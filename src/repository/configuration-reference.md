---
order: 13
title: Configuration reference
description: Every setting the repository reads, in one place - grouped by the chapter that explains it, with its default and what it changes. Server startup properties, per-repository dials, the management endpoints, and the one-off import fields.
---

Every earlier chapter introduces its own handful of settings in context. This chapter collects them
in one place so you can look one up without hunting: each is listed under the chapter that explains it,
with its default and a one-line reminder of what it does. Read the chapter for the *why*; read this page
for the *what* and the *default*.

## How a setting is set

There are only a few ways a value reaches the server, and the table columns below assume you know which
applies:

- **Server startup - an environment variable or a system property.** Cloud credentials and the store
  root are environment variables (`JENESIS_*`); everything wire-level is a `-Djenesis.repository.<key>=…`
  system property. The tables use the **short key** (`quota`, `auth`, `license-allowed`); the full system
  property prepends `jenesis.repository.` to it.
- **Per repository - the console settings screen or the settings API.** Most gate, provenance, search
  and maintenance dials are *repository* settings you edit live; the change takes effect on the next
  request, no restart.
- **Per run - a request body.** A migration is configured in the `POST` that launches it, not by a
  standing key.

Where a key is both a repository dial *and* pinnable from above, the two meet with a clear rule:

<div class="note">
  A value pinned at startup (env var or <code>-Djenesis.repository.&lt;key&gt;=…</code>) <strong>wins over
  any stored per-repository edit.</strong> Pin the policy you want a deployment to hold to; leave the rest
  for a repository - or a tenant, where the key is tenant-overridable - to set for itself.
</div>

A capability being *present* is not a setting - it is whether its module is on the server's path
(`+source+store+s3`, `+source+proxy`, `source/oidc`, …), noted in
[Architecture](/repository/architecture/) and each capability's chapter. But every *installed*
implementation also carries a uniform runtime toggle, and an exclusive seam a selection key - the
**Feature toggles & implementation selection** section just below - so one image carrying every
module is trimmed by configuration instead of rebuilt.

### Value formats

| Kind | How you write it |
|------|------------------|
| Boolean | `true` / `false`. |
| Duration | ISO-8601 - `PT10M` (ten minutes), `PT1H` (an hour), `P1D` (a day), `P7D` (a week); simple forms like `60s` / `5m` are also accepted. One key, `scan-interval-millis`, is a plain millisecond count instead. |
| Byte count | a plain number, or a `K` / `M` / `G` / `T` suffix (`10GB`). |
| Verdict | `ALLOW` / `QUARANTINE` / `REJECT`. |
| List | comma-separated, unless a key says otherwise. |

---

## Feature toggles & implementation selection

Startup keys, read at `ServiceLoader` discovery - the convention every discovered implementation
follows, so an image carrying every module (the all-in-one image) is shaped with `docker run -e`
rather than rebuilt. Spring's relaxed binding makes every key an environment variable:
`jenesis.repository.maven` is `JENESIS_REPOSITORY_MAVEN`, `jenesis.repository.store` is
`JENESIS_REPOSITORY_STORE`.

- **A parallel implementation** (a format, an import source, a feed - many active at once) toggles by
  its name: `jenesis.repository.<feature>=true|false`. **Unset means enabled**; only an explicit
  `false` disables, and a disabled implementation is simply not activated at discovery - it degrades
  exactly like a missing module (`jenesis.repository.maven=false` removes the Maven layout, and its
  importer with it). The advisory feeds are the deliberate exception: each stays **opt-in**
  (`osv=true`, …), so an unconfigured deployment consults no external API.
- **An exclusive seam** (one active implementation) selects by name with
  `jenesis.repository.<spi>=<feature>`; unset picks the noted default or the first enabled
  implementation in discovery order, and a selection naming an uninstalled implementation degrades to
  the documented `501` rather than failing the boot.
- **Required-config self-disable:** an implementation that cannot run without a key (a credential, a
  bucket) disables itself when that key is unset and logs one line naming the missing keys and the
  `jenesis.repository.<feature>=false` switch that silences it. The selected **store** is the one
  exception - it fails loudly, because silently falling back would persist against the wrong backend.

