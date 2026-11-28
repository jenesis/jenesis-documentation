# Greenfield experiment - design notes

The question: an agent given one written specification implements the same service from scratch in Java and
in Rust (Go and others later). What does each language cost to develop, how often is the result right, and how
fast is the warm result? This folder is the task, its acceptance suite, the reference used to validate that
suite, and the load-test design.

| Path | What it is | Shown to the agent |
|---|---|---|
| `SPEC.md` | The specification: 81 numbered rules, 14 endpoints | yes |
| `conformance/run.py`, `lib.py` | Runner and helpers, Python 3 standard library only | yes |
| `conformance/visible/` | 33 tests | yes |
| `conformance/hidden/` | 99 tests | no - decides the verdict |
| `reference/server.py` | Single-file standard-library implementation (about 640 lines) | **never** |
| `load/PLAN.md` | Load-test design | no |

`PORT=18731 python3 reference/server.py &` then `python3 conformance/run.py http://localhost:18731` prints
`PASSED 132/132` (`--only visible` / `--only hidden` select a half; `-v` adds the assertion). The whole suite
takes about two seconds against the reference.

## Design decisions

**Domain.** Lock passage tolls and delay rebates for an invented canal authority, the Kestle & Wendle Navigation.
Canal tolls exist in the world, but nothing about these is real: the nine locks, their lifts and adjacency,
the vessel classes and their lift rates, the length bands, the repeat-passage halving, the weight threshold,
the cargo percentages, the night/weekend band with its pre-multiplied combined rate 0.2508, the tier rules
(heritage only for narrowboats), the 7.50 minimum, the rebate bands with a per-30-minute increment, halving for
water level *before* the 40 % cap, the operator check digit `(3·L1 + L2 + 7·d1 + d2) mod 10`, the four-eyes rule,
the 48-hour settlement wait, the single 7-day reopen. None of it can be recalled; all of it must be read.

**Where the difficulty is.** Exact decimal arithmetic with two rounding modes applied at stated points (half-even
to 4 places for every intermediate, half-up to 2 for the total); a validation order that decides which of
several errors is reported; a mixed sort order (`enteredAt` descending, `id` ascending); idempotency that replays
before validation and expires by the injected clock; boundaries that are inclusive on one side only (30-day
staleness, 14-day claim window, 7-day reopen, 48-hour settlement, night from 22:00 to 05:59:59). The mutation
check below shows every one of these is pinned by at least one hidden test.

**Language neutrality.** Money and tonnage are JSON strings, so no language is pushed into binary floating point
by its JSON parser and every language needs the same explicit decimal handling (Java `BigDecimal`, Rust a decimal
crate or scaled integers, Go `math/big` or a decimal module). Integers are small. The spec names no library,
annotation, ORM, thread model or file layout; the only process contract is `./build` and `PORT=<n> ./run`.

**Time.** A service clock set by `PUT /admin/clock`; the machine clock is never read. Every test resets the
service and sets the clock, so tests are independent and order-free.

**Persistence: none.** The one exception the brief allowed - an append-only journal that a restart replays - is
left out. It would need its own precisely specified record format, fsync rule and recovery semantics (a torn last
line, a journal written by a crashed import), it puts disk I/O into the load figures, and its tests must kill
and restart the process, which makes the suite slower and the harness more fragile. None of that bears on the
question asked. If wanted later it is a clean add-on: one section, "R17 journal", and a hidden test class that
restarts the service between two halves of a scenario.

**CPU-bound and allocation-bound endpoints.** `POST /tariff/quotes` (up to 5 000 specifications, about 20 decimal
operations and four roundings per lock, up to 12 locks each) is the CPU path. `GET /passages?limit=200` over a
store of 50 000 records is the allocation and serialisation path: filter, sort, and write about 250 KB of nested
JSON per response. Both are measured by the load plan; neither is dominated by a shared C library.

**Size.** Big enough that development cost differs, small enough for five runs per language. The reference is
about 640 dense lines of Python with a decimal type, a JSON codec and an HTTP server all in the standard library.
Estimates for a typed implementation, tests the agent writes excluded:

| Language | Lines (estimate) | Note |
|---|---|---|
| Java (JDK HTTP server + a JSON library) | 1 500 - 2 200 | records for requests, `BigDecimal`, hand validation |
| Rust (axum/tokio + serde_json + a decimal crate) | 1 300 - 2 000 | validation by hand on `serde_json::Value` (the error order defeats derive-based validation) |
| Go (net/http + encoding/json) | 1 400 - 2 000 | no decimal in the standard library |

That is consistent with 30 to 90 minutes for a strong agent. The spec is about 4 900 words; reading it is a
fixed cost shared by every arm.

## Validating the suite

The full suite passes against the reference. Each of these single-line faults in a copy of the reference makes
the hidden suite fail, naming the rules shown (the visible suite alone misses five of the eight):

