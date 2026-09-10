---
order: 13
title: Configuration reference
description: Every setting Jenesis Repository and its console read, grouped by the chapter that explains it - the key, its environment-variable spelling, its default, and what it changes.
---

The earlier chapters explain each setting where it matters. This page lists all of them in one place: the key,
how it is spelled as an environment variable where that differs from the obvious form, its default, and a
one-line reminder of what it does.

## How a setting is set

Jenesis Repository is a Spring Boot application, so a setting reaches it the way any Spring Boot setting
does, and the same value can be given in any of these forms:

| Form | Example |
|---|---|
| An environment variable | `JENREG_PROXY_MAVEN=https://repo1.maven.org/maven2/` |
| A system property | `-Djenreg.proxy.maven=https://repo1.maven.org/maven2/` |
| An `bundle.properties` file next to the launch | `jenreg.proxy.maven=https://repo1.maven.org/maven2/` |
| A Spring profile | `SPRING_PROFILES_ACTIVE=dev` selects the `dev` profile's properties file |

The environment spelling follows Spring's relaxed binding: upper case, dots and hyphens become underscores, so
`jenreg.block-private-import-hosts` is `JENREG_BLOCK_PRIVATE_IMPORT_HOSTS`. The tables below spell a variable
out only where a key does not follow that rule.

Two conventions cover most keys:

- **A toggle switches a discovered module off.** Every format, importer and fetcher is enabled when it is on
  the module path; `jenreg.<name>=false` disables it exactly as if its module were absent. Nothing else needs
  setting to enable one.
- **A selection picks one implementation.** Where exactly one implementation may be active - the store
  backend, the upstream fetcher - `jenreg.<kind>=<name>` names it. A selection that names an implementation
  nobody provides fails the boot rather than falling back. Where the capability may also be absent - the
  fetcher, the rate limiter - two enabled implementations are ambiguous and fail the boot as well. The
  store is the one selection with a default, `filesystem`, which wins when you select nothing.

<div class="note">
  Durations are ISO-8601 (<code>PT90S</code>) unless a row says otherwise; <code>jenreg.proxy-miss-ttl</code>
  also takes the short form Spring binds (<code>90s</code>, <code>5m</code>). Sizes for the quota take a
  <code>K</code>, <code>M</code>, <code>G</code> or <code>T</code> suffix. A boolean is <code>true</code> or
  <code>false</code>.
</div>

## Server & storage

See [Getting started](/repository/getting-started/) and [Storage](/repository/storage/).

