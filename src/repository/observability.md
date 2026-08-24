---
order: 10
title: Observability
description: How a running Jenesis Repository reports on itself - recent logs over HTTP, health and metrics endpoints, the security-posture advisories, and the consistency check for a multi-node deployment.
---

A repository you depend on needs to answer three questions: what is it doing, is it healthy, and is it
configured safely. Jenesis Repository answers them over plain HTTP, so a console, a script or a monitoring
system reads the same endpoints. This chapter covers the log tail, the health and metrics endpoints, the
security-posture report, and the consistency check across several nodes.

## Who may read these endpoints

`GET /api/logs`, `GET /api/consistency` and the `/actuator` endpoints show deployment-wide state - every
repository's log lines, every node, every metric. They are therefore gated to a key that holds a
deployment-wide `*` grant; a key scoped to one repository is refused, and so is a keyless caller even when
anonymous read rights are granted. On a deployment that runs with authentication off, anyone can read them.
`/actuator/health` is always open, so probes need no credential.

## Recent logs

The server keeps its most recent log entries in memory and serves them at `GET /api/logs`, which lets you read
the tail without shell access to the host:

```bash
curl -H 'Jenesis-Repository-Key: jenk_…' \
  'http://localhost:8080/api/logs?level=WARN&q=proxy&limit=50'
```

```json
{"cursor":1834,"count":2,"entries":[
  {"seq":1821,"timestamp":"2026-08-21T09:14:02.118Z","level":"WARN",
   "logger":"build.jenesis.observation","message":"jenreg.proxy.fetch [format=maven, outcome=miss] failed: …",
   "tenant":"default"}]}
```

| Parameter | Meaning |
|---|---|
| `level` | The minimum level to return (`INFO`, `WARN`, `ERROR`). |
| `q` | A substring matched against the logger name and the message. |
| `since` | A sequence number; only entries after it are returned. Use the `cursor` of a previous response to tail. |
| `limit` | The most entries to return (default 200). |
| `tenant` | Restrict to entries stamped with this tenant. |

The buffer holds the last 1 000 entries by default (`jenreg.logs-buffer`); older lines are gone from this
view, but still reach your normal log output. Each entry carries a `seq`, so polling with `since=<cursor>`
never repeats or skips a line.

The server's own operations log under the logger `build.jenesis.observation`: a completed operation at
`INFO`, a failed one at `WARN` with its error. Today the one operation instrumented this way is the proxy
fetch, `jenreg.proxy.fetch`, tagged with the `format` it served and the `outcome` - `hit` (served locally),
`miss` (fetched from the upstream) or `negative` (the upstream did not have it either, whether that `404`
was fresh or remembered). Filter on `q=proxy.fetch` to watch your pull-through cache work. The same logger
writes one line per HTTP request, `http.server.requests`, with its method, path and status - the server's
access log; nothing else is logged per request.

## Health and metrics

The server exposes three Spring Boot Actuator endpoints: `/actuator/health`, `/actuator/info` and
`/actuator/metrics`. Health serves the liveness and readiness probes (`/actuator/health/liveness`,
`/actuator/health/readiness`) a container platform expects, is never rate-limited, and is readable without a
credential. Its detail is shown only to an authorised caller (`management.endpoint.health.show-details` is
`when-authorized`); an anonymous probe sees up or down alone.

`/actuator/metrics` lists the JVM and HTTP request meters Spring Boot collects - request counts by URI and
status, memory, threads. The proxy-fetch operation described above is also an observation, so a Micrometer
registry on the module path receives it as a timer tagged with `format` and `outcome`. The server ships no
*exporting* registry of its own: Spring Boot auto-configures an in-memory one, which is what this endpoint
serves, and forwarding the numbers to a monitoring system means adding that system's registry.

### What the modules report

Beside those meters, each installed module reports signals of its own, named `jenreg.<area>.<signal>`. The
console's **Metrics overview** panel lists them with their current values and a line of description each. A
module that is absent, or whose feature is switched off, reports nothing rather than an empty row - so the
panel shows what this deployment is doing, not a fixed catalogue.

