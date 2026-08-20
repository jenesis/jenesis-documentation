---
order: 11
title: Observability
description: How the repository reports on itself - one instrumentation point that feeds logs, metrics and traces at once; the Micrometer naming convention and the tags it keeps off your meters; the Actuator and Prometheus endpoints; and the OTLP tracing you switch on with two settings.
---

A repository you run in anger needs to tell you what it is doing: which uploads were rejected, how
often a proxy leg misses its cache, how many sign-ins failed. Jenesis Repository is a Spring Boot
application, so it reports through the standard **Actuator** endpoints and the **Micrometer**
metric façade - nothing bespoke to learn. What is worth knowing is how it wires those together, and
which two settings turn distributed tracing on.

## One instrumentation point, three signals

Every meaningful operation in the server - a proxy fetch, a publish decision, an import, a console
action - is wrapped once, at a single instrumentation point, as a **Micrometer observation**. From
that one wrap the framework fans out three signals:

- a **log line** when the operation finishes,
- a **metric** (a timer, and a count of errors), and
- a **trace span** - but only when a tracing bridge is on the module path (see *Traces*, below).

You never choose per-call which signals to emit. Instrument once; configure what leaves the process
with the settings at the end of this chapter.

### The naming convention

Observations are named `jenreg.<area>.<signal>` - for example `jenreg.proxy.fetch` for a
pull-through cache leg, or `jenreg.gc.collected` for reclaimed objects. When you scan a metrics or
trace backend, everything the repository itself raises sits under the `jenreg.` prefix; the Spring
and Tomcat meters keep their own.

### High-cardinality context vs. metric tags

Each observation carries the **repository** and **tenant** it ran under. These are recorded as
**high-cardinality key-values**: they ride along on logs and trace spans, where you want to filter by
them, but they are deliberately **kept off the metric tags**. A busy deployment can hold
thousands of repositories, and turning each into a metric dimension would multiply your time series
past what a metrics backend can hold.

What *does* become a metric tag is a small, bounded **outcome**: the proxy-fetch meter is tagged with
its `format` and an `outcome` of `hit`, `miss` or `negative`; a publish observation carries its
verdict; an import carries its source. These are low-cardinality by construction, so grouping a chart
by them stays cheap.

<div class="note">
  An operation that runs before a tenant or repository is resolved - a deployment-wide sweep, a
  request rejected at the door - records <code>none</code> for the missing value rather than failing.
  So a dashboard filter on repository always has something to match.
</div>

## Logs

The logging signal is always on. Each observation logs exactly **one line** when it completes, under
the logger `build.jenesis.observation`, carrying the observation name, its key-values (repository,
tenant, any outcome) and - if the operation failed - the error. A successful operation logs at
`INFO`; a failed one at `WARN`.

Because it is a plain SLF4J logger, you tune it like any other. Raise it to `WARN` to see only
failures, or route it to its own appender:

```properties
logging.level.build.jenesis.observation=WARN
```

When tracing is enabled, each of these lines also carries the current **trace and span ids**, so you
can pivot straight from a log entry to the full trace.

### Reading the recent ones without shell access

You do not always have the log file to hand - a container that ships its output elsewhere, or a colleague
diagnosing a publish from the console. The server keeps its **last 1000 entries in memory** and serves them
at `GET /api/logs`, filtered by `level`, searched with `q`, and tailed with a `since` cursor:

```bash
curl -H "Jenesis-Repository-Key: $KEY" 'https://repo.example.com/api/logs?level=WARN&q=publish'
```

The console surfaces the same thing as a **Logs** panel. It is a bounded ring, never a file re-read, so it
costs a fixed amount of memory and cannot grow: `jenreg.logs-buffer` sets how many entries it
holds. Reading it is authorised like every other read.

## Metrics

Metrics are exposed through Spring Boot Actuator. By default the server publishes three Actuator
endpoints, over the same HTTP port as the repository:

| Endpoint | Serves |
|----------|--------|
| `/actuator/health` | Liveness and readiness. Kubernetes-style **probes** are enabled; full details show only to an authorised caller. |
| `/actuator/info` | Build and application information. |
| `/actuator/metrics` | The Micrometer meter registry - every `jenreg.*` observation timer plus the JVM, Tomcat and HTTP meters. |

<div class="tip">
  The health probes are never rate-limited, so an aggressive
  <a href="/repository/rate-limiting-usage/"><code>rate-limit</code></a> setting can never make your
  orchestrator think the server is down.
</div>

Beyond the per-operation timers, each capability publishes the few numbers that describe its own state:

| Meter | Reports |
|-------|---------|
| `jenreg.proxy.fetch` | One timer per pull-through leg, tagged by format and outcome. Chart the miss rate to see how much load [proxying](/repository/proxying/) sheds upstream. |
| `jenreg.proxy.revalidation.entries` | Index bodies held for conditional revalidation, a bounded gauge. |
| `jenreg.quota.capacity` | The storage ceiling, against which stored bytes are measured. |
| `jenreg.ratelimit.buckets` | How many rate-limit buckets are live. |
| `jenreg.usage.tracked` / `.dropped` | Credential uses recorded, and uses shed because the tracking queue was full. |
| `jenreg.walk.resumes` | How often an artifact walk resumed a segment rather than starting one. |
| `jenreg.gc.condemned` / `.collected` | Objects marked unreferenced, and objects actually reclaimed. |
| `jenreg.consistency.nodes` / `.diverged` | Live nodes compared, and how many are diverged rather than lagging. |

Health checks sit beside them under `/actuator/health`: `jenreg.proxy.negativecache`,
`jenreg.proxy.revalidation`, `jenreg.ratelimit.limiter`, `jenreg.usage.worker` and
`jenreg.consistency.divergence` each report whether their own machinery is doing its job.