| Key | Default | Effect |
|---|---|---|
| `PORT` (env) | `8080` | The port the server listens on. |
| `jenreg.store` | `filesystem` | The store backend: `filesystem`, `s3`, `gcs` or `azure-blob`. |
| `jenreg.tenant` | `default` | The tenant half of the artifact space this deployment serves. |
| `jenreg.repository` | `default` | The repository half of the artifact space. |
| `jenreg.quota` | *(unset - no cap)* | The storage ceiling, as a byte count or a number with a `K`/`M`/`G`/`T` suffix; a write past it answers `507`. |
| `jenreg.read-only` | `false` | Refuse every write - publishes, imports, deletes and internal cache fills - with `403`, while reads work normally. |
| `jenreg.rebuild.interval` | `P7D` | How often the server regenerates every stored listing (`tags/list`, `_catalog`, a computed `maven-metadata.xml`), so a write that could not land is repaired without a read ever paying for it. An ISO-8601 duration (`PT6H`) or a short one (`6h`, `30m`); `off` disables the pass. The first pass runs a minute after start. |
| `jenreg.gc` | `mark-sweep` | The collector that reclaims the blobs no live pointer references, by name; a name nothing answers to fails the boot. See [Reclaiming space](/repository/storage/). |
| `jenreg.collect` | `true` | Switch off the walk pass that runs the collector. |
| `jenreg.gc.stride` | `20000` | Items the collector handles between checkpoints. |
| `jenreg.gc.grace` | `PT0S` | A wall-clock floor on the gap between condemning a blob and deleting it, on top of the two-pass rule. |
| `jenreg.walk` | *(the one installed)* | Select the artifact walk the rebuild pass enumerates through, by name; a name nothing answers to fails the boot. |
| `jenreg.walk.checkpoint` | `1000` | Items a walk enumerates before it commits its cursor, so an interrupted pass resumes near where it stopped rather than starting over. |
| `jenreg.walk.segments` | `32` | Key ranges one pass is split into. Several nodes claim disjoint segments, so they share one pass instead of repeating it. |
| `jenreg.walk.ttl` | `PT15M` | How long a node's claim on a segment stands before another node may take it, which is what lets a pass survive a node that stops mid-segment. |
| `jenreg.demo` | `false` | Seed a completely empty repository with real artifacts, pulled through each format's own default upstream, so it needs no proxy configured. A no-op on a repository that holds anything, and skipped entirely under `jenreg.read-only=true`. |
| `jenreg.filesystem.root` | *(required for `filesystem`)* | The directory the filesystem backend stores under; the server refuses to start without one. |
| `jenreg.cache.ttl` | `PT5M` | How long a node serves a credential or a setting it has already read before asking the store again; another node's change shows within this. `0` switches the cache off. |
| `jenreg.s3.bucket` | *(required for `s3`)* | The bucket. |
| `jenreg.s3.region` | `us-east-1` | The signing region. |
| `jenreg.s3.endpoint` | *(AWS)* | An S3-compatible endpoint (MinIO, Ceph, LocalStack); enables path-style access. Must be `https`. |
| `jenreg.s3.allow-insecure-endpoint` | `false` | Permit a plain-`http` endpoint. |
| `jenreg.s3.access-key-id`, `jenreg.s3.secret-access-key` | *(AWS credential chain)* | Static credentials; when both are set they replace the ambient chain. |
| `jenreg.s3.sse-kms-key-id` | *(SSE-S3)* | Encrypt objects with this KMS key instead of SSE-S3. Encryption is always on. |
| `jenreg.gcs.bucket` | *(required for `gcs`)* | The Google Cloud Storage bucket, reached through its JSON API. |
| `jenreg.gcs.credentials` | *(Application Default Credentials)* | A service-account key file, or `none` for an emulator. |
| `jenreg.gcs.project` | *(unset - the bucket must exist)* | The project the bucket is created in on first use. |
| `jenreg.gcs.endpoint` | *(Google)* | An emulator endpoint; must be `https`. |
| `jenreg.gcs.allow-insecure-endpoint` | `false` | Permit a plain-`http` endpoint, for an emulator. |
| `jenreg.azure-blob.connection-string` | *(required for `azure-blob`)* | The storage-account connection string (or the Azurite development string). |
| `jenreg.azure-blob.container` | `jenesis-repository` | The container. |
| `jenreg.azure-blob.allow-insecure-endpoint` | `false` | Permit a plain-`http` blob endpoint. |
| `jenreg.s3.conditional-write-probe`, `jenreg.gcs.conditional-write-probe`, `jenreg.azure-blob.conditional-write-probe` | `true` | Probe at boot that the endpoint honours write preconditions and refuse to start when it does not; `false` skips the probe and warns at every start. |
| `jenreg.s3.streaming-writes`, `jenreg.gcs.streaming-writes`, `jenreg.azure-blob.streaming-writes` | `true` | Stream a compare-and-set body to the store; `false` buffers it in heap first, for an endpoint that cannot take a streamed one. |
| `jenreg.archive.largest-entry` | `1048576` (1 MiB) | The most one archive member may decompress to when a format reads a declaration out of it. |
| `jenreg.archive.largest-walk` | `67108864` (64 MiB) | The most bytes one walk may draw from a single archive. |

## Formats