| Signal | Kind | Reports |
|---|---|---|
| `jenreg.listing.materialised` | counter | Listing documents generated from the store, on first use or a rebuild. |
| `jenreg.listing.updates` | counter | Listing documents rewritten on the write path. |
| `jenreg.listing.coalesced` | counter | Listing changes that rode along another writer's rewrite instead of making their own. |
| `jenreg.listing.conflicts` | counter | Listing writes retried because another node changed the document first. |
| `jenreg.listing.forgotten` | counter | Listing documents dropped for regeneration after a write could not land. |
| `jenreg.proxy.negativecache.entries` | gauge | Upstream `404`s remembered, so a re-probe is answered without re-hitting the upstream. |
| `jenreg.proxy.negativecache` | health | That the negative cache is installed and remembering upstream misses. |
| `jenreg.proxy.revalidation.entries` | gauge | Proxied indexes held with their validator, so a re-fetch is a conditional request. |
| `jenreg.proxy.revalidation.bytes` | gauge | Bytes those held indexes occupy, against the ceiling past which the oldest are evicted. |
| `jenreg.proxy.revalidation` | health | That the revalidation cache is installed and saving index transfers. |
| `jenreg.quota.used` | gauge | Stored bytes counted against the storage quota, when one is set. |
| `jenreg.quota.capacity` | health | Headroom under that quota; degraded once usage reaches the ceiling and a fresh blob is refused. |
| `jenreg.ratelimit.buckets` | gauge | Rate-limit buckets tracked, one per metered tenant; `0` while no limit is set. |
| `jenreg.ratelimit.limiter` | health | That the token-bucket limiter is installed and metering requests. |
| `jenreg.usage.tracked` / `.queue` / `.dropped` | gauge, gauge, counter | Credential-use accounting: accumulators held, hits waiting to drain, and hits dropped under back-pressure. Needs `jenreg.track-key-usage`. |
| `jenreg.usage.flush` | task | The worker draining those buffered hits. |
| `jenreg.usage.worker` | health | That the worker thread is running and draining hits off the request path. Needs `jenreg.track-key-usage`. |
| `jenreg.rebuild.pass` | task | The scheduled rebuild pass; reported as disabled, with the reason, when none is scheduled. |
| `jenreg.consistency.nodes` / `.diverged` | gauge | Live nodes sharing the store, and how many have diverged; both `0` until `jenreg.consistency.enabled` is on. |
| `jenreg.consistency.divergence` | health | Whether any node has diverged - detect-only, and never blocks a request. |

A counter accumulates for the life of the process, a gauge is a current reading, a task carries its last
run and outcome, and a health check reads `UP`, `UNKNOWN`, `DEGRADED` or `DOWN`, with a line saying why.

## Security posture

`GET /api/posture` lists every setting that leaves the deployment less safe than it could be, each with the
reason and the exact key and value that fix it. It never echoes a secret, so it is safe to surface on a
dashboard:

```bash
curl -H 'Jenesis-Repository-Key: jenk_…' http://localhost:8080/api/posture
```

```json
{"count":2,"critical":1,"warn":1,"info":0,"advisories":[
  {"id":"jenreg.auth.open","severity":"CRITICAL","scope":"DEPLOYMENT","tenant":null,
   "title":"Authorization is disabled - the instance is fully open",
   "why":"…","fix":"…","settingKey":"jenreg.auth","settingValue":"true","docs":"…"}]}
```

The advisories the server raises:

| Id | Severity | Raised when |
|---|---|---|
| <span id="jenreg.auth.open">`jenreg.auth.open`</span> | critical | `jenreg.auth=false` - every request is served anonymously. |
| <span id="jenreg.profile.dev">`jenreg.profile.dev`</span> | critical | The `dev` Spring profile is active, so the console runs its local-only form login. |
| <span id="jenreg.anonymous.write">`jenreg.anonymous.write`</span> | critical | `jenreg.anonymous-rights` grants a keyless caller write or manage rights. |
| <span id="jenreg.anonymous.enabled">`jenreg.anonymous.enabled`</span> | warn | `jenreg.anonymous-rights` grants a keyless caller read rights (the public-mirror pattern). |
| <span id="jenreg.importer.ssrf">`jenreg.importer.ssrf`</span> | warn | `jenreg.block-private-import-hosts=false` - an import may reach internal hosts or run over plaintext. |
| <span id="jenreg.ratelimit.unset">`jenreg.ratelimit.unset`</span> | warn | `jenreg.rate-limit` is unset or `0`, so nothing throttles a client. |
| <span id="jenreg.console.wildcard">`jenreg.console.wildcard`</span> | warn | `jenreg.ui.admins` contains `*`, making every signed-in console user an admin. |
| <span id="jenreg.demo.writable">`jenreg.demo.writable`</span> | warn | `jenreg.demo=true` without `jenreg.read-only=true` - a seeded demo anyone can write to. |

A clean deployment returns an empty list. The same report is shown in the console's **Security posture**
panel, and every advisory scoped to the deployment is also logged once at boot.