| Selection key | Default | Chooses among |
|---------------|---------|---------------|
| `jenesis.repository.store` | `filesystem` | The storage backend: `filesystem`, `s3`, `gcs`, `azure-blob`. See [Storage](/repository/storage/). |
| `jenesis.repository.fetcher` | *(first enabled - `http`)* | The upstream HTTP fetcher every proxy and import shares. See [Proxying & groups](/repository/proxying/). |
| `jenesis.repository.token-exchange` | *(first enabled - `oidc`)* | The OIDC token-exchange implementation behind `/api/token`. See [Authentication & access](/repository/authentication/). |
| `jenesis.repository.tenants` | *(first enabled)* | The tenant-directory implementation (`store-tenants` in the standard image). |
| `jenesis.repository.rate-limiter` | *(first enabled - `token-bucket`)* | The rate-limiter implementation. See [Rate limiting & usage tracking](/repository/rate-limiting-usage/). |
| `jenesis.repository.key-usage` | *(first enabled - `batching`)* | The credential usage-tracker implementation. |
| `jenesis.repository.retention` | *(first enabled - `cleaner`)* | The retention engine behind the cleanup and retention endpoints. See [Maintenance](/repository/maintenance/). |
| `jenesis.repository.walk` | *(first enabled - `store`)* | The artifact-walk implementation store-sweeping passes enumerate through. See [Maintenance](/repository/maintenance/). |
| `jenesis.repository.gc` | *(none installed - nothing reclaimed)* | The garbage collector (`mark-sweep` is the shipped implementation); with none installed or selected no content blob is ever reclaimed. See [Maintenance](/repository/maintenance/). |

An implementation's *own* settings keep their documented keys - the tables below and
`JENESIS_AWS_BUCKET`-style credentials - the toggle only decides whether it activates.

---

## Server & storage

