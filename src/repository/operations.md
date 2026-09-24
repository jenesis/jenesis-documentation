---
order: 11
title: Operations
description: Watching and running a deployment - the Metrics and Security posture pages, scheduled walks of the store, manual uploads through Deploy, webhooks, rate limits, and the health, metrics and log endpoints.
---

The **Operations** section is where a deployment's administrators see what the server is doing and change how
it runs in the background. Its pages - **Metrics**, **Security posture** and **Walks** - are for the deployment's
administrators, and **Deploy**, once switched on, for anyone with the admin role. Beside them this chapter covers
what a monitoring system reads over HTTP, webhooks, and the rate limit.

## Metrics

**Metrics** lists what every installed module reports about itself: counters, gauges, health checks and the state
of each background task, each with its current value and a line saying what it measures. A module that is not
installed, or is switched off, reports nothing, so the page shows what this deployment is actually doing - how
full the storage quota is, how often the proxy cache answered locally, when the collector last ran.

## Security posture

**Security posture** lists every configuration choice that makes the deployment less safe than it could be, most
severe first - running without keys, a plaintext upstream, a feed that fails open. Each entry says why it matters
and which setting changes it. A clean deployment lists nothing, which is the healthy state, and the count shown in
the header is the length of this list.

Observing the posture never changes it: the page is read-only, and it names the setting at fault, never its value.
Each entry links here, to its own line of this table:

| Advisory | Severity | Raised when |
| --- | --- | --- |
| <span id="jenreg.auth.open">`jenreg.auth.open`</span> | critical | `JENREG_AUTH=false` - every request is served without a key, writes included. |
| <span id="jenreg.profile.dev">`jenreg.profile.dev`</span> | critical | The `dev` profile is active, so the console runs its local-only sign-in. |
| <span id="jenreg.anonymous.write">`jenreg.anonymous.write`</span> | critical | `anonymous-rights` lets a caller without a key write or administer. |
| <span id="jenreg.gate.malware">`jenreg.gate.malware`</span> | critical | `malware-action` is `ALLOW` for a tenant, so a package known to be malicious is admitted. |
| <span id="jenreg.consistency.config">`jenreg.consistency.config`</span> | critical | One server of several runs with different settings or tenants from the others. |
| <span id="jenreg.consistency.pointer">`jenreg.consistency.pointer`</span> | critical | Two servers answer the same path with different content. |
| <span id="jenreg.anonymous.enabled">`jenreg.anonymous.enabled`</span> | warning | `anonymous-rights` lets a caller without a key read - right for a public mirror, and worth knowing otherwise. |
| <span id="jenreg.gate.vulnerability.action">`jenreg.gate.vulnerability.action`</span> | warning | `vulnerability-action` is `ALLOW` for a tenant, so an artifact over the threshold is served. |
| <span id="jenreg.gate.vulnerability">`jenreg.gate.vulnerability`</span> | warning | `vulnerability-threshold` is `NONE` for a tenant, which switches the vulnerability check off. |
| <span id="jenreg.gate.denylist.action">`jenreg.gate.denylist.action`</span> | warning | `deny-list-action` is `ALLOW` for a tenant, so the deny list is ignored. |
| <span id="jenreg.importer.ssrf">`jenreg.importer.ssrf`</span> | warning | `block-private-import-hosts=false` - an import may reach internal addresses, or travel unencrypted. |
| <span id="jenreg.ratelimit.unset">`jenreg.ratelimit.unset`</span> | warning | `rate-limit` is `0`, so nothing throttles a client. |
| <span id="jenreg.demo.writable">`jenreg.demo.writable`</span> | warning | A demo deployment that is not read-only, so anyone can write to it. |
| <span id="jenreg.consistency.stuck">`jenreg.consistency.stuck`</span> | warning | One server of several has stopped catching up with what the others have seen. |
| <span id="jenreg.posture.collision">`jenreg.posture.collision`</span> | warning | Two installed modules report under the same advisory name - a packaging fault, shown rather than hidden. |

## Walks

Some work needs to look at everything the store holds - applying retention, reclaiming space, rebuilding the
indexes clients read. The server does it in **walks**: one pass over the store that every such job rides along
on, so the store is read once rather than once per job.

**Walks** shows the scheduled walks, with when each last ran and what it did. Two are scheduled by default:

| Walk | When | What rides along |
| --- | --- | --- |
| `retention` | Daily at 03:00 UTC | Applying each repository's retention policy |
| `rebuild` | Sundays at 03:00 UTC | Everything else: reclaiming space, repairing indexes, back-filling what a newly installed module needs |

Each walk can be edited in place - its schedule as a cron expression with seconds first, in UTC
(`0 0 3 * * *`), whether it is switched on, and which jobs ride along - or removed, and **Add a walk** schedules
another. **Walk the store now** starts a walk at once.

<div class="note">
  A walk reads every object in the store, so on object storage every scheduled walk is a recurring cost. The
  default schedule keeps the whole-store work weekly; <a href="/repository/cost/">What it costs to run</a> puts
  numbers on it.
</div>

## Deploy

**Deploy** publishes a single file from the browser - a one-off artifact that has no build to publish it. Choose
the repository, enter the path the artifact is published under, such as
`maven/com/example/tool/1.0/tool-1.0.jar`, pick the file, and press **Publish**. It passes the same gate a client's
upload does.

The page is switched off by default; switch it on with `JENREG_DEPLOY=true` or under **Settings → Modules**.

## Webhooks

The server can call you back when something happens - a publish, a removal, a hold, a release, a new finding.
Webhooks are configured under **Settings → Settings**, in the **Webhooks** group:

| Setting | Meaning |
| --- | --- |
| `webhook` | Switches delivery on. |
| `webhook-endpoints` | One endpoint per line, `https://hooks.example.com/repo publish,quarantine` - the events after the URL, or none for all. |
| `webhook-secrets` | Per endpoint, a secret the server signs each delivery with (HMAC-SHA256), as `https://hooks.example.com/repo=<secret>`. |
| `webhook-attempts` | How many times a failing delivery is retried, with a growing pause, before it is set aside. Five by default. |

Deliveries go out from a background queue, so a slow receiver never slows a publish. An endpoint must be
`https` and on a public address unless `webhook-allow-internal` permits otherwise.

## Rate limits

Every request is metered against a per-tenant ceiling - **6 000 requests a minute** by default, a hundred a
second - and a request over it is answered `429` with `Retry-After: 60`. The ceiling is set on the
**Repositories** page, or deployment-wide with `JENREG_RATE_LIMIT`; `0` removes it.

A request is charged to its key's tenant, and every request without a key shares one bucket of its own. A
bucket holds a minute's worth of burst, so a build resolving a large dependency graph in a quick burst gets
through while a sustained flood is shed. Health probes and metric scrapes are never limited. Each server of a
multi-node deployment keeps its own buckets, so behind a load balancer the effective ceiling is the setting
times the number of servers.

## Endpoints for monitoring

| Endpoint | Answers | Who may read it |
| --- | --- | --- |
| `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` | Up or down, for probes | Anyone; the detail only to an administrator |
| `/actuator/metrics` | The server's meters, for a monitoring system | A key with a deployment-wide `*` grant |
| `/api/logs` | The most recent log entries, filterable by level and text | A key with a deployment-wide `*` grant |
| `/api/posture` | The security posture, as JSON | A key with a deployment-wide `*` grant |

`/api/logs` keeps the last thousand entries in memory, with a sequence number on each, so a script can tail it:

```bash
curl -H "Jenesis-Repository-Key: $ADMIN_KEY" \
  'https://repo.example.com/api/logs?level=WARN&limit=50'
```