<div class="note">
  On an enforcing server the posture read needs a key with a deployment-wide <code>*</code> grant, like the
  other reads above. Unlike them, it is also readable by a keyless caller once
  <code>jenreg.anonymous-rights</code> grants read rights, since it never reveals a secret. With authentication
  off, anyone reads it.
</div>

## Running more than one node

Every node is stateless; the store is the only state, so several nodes behind a load balancer share one
bucket or one mounted directory and serve the same content. Each node derives some state from the store -
its view of the index, its configuration - and a node that falls behind or is configured differently would
answer differently from its peers. The consistency check makes that visible.

Switch it on with `jenreg.consistency.enabled=true` on every node. Each node then publishes a small
fingerprint of its derived state to the store on a heartbeat, and `GET /api/consistency` on any node compares
all of them:

```bash
curl -H 'Jenesis-Repository-Key: jenk_…' http://localhost:8080/api/consistency
```

```json
{"localNodeId":"repo-2","nodeCount":3,"liveCount":3,"converged":true,"singleNode":false,"truncated":false,
 "nodes":[{"nodeId":"repo-1","live":true,"stale":false,"heartbeatAgeMillis":4120,
           "indexCursor":128934,"snapshotVersion":"…","configGeneration":"3f2a…",
           "inventoryTotal":12894,"quotaUsed":73400320,"local":false}],
 "divergences":[]}
```

A node is **live** while its heartbeat is younger than `jenreg.consistency.dead-after`; only live nodes take
part in the comparison, and a fleet of one live node is always converged. A node whose last heartbeat is older
than `staleness-window` is flagged `stale` but stays in the comparison until `dead-after`. Three kinds of
divergence are reported, and each also appears in the security-posture report under its own id:

| Id | Meaning |
|---|---|
| <span id="jenreg.consistency.config">`jenreg.consistency.config`</span> | A live node's configuration generation differs from the freshest node's - it missed a configuration change or is split from the fleet. |
| <span id="jenreg.consistency.stuck">`jenreg.consistency.stuck`</span> | A node's index cursor has lagged behind the furthest node for longer than `sweep-interval × sweep-intervals` without advancing. Lag within that budget is not a divergence. |
| <span id="jenreg.consistency.pointer">`jenreg.consistency.pointer`</span> | Two live nodes resolve the same pointer to different content - a client would get different bytes depending on which node answers. |

The check only reports; it never blocks a request.

A node names itself with `jenreg.consistency.node-id`; unset, it uses the hostname, and falls back to a
generated id (with a warning) only when no hostname is available. Give each node a stable id so a restart
re-uses its fingerprint. Without the setting switched on, a node publishes nothing and writes no operational
keys into the store.

A fingerprint whose node has been silent for longer than `jenreg.consistency.forget-after` (a day by default)
is deleted by a publishing node, which reaps at most once an hour, so a fleet that gives every restart a
fresh hostname does not accumulate a fingerprint per host it ever ran on. A report reads at most 1 000
fingerprints; past that it answers with `"truncated":true` and compares the ones it read.

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.logs-buffer` | `1000` | Entries the in-memory log ring keeps for `GET /api/logs`. |
| `jenreg.consistency.enabled` | `false` | Publish this node's fingerprint and take part in the consistency check. |
| `jenreg.consistency.node-id` | the hostname | The node's stable name in the report. |
| `jenreg.consistency.heartbeat` | the sweep interval | Milliseconds between fingerprint publications (at least 1 000). |
| `jenreg.consistency.sweep-interval` | `60000` | Milliseconds per sweep; with `sweep-intervals`, the budget a lagging node has before it is stuck. |
| `jenreg.consistency.sweep-intervals` | `3` | Sweeps a lagging node may take to catch up. |
| `jenreg.consistency.staleness-window` | `300000` | Milliseconds since a node's last heartbeat after which it is flagged `stale`. |
| `jenreg.consistency.dead-after` | `900000` | Milliseconds of silence after which a node leaves the live comparison. |
| `jenreg.consistency.forget-after` | `86400000` | Milliseconds of silence after which a node's fingerprint is deleted; a publishing node reaps at most hourly. |
| `management.endpoints.web.exposure.include` | `health,info,metrics` | The Actuator endpoints served. |
| `management.endpoint.health.probes.enabled` | `true` | Serve the liveness and readiness probe groups. |
| `management.endpoint.health.show-details` | `when-authorized` | Show health detail only to an authorised caller. |

Every `jenreg.*` key is also an environment variable (`JENREG_CONSISTENCY_ENABLED=true`) or a `-D` system
property.