| Mutation | Hidden rules failing | Visible fails? |
|---|---|---|
| half-up instead of half-even at 4 places | R4.3, R4.5, R4.9 | yes |
| half-even instead of half-up for the total | R4.9 | no |
| listing tie-break by `id` descending | R8.3 | yes |
| no repeat-passage halving | R4.3, R4.7, R10.3, R13.3 | yes |
| staleness boundary inclusive | R6.1 | no |
| lock fee via binary floating point | R4.3 | no |
| cap applied before the water-level halving | R10.3 | no |
| idempotency keys never expire | R7.5 | no |

Spec defects found while making the reference pass, and fixed in `SPEC.md`: worked example 3 used a 25.0 m
narrowboat on a narrow lock, which its own gauge rule refuses (now 22.0 m); the statement example's figures read as
normative (now marked as shape only); `null` for an optional field was undefined; the import's `Content-Type`,
repeated and unknown statement parameters, and whether a response may carry extra fields were unstated.

## Known weaknesses and threats to validity

- **The model knows the languages unequally.** Training data has more Java than Rust and more web-service Rust in
  axum than in anything else. This is part of what "write everything in Rust" claims to be free of, so it is a
  finding, not noise - but say so when reporting.
- **Stack choice dominates start-up and memory.** A Spring Boot service and a JDK-`HttpServer` service differ by
  seconds of start-up and hundreds of megabytes; the language does not. Without a rule the experiment measures
  what the agent happened to reach for. See the recommendation below.
- **The JVM's defaults.** Heap size, GC and whether `./run` uses AppCDS or a native image change RSS and start-up
  more than code does. Record the `./run` line; decide whether flags are fixed by the harness.
- **Dependency download time.** Cold Maven or Cargo caches would add network time to "build seconds". Warm both
  caches with the allowed libraries before the run, as the bug-fix experiment does, and record cache misses.
- **Compile-error versus failed-test counting.** Needs shims on `PATH` (`cargo`, `rustc`, `mvn`, `javac`, `java`,
  `python3 conformance/run.py`) that log command, exit code and duration, classified afterwards: a non-zero
  compiler exit is a compile error, a non-zero test or conformance run after a successful compile is a failed
  test. The existing `calls.py` is the place to extend.
- **The visible suite as an oracle.** An agent can iterate against it. That is realistic and the same in both
  arms; record how many times it ran. Hidden tests reach rules the visible ones do not, so overfitting the visible
  set does not pass.
- **Linearisability is tested lightly** (one race of eight concurrent transitions on one version). A service
  with a data race elsewhere may pass. The load test's error count is the second line of defence.
- **Exact response shapes.** Tests compare whole objects for operators, passages, claims, audit entries and the
  statement (R1.11 says so). An agent adding a field fails those tests; that is a rule-reading failure, which is
  what is measured, but it concentrates failures on a few rules.
- **Linear scans.** Nothing requires an index; the listing and the statement scan. An agent that adds an index
  wins scenario B for reasons unrelated to the language. Report it with the result.
- **One task.** One domain is one sample of "back-office service". Five runs per language measure the agent's
  variance, not the task's.

## Recommendation: prescribe the stack, minimally

Prescribe one HTTP server and one JSON library per language - the ecosystem's default rather than the fastest -
allow a decimal library where the standard library has none, and forbid everything else (frameworks, dependency
injection, validation libraries, databases):

| Language | HTTP | JSON | Decimal | Build |
|---|---|---|---|---|
| Java | JDK `com.sun.net.httpserver` (with a virtual-thread executor) | Jackson `databind` | `BigDecimal` | Maven, as the bug-fix experiment |
| Rust | `axum` on `tokio` | `serde_json` | `rust_decimal` | Cargo, `--release` |
| Go | `net/http` | `encoding/json` | `shopspring/decimal` or `math/big` | `go build` |

Why: the claim under test is about languages, and a free choice turns it into a claim about frameworks (Spring
versus axum would be decided by Spring's start-up). The Rust row is what an agent told "write it in Rust" would
choose anyway, so it does not handicap Rust; the Java row is the equally idiomatic minimal choice, and does not
handicap Java with a framework it would not need. Plain `std` Rust (no async runtime, no HTTP crate) is not
recommended: it forces the agent to write an HTTP/1.1 parser, which measures something else and is not what
anyone means by the claim. A second arm with a free stack can follow if the prescribed result is in doubt;
record the choice the agent makes there, since that is itself a finding.

Pre-warm the caches with exactly these libraries, at pinned versions, so that a run never downloads.

## Open decisions

1. Prescribe the stack (recommended above) or leave it free, or both as two arms.
2. Persistence: keep the in-memory-only design, or add the journal section.
3. JVM flags: fixed by the harness (for example `-Xmx512m -XX:+UseSerialGC` or nothing), or the agent's own.
4. The conformance threshold for entering the load test (proposed 95 % of hidden tests).
5. Whether the agent may see the visible suite at all, and whether it is told the hidden suite exists (the
   spec's §16 says so now).
6. Model, effort and a wall-clock cap per run (proposed: 120 minutes, scored as failed if exceeded).
7. The fixed load rates, to be set after a pilot on the slowest passing implementation.