<div class="note">
  Authentication failures and shed requests are <em>recorded</em> by the components that refuse them -
  tagged by mechanism and outcome, and by the bucket a request metered against - but the core registers no
  meter of its own for them. A deployment that wants them charted surfaces them through whatever metrics
  layer it installs, which is why they are absent from the table above.
</div>

### Prometheus

The base server exposes metrics in Actuator's own JSON. To scrape with **Prometheus**, a distribution
puts a Prometheus registry on the module path and adds `prometheus` to the exposed endpoints:

```properties
management.endpoints.web.exposure.include=health,info,metrics,prometheus
```

Prometheus then scrapes `/actuator/prometheus`, and the same `jenreg.*` meters appear in its text
exposition format with no further wiring.

## Traces

Distributed tracing is **off until you opt in**. The instrumentation is always present - every
observation is span-ready - but a span is only recorded and exported when a **tracing bridge** is on
the module path. With one there, you turn tracing on with the standard Micrometer settings: a sampling
probability, and an **OTLP** endpoint to export spans to.

```properties
# Sample every request while you investigate; dial down in production.
management.tracing.sampling.probability=1.0
# An OpenTelemetry collector speaking OTLP over HTTP.
management.otlp.tracing.endpoint=http://otel-collector:4318/v1/traces
```

Each span carries the same repository and tenant key-values as its log line and inherits the
`jenreg.<area>.<signal>` name, so a trace reads as the operation it measures. And because the log
line now carries the trace id, a warning in your logs links straight to the trace that produced it.

<div class="warning">
  Sampling at <code>1.0</code> traces every request - right for a short investigation, expensive as a
  standing default. Lower <code>management.tracing.sampling.probability</code> to a small fraction once
  you are done, or leave tracing off entirely and rely on metrics and logs.
</div>

## Security posture

Metrics tell you how the server is behaving; the **security posture** tells you how it is *configured*. Each
module reports advisories about its own settings - a pure function of configuration, so reading it never
changes anything - and the server collects them at `GET /api/posture` and on a console panel.

```bash
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/posture
```

Each advisory carries an id, a severity, what is unsafe about the setting and what to do instead - so a
deployment running open (`jenreg.auth.open`), one seeding demo data into a writable space
(`jenreg.demo.writable`), one whose console accepts a wildcard origin (`jenreg.console.wildcard`) or whose
import edge will follow a private address (`jenreg.importer.ssrf`) says so out loud, at boot and on every
read of the endpoint.

A module that is absent, or switched off, reports nothing - so the posture is a picture of what this
deployment actually runs rather than a checklist of everything the product could do.

## Running more than one node

Several server nodes over one shared store are **eventually consistent by design**: each derives its own
indexes from the store, so at any instant one may be slightly behind another. That is normal and harmless -
what matters is telling it apart from a node that has stopped catching up.

Each node therefore publishes a small **fingerprint** of its derived state on a heartbeat - its cursor, its
config generation, a few counters and a sampled set of pointers - and `GET /api/consistency` compares the
fingerprints of the nodes currently alive:

```bash
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/consistency
```

The comparison distinguishes two things. A node that is **behind but still advancing** inside the staleness
window is benign lag, and is reported as such. A node that is **alive but frozen** - its cursor unmoved for
several sweeps - or that disagrees about something which must be identical, like the configuration
generation or where a pointer resolves, is **diverged**, and that is a problem to act on.

It **detects and reports; it never blocks a request**. A divergence surfaces three ways: as a
security-posture advisory naming the node and the fix, as metrics
(`jenreg.consistency.nodes`, `jenreg.consistency.diverged`) with a matching health check, and as a
**Consistency** panel in the console.

<div class="note">
  Off by default, because a single node has nothing to compare itself against and would only write
  heartbeats into an otherwise clean store. A multi-node deployment sets
  <code>jenreg.consistency.enabled=true</code> and gives each node its own
  <code>jenreg.consistency.node-id</code> - both per node rather than shared, since they describe the
  instance rather than the deployment. It degrades cleanly: one node reports no divergence rather than a
  false positive.
</div>

<div class="tip">
  This is what makes the per-instance caveat on the metrics above safe to rely on. The numbers a node
  reports are its own, so a fleet reading one node's metrics sees one node's view - the consistency check
  is how you learn whether that view is representative.
</div>

## Settings

The observability knobs are the standard Spring Boot properties; set them as system properties
(`-Dmanagement.…`), environment variables, or in the deployment's configuration.

| Key | Default | Meaning |
|-----|---------|---------|
| `management.endpoints.web.exposure.include` | `health,info,metrics` | Which Actuator endpoints are served. Add `prometheus` to expose `/actuator/prometheus`. |
| `management.endpoint.health.probes.enabled` | `true` | Serve separate liveness and readiness probes. |
| `management.endpoint.health.show-details` | `when-authorized` | Show full health detail only to an authorised caller; anonymous callers see up/down alone. |
| `logging.level.build.jenesis.observation` | `INFO` | Verbosity of the one-line-per-operation log. Raise to `WARN` for failures only. |
| `management.tracing.sampling.probability` | `0.0` | Fraction of operations traced. `0` records no spans; `1.0` traces everything. Needs a tracing bridge on the path. |
| `management.otlp.tracing.endpoint` | - | Where to export spans over OTLP. Unset means no export even when sampling is above zero. |

Metrics and logs need no extra infrastructure - they are on the moment the server starts. Tracing is
the one signal that asks for a bridge on the module path and a collector to receive it.
