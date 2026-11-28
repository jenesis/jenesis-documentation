# Load test plan

What the load test measures is the warm service an agent wrote, not the agent. It runs after the conformance
verdict, only on implementations that pass the hidden suite at or above a threshold (proposed: 95 %), so that a
fast but wrong service is never ranked. Everything below is a design; nothing here is implemented yet.

## Tool

**vegeta** (a single static binary, downloaded from its GitHub release into the harness folder, no root), driven
by target files the harness generates. Reasons:

- It is *open-model*: `-rate=N/s` sends at a fixed arrival rate whatever the server does, and latencies are
  measured from the intended send time, so a stalling server (a GC pause, a lock) shows in p99 instead of
  silently lowering the offered load (coordinated omission). That is what "a fixed load" has to mean.
- A target file carries method, URL, headers and a body file per request, so a request mix and per-request
  unique bodies (needed for `POST /passages`, which refuses duplicates) are plain data, generated once per
  seed and identical for every language.
- It reports HDR percentiles (`vegeta report -type=hdrplot`) and writes raw results we keep.
- It is cheap per request and written in neither language under test.

Considered and not chosen: **wrk2** (also open-model and lighter, but must be compiled and the mix lives in
Lua - a fine fallback if vegeta's own CPU becomes the limit); **wrk / oha / hey** (closed-model only, so they
measure throughput under saturation but understate tail latency); **k6** (scriptable, but its JavaScript VM
costs several times more CPU per request than the services under test, which on four cores is the problem
this plan has to avoid); a **Python standard-library driver** (the GIL caps it at a few thousand requests per
second, below what a compiled service answers - the driver would be what is measured). A small Python script is
still used for everything that is not load: seeding, start-up timing, RSS sampling.

## Machine discipline on four cores

- Service pinned to cores 0-1, driver to cores 2-3 (`taskset -c`); the sampler and harness on core 3 at nice 10.
  Two cores for the service is deliberate: it is enough to show a runtime's concurrency, and leaves the driver
  headroom.
- The driver's CPU is sampled from `/proc/<pid>/stat` every second. A measurement window in which the driver
  exceeds 70 % of its two cores is discarded and re-run at a lower rate. Before the first real run, calibrate:
  run each scenario against a deliberately trivial responder (the service's own `GET /admin/clock`) to find the
  driver's ceiling on this machine, and keep every scenario's rate below half of it.
- Nothing else runs: no build, no conformance suite, no other experiment. Frequency scaling set to
  `performance` where the machine allows it; otherwise record the governor.
- Loopback only; keep-alive on (vegeta's default), `-max-connections` capped per concurrency level.

## Procedure per implementation

1. `./build` is not timed here (development cost is measured in the agent run). Record the size of the deployable
   artefact: the files `./run` executes from the project folder (a jar and its dependency jars, or a binary),
   excluding the toolchain and the JDK. Also record whether the binary is statically or dynamically linked, and
   for the JVM the flags `./run` passes.
2. **Start-up**, 20 trials: from `exec ./run` to the first `200` on `GET /admin/clock`, polled every 5 ms with a
   connect timeout of 50 ms. Report median and max. Then idle RSS 2 s after the first 200.
3. **Seed** (not timed): `POST /admin/reset`, `PUT /admin/clock` to `2026-03-20T12:00:00Z`, register 200
   operators (all three tiers), import 50 000 passages in five atomic imports of 10 000 lines (deterministic
   seed: classes, lengths, cargo, routes and `enteredAt` spread over the 30-day window; marks unique), lodge 5 000
   claims and move 3 000 of them through the workflow. Record RSS after seeding.
4. Run each scenario below: **warm-up 60 s** at the scenario's rate (results discarded; long enough for C2 to
   compile the hot paths, verified once in a pilot by checking that a further 60 s warm-up changes p50 by less
   than 5 %), then **measure 120 s**. Three repetitions per scenario, the service restarted and re-seeded between
   repetitions; report the median repetition.
5. During every window, sample RSS of the whole process tree (`./run` may be a wrapper) every second from
   `/proc/<pid>/status` (`VmRSS`), and report mean and peak.

## Scenarios

Rates are absolute and identical for every language, fixed once after a pilot on the slowest passing
implementation (proposed: 60 % of its saturation throughput for that scenario, rounded). A second, per-language
"capacity" figure is the highest rate at which p99 stays below 100 ms and errors below 0.1 %, found by stepping
the rate in 10 % increments; this is the throughput number.

| Scenario | Request | What it stresses |
|---|---|---|
| **A. CPU** | `POST /tariff/quotes`, 1 000 items per body (about 250 KB), 16 distinct bodies rotated | Decimal arithmetic and the rule engine, JSON parse of a large body |
| **B. JSON** | `GET /passages?limit=200&offset=<k>` with one of `operator=`, `cargo=`, `from=&to=` or none, offsets spread over the result | Filtering and sorting 50 000 records, serialising 200 nested objects (about 250 KB per response), allocation and GC |
| **C. Mixed** | 40 % `GET /passages/{id}`, 15 % `POST /passages` (unique body each), 15 % `GET /passages?limit=50&operator=…`, 10 % `POST /tariff/quotes` (20 items), 10 % `POST /claims` (unique passage and lock), 5 % `GET /claims/{id}`, 5 % `GET /reports/operator-statement` | A realistic blend: small writes under the single-writer rule, point reads, a scan per statement |

Scenario C needs per-request unique bodies: the generator writes rate × (warm-up + measure) × share of them, so
no body repeats within a repetition and every `POST` is expected to answer `201`. Any other status in A, B or
C counts as an error; an error rate above 0.1 % invalidates the window.

Concurrency levels: the open model sets the rate, not the concurrency; `-max-connections` is run at 8, 32 and 128
for the capacity search to show how each runtime behaves with many idle keep-alive connections. The headline
figures use 32.

## What is recorded

Per implementation and scenario: offered rate, achieved rate, error count by status, p50 / p90 / p95 / p99 /
p99.9 / max latency, capacity throughput, mean and peak RSS, driver CPU, service CPU (user + system seconds from
`/proc`, which gives CPU per request - often the fairest single number on a pinned machine). Per implementation:
start-up median and max, idle RSS, RSS after seeding, artefact size. Raw vegeta result files are kept.

## Threats specific to the load test

- A service that is faster because it skipped a rule. The conformance threshold guards this; the load scenarios
  only touch endpoints whose hidden tests passed, otherwise the scenario is reported as not run.
- Linear scans by design: nothing in the specification asks for indexes, so scenario B and the statement measure
  whether the agent added one. That is a property of the code written, which is part of what we compare, but it
  must be reported beside the language result, not hidden in it (record whether `GET /passages?operator=` cost
  grows with the store: run B once with 10 000 and once with 50 000 passages).
- A global lock is the simplest way to honour R0.3 and caps throughput at one core for writes; reads may or may
  not take it. Report it rather than prescribing it.