Startup environment variables and system properties, read once when the server boots.
See [Getting started](/repository/getting-started/) and [Storage](/repository/storage/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `JENESIS_STORE_ROOT` | *(required for filesystem)* | Root directory of the filesystem store. |
| `jenesis.repository.store` | *(filesystem)* | Storage backend: unset = filesystem, `s3`, `gcs`, or `azure-blob`. |
| `jenesis.repository.quota` | *(unset - no cap)* | Storage cap; a new artifact is refused with `507` once stored blob bytes reach it. Byte count or `K`/`M`/`G`/`T`. |
| `SPRING_PROFILES_ACTIVE` | *(none)* | Set to `dev` for the built-in `admin`/`admin` form login on a local run - never in production. |

The tenant and repository of the fixed artifact space are `jenesis.repository.tenant` and
`jenesis.repository.repository`, both defaulting to `default` - see
[Authentication & access](/repository/authentication/) below.

### Cloud store credentials

Read only by the backend you select. See [Storage](/repository/storage/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `JENESIS_AWS_BUCKET` | *(required for `s3`)* | Bucket for the S3-compatible backend. |
| `JENESIS_AWS_ENDPOINT` | *(AWS)* | Custom endpoint for a non-AWS S3 store (GCS, MinIO, Ceph). |
| `JENESIS_AWS_ACCESS_KEY_ID` | *(AWS chain)* | Explicit S3 access key; set together with the secret key, else the standard AWS credential chain is used. |
| `JENESIS_AWS_SECRET_ACCESS_KEY` | *(AWS chain)* | Explicit S3 secret key; set together with the access key. |
| `JENESIS_GCS_BUCKET` | *(required for `gcs`)* | Bucket for the native Google Cloud Storage backend. |
| `JENESIS_GCS_ACCESS_KEY_ID` | *(required for `gcs`)* | GCS HMAC access key (Cloud Storage → Settings → Interoperability); set with the secret. |
| `JENESIS_GCS_SECRET_ACCESS_KEY` | *(required for `gcs`)* | GCS HMAC secret key; set with the access key. |
| `JENESIS_GCS_ENDPOINT` / `JENESIS_GCS_REGION` | *(GCS defaults)* | Custom endpoint / region for the GCS backend. |
| `JENESIS_AZURE_CONNECTION_STRING` | *(required for `azure-blob`)* | Azure account connection string. |
| `JENESIS_AZURE_CONTAINER` | *(default container)* | Azure Blob container to use. |

<div class="tip">
  Pointing a build at the server is not a repository setting - it is a client knob:
  <code>-Djenesis.maven.uri</code>, <code>-Djenesis.module.uri</code> and
  <code>-Djenesis.module.token</code> on the consuming Jenesis or Maven build, covered in
  <a href="/repository/getting-started/">Getting started</a>.
</div>

---

## Formats

System property, read at startup. See [Formats](/repository/formats/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.repository.<format>` | *(enabled)* | Toggle an installed format by its name (`maven`, `jenesis`, `oci`, `raw`, …); `false` degrades it exactly like a missing module - its paths unclaim, and its importer skips. |
| `jenesis.repository.maven-metadata-compute` | `false` | Compute `maven-metadata.xml` on read from stored version folders instead of serving the published bytes verbatim. |

---

## Proxying & groups

Per-format system properties, read at startup. See [Proxying & groups](/repository/proxying/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.repository.proxy-enabled` | `true` | The pull-through switch for the whole deployment; `false` serves every format hosted-only. |
| `jenesis.repository.proxy.<format>` | *(the format's canonical upstream)* | Overrides the upstream URL a proxy-capable format mirrors, keyed by its name (`proxy.maven` → Maven Central, `proxy.oci` → Docker Hub). A format that declares no canonical upstream stays hosted-only until named here. |
| `jenesis.repository.proxy-miss-ttl` | `60s` | How long a definite upstream `404` is remembered in the negative cache; `0` disables it. |

---

## Maintenance

Startup system properties, **spelled in full as written** (they are not `jenesis.repository.`-prefixed
repository dials). The implementation selections - `jenesis.repository.walk` and `jenesis.repository.gc` -
are in the selection-key table above. See [Maintenance](/repository/maintenance/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.walk.checkpoint` | `1000` | Keys visited between durable cursor commits of a walk segment. |
| `jenesis.walk.segments` | `32` | Target number of ranges a walk pass is split into across nodes. |
| `jenesis.walk.ttl` | `900` | Seconds before a dead node's segment claim expires and its segment resumes elsewhere (a plain second count). |
| `jenesis.gc.stride` | `20000` | Checkpoint stride of the garbage collector's own walk passes. |
| `jenesis.gc.grace` | *(none)* | Optional ISO-8601 wall-clock floor on the condemn-to-collect grace, on top of the one-pass generation gap - a blob is not reclaimed until its condemned marker is at least this old, so fast generation turnover across nodes cannot shorten the grace. |

---

## Authentication & access

Wire-gating system properties, read at startup before any tenant configuration.
See [Authentication & access](/repository/authentication/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `auth` | `false` | Enforce the credential model. `false` leaves the server **open** - every request allowed. |
| `read-only` | `false` | Deployment-wide read-only mode: every write - external or internal - is refused with `403`, all reads work normally. Advertised at `GET /api/capabilities`. |
| `tenant` | `default` | The tenant half of the one artifact space this deployment serves. |
| `repository` | `default` | The repository half of that space. |
| `jenesis.repository.anonymous-rights` | *(unset - no rights)* | Rights a keyless caller is granted under an enforcing deployment. Blank grants nothing, so anonymous access is strictly opt-in. |

Finer controls - credential lifetime **policy**, OIDC **trusts**, custom **roles**, the **quota** and the
**rate limit** - are data set through the management surface, not startup properties.

---

## Rate limiting & usage tracking

Startup properties, read once when the server boots.
See [Rate limiting & usage tracking](/repository/rate-limiting-usage/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.repository.rate-limit` | *(unset - no limit)* | Deployment-default request ceiling in permits per minute, metered per tenant; excess sheds with `429` and a `Retry-After`. Actuator probes are never throttled. |
| `jenesis.repository.track-key-usage` | `false` | Record each credential's last use, source address and use count on the batching worker. |

A tenant's own rate ceiling is per-tenant data set through the management surface
(`PUT /api/rate-limit`), not a startup property.

---

## Migration & import

A migration is not a standing setting - it is configured in the body of the `POST` that launches it.
See [Migration & import](/repository/migration-import/).

| Field | Required | What it sets |
|-------|----------|--------------|
| `source` | yes | Connector name: `nexus`, `artifactory`, or `jenesis` (whichever are on the path). |
| `url` | yes | The incumbent's base URL. |
| `repository` | yes | The source repository to walk. |
| `format` | for `artifactory` | The single package type of the source (`maven2`, `docker`, `raw`); Nexus and Jenesis report it per asset. |
| `username` / `password` | if the source needs auth | HTTP basic credentials (for a `jenesis` source, the API key is the password). |
| `resume` / `cursor` | to continue | A prior job's saved cursor, to pick up where an interrupted walk stopped. |

The Maven importer honours the same `maven-metadata-compute` opt-in as the Maven format: with it on, a
source `maven-metadata.xml` is dropped and regenerated from the imported version folders.

An installed connector is also switchable off by name - `jenesis.repository.nexus=false` removes
`nexus` from the accepted `source` values, per the **Feature toggles & implementation selection**
section above.

One startup property guards the edge itself, since a migration is walked with the upstream credentials
attached:

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.repository.block-private-import-hosts` | `true` | Refuse a migration URL that is plaintext `http`, or whose host resolves to a private or loopback address. |
| `jenesis.repository.batch-upload` | `false` | Accept a zip carrying `X-Jenesis-Explode: zip` and explode it into one publish per entry. |
| `jenesis.repository.demo` | `false` | Seed a completely empty repository with real artifacts on first boot; refuses a non-empty one. |

---

## Multi-node consistency

Read at startup, except the dials, which are runtime-tunable. Off by default: a single node writes nothing.
See [Observability](/repository/observability/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `jenesis.consistency.enabled` | `false` | Publish this node's fingerprint and compare it against the others. Per node, not a shared setting. |
| `jenesis.consistency.node-id` | *(generated)* | This node's identity in the comparison. Per node. |
| `jenesis.consistency.heartbeat` | *(sweep interval)* | Milliseconds between fingerprint publishes. |
| `jenesis.consistency.sweep-interval` | | Milliseconds between consistency sweeps. |
| `jenesis.consistency.sweep-intervals` | | How many frozen sweeps before a live-but-frozen node is reported stuck. |
| `jenesis.consistency.staleness-window` | | Milliseconds a node may lag and still count as benign lag. |
| `jenesis.consistency.dead-after` | | Milliseconds after a node's last heartbeat before it is treated as dead and no longer compared. |

---

## Observability

Standard Spring Boot management properties, set as system properties (`-Dmanagement.…`), environment
variables, or in the deployment's configuration. See [Observability](/repository/observability/).

| Key | Default | What it sets |
|-----|---------|--------------|
| `management.endpoints.web.exposure.include` | `health,info,metrics` | Which Actuator endpoints are served; add `prometheus` to expose `/actuator/prometheus`. |
| `management.endpoint.health.probes.enabled` | `true` | Serve separate Kubernetes-style liveness and readiness probes. |
| `management.endpoint.health.show-details` | `when-authorized` | Show full health detail only to an authorised caller. |
| `logging.level.build.jenesis.observation` | `INFO` | Verbosity of the one-line-per-operation observation log; raise to `WARN` for failures only. |
| `management.tracing.sampling.probability` | `0.0` | Fraction of operations traced (`1.0` = all); needs a tracing bridge on the module path. |
| `management.otlp.tracing.endpoint` | *(unset)* | Where to export spans over OTLP; unset exports nothing even when sampling is above zero. |
| `jenesis.repository.logs.buffer` | `1000` | How many recent log entries the in-memory ring behind `GET /api/logs` and the console's **Logs** panel keeps. |

---

## The console

The console reads no settings of its own beyond the server ones already listed - `SPRING_PROFILES_ACTIVE=dev`
for the local `admin`/`admin` login, and the `jenesis.ui.*` reclaim target under
[Maintenance](/repository/maintenance/). See [The console](/repository/console/).

<div class="note">
  The theme switch (Auto / Light / Dark) is a per-browser preference, not a server setting - it changes
  nothing another user sees.
</div>