See [Formats](/repository/formats/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.maven` | `true` | Serve the Maven layout at `/repository/maven/`. |
| `jenreg.jenesis` | `true` | Serve the module layout at `/repository/module/` and `/repository/artifact/`. |
| `jenreg.oci` | `true` | Serve the OCI registry at `/v2/`. |
| `jenreg.raw` | `true` | Serve the raw layout at `/repository/raw/`. |
| `jenreg.maven-metadata-compute` | `false` | Derive `maven-metadata.xml` from the stored version folders instead of serving only what was published. |
| `jenreg.batch-upload` | `false` | Honour the `X-Jenesis-Explode: zip` header and publish an uploaded archive entry by entry. |
| `jenreg.batch-upload-max-entries` | `10000` | The most entries one exploded archive may publish. |

## Proxying

See [Proxying](/repository/proxying/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.proxy.<format>` | *(unset - no proxying)* | The upstream a format pulls through on a local miss, for example `jenreg.proxy.maven=https://repo1.maven.org/maven2/` or `jenreg.proxy.oci=https://registry-1.docker.io`. |
| `jenreg.proxy-miss-ttl` | `60s` | How long an upstream `404` is remembered; `0` disables the negative cache. |
| `jenreg.proxy.request-timeout` | `PT1M` | The per-request upstream timeout (ISO-8601 or plain seconds). System property only. |
| `jenreg.http` | `true` | The HTTP upstream fetcher; `false` disables proxying and imports. |
| `jenreg.fetcher` | *(the one installed)* | Select the upstream fetcher by name (`http`); naming one that is not installed fails the boot. |

## Authentication & access

See [Authentication & access](/repository/authentication/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.auth` | `true` | Authorise every request against the `Jenesis-Repository-Key` header. `false` serves every request anonymously and raises the `jenreg.auth.open` advisory. |
| `jenreg.bootstrap-key` | *(empty)* | A well-formed `jenk_<tenant>.<secret><checksum>` key provisioned at boot with `*` on every repository of its tenant, so a fresh enforcing deployment can issue its first real keys through `/api/credentials`. Malformed values refuse to boot; a `SECURITY` line is logged while it is set. |
| `jenreg.credential-default-lifetime` | *(empty)* | The lifetime of a key minted without an explicit expiry, as an ISO-8601 duration (`P30D`, `PT12H`). Empty keeps the 90-day default. |
| `jenreg.credential-max-lifetime` | *(empty)* | The ceiling on any key's lifetime, as an ISO-8601 duration; a mint or an expiry change asking for more is pulled back to it. Empty leaves lifetimes uncapped. |
| `jenreg.anonymous-rights` | *(empty)* | The rights a keyless caller holds under `jenreg.auth=true`: a comma list of `<surface>:<verb>` tokens (`repository:read`, `repository:write`, `manage:read`, `manage:write`, `<surface>:*`, `*`), each optionally scoped as `<repository>=<token>`. |
| `jenreg.read-only` | `false` | See *Server & storage*; paired with `anonymous-rights=repository:read` this is the public-mirror pattern. |

## Rate limiting

See [Rate limiting](/repository/rate-limiting-usage/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.rate-limit` | `0` *(no limit)* | Permits per minute per tenant (and for the shared anonymous bucket); excess answers `429` with `Retry-After`. Unset raises the `jenreg.ratelimit.unset` advisory. |
| `jenreg.track-key-usage` | `true` | Record each credential's last use and running count. The accounting is batched into at most one write per credential per day; `false` switches it off, and the `jenreg.usage.*` signals then report nothing. |
| `jenreg.token-bucket` | `true` | Switch the in-memory token-bucket limiter off with `false`; every request is then unmetered. |
| `jenreg.rate-limiter` | *(the one installed)* | Select the rate limiter by name (`token-bucket`); naming one that is not installed fails the boot. |
| `jenreg.key-usage` | *(the one installed)* | Select the credential-usage tracker by name (`batching`). |

## Migration & import

See [Migration & import](/repository/migration-import/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.block-private-import-hosts` | `true` | Refuse an import URL that is not `https` or that resolves to a private, loopback or link-local address. `false` raises the `jenreg.importer.ssrf` advisory. |

## Observability

See [Observability](/repository/observability/).

| Key | Default | Effect |
|---|---|---|
| `jenreg.logs-buffer` | `1000` | Entries the in-memory log ring keeps for `GET /api/logs`. |
| `jenreg.consistency.enabled` | `false` | Publish this node's fingerprint and take part in the multi-node consistency check. |
| `jenreg.consistency.node-id` | the hostname | The node's stable name in the consistency report. |
| `jenreg.consistency.heartbeat` | the sweep interval | Milliseconds between fingerprint publications (at least 1 000). |
| `jenreg.consistency.sweep-interval` | `60000` | Milliseconds per sweep. |
| `jenreg.consistency.sweep-intervals` | `3` | Sweeps a lagging node may take to catch up before it is reported stuck. |
| `jenreg.consistency.staleness-window` | `300000` | Milliseconds since a node's last heartbeat after which it is flagged `stale`. |
| `jenreg.consistency.dead-after` | `900000` | Milliseconds of silence after which a node leaves the live comparison. |
| `jenreg.consistency.forget-after` | `86400000` | Milliseconds of silence after which a node's fingerprint is deleted by the next node that publishes. |
| `management.endpoints.web.exposure.include` | `health,info,metrics` | The Actuator endpoints served. |
| `management.endpoint.health.probes.enabled` | `true` | Serve the liveness and readiness probe groups. |
| `management.endpoint.health.show-details` | `when-authorized` | Show health detail only to an authorised caller. |

## The console

See [The console](/repository/console/). The console runs in the server's process, on the server's port,
and reads these beside the settings above.

| Key | Default | Effect |
|---|---|---|
| `jenreg.console` | `true` | Serve the console in this process; `false` leaves only the repository's own endpoints. |
| `jenreg.ui.admins` | *(empty - nobody)* | Comma-separated provider-qualified ids (`github/<id>`, `oidc/<subject>`) **seeded** as deployment administrators on every boot. A seed rather than a mirror: removing an id does not revoke it, and an administrator granted through the API is equally real. A `*` entry is refused at startup. |
| `jenreg.ui.github.client-id`, `jenreg.ui.github.client-secret` | *(empty - GitHub login off)* | A GitHub OAuth app. |
| `jenreg.ui.oidc.issuer-uri`, `jenreg.ui.oidc.client-id`, `jenreg.ui.oidc.client-secret` | *(empty - OIDC login off)* | An OpenID Connect provider; endpoints are discovered from the issuer at startup. |
| `jenreg.ui.oidc.name` | `Single sign-on` | The label on the OIDC sign-in button. |
| `SPRING_PROFILES_ACTIVE=dev` (env) | *(unset)* | Replace OAuth2 with a form login and the built-in `admin`/`admin` and `viewer`/`viewer` accounts; raises the `jenreg.profile.dev` advisory. |
