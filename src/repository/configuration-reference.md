---
order: 17
title: Configuration reference
description: Every setting Jenesis Repository reads - the startup settings given in its environment, and the runtime settings changed in the console - with its environment variable, its default and what it does.
---

A deployment is configured in two ways, and this page lists both. **Startup settings** are given in the
environment the server starts in and change with a restart. **Runtime settings** are changed in the console under
**Settings → Settings**, where each shows whether it applies at once or on the next restart; they can be given in
the environment too, which then pins them.

Every setting is a key under `jenreg.`, and its environment variable is the key upper-cased with dots and dashes
as underscores: `filesystem.root` is `JENREG_FILESYSTEM_ROOT`. A format, feed or other module is switched off with
`JENREG_<MODULE>=false`, as described in [Settings](/repository/settings/#modules).

## Startup settings

### Store

See [Running in production](/repository/deploying/).

| Key | Default | Effect |
| --- | --- | --- |
| `store` | `filesystem` | The store backend: `filesystem`, `s3`, `gcs` or `azure-blob`. |
| `filesystem.root` | *(required)* | The directory the filesystem store keeps everything in; the server refuses to start without it. |
| `s3.bucket` | *(required for s3)* | The bucket. |
| `s3.region` | `us-east-1` | The signing region. |
| `s3.endpoint` | *(AWS)* | An S3-compatible endpoint, such as MinIO; must be `https`. |
| `s3.access-key-id / s3.secret-access-key` | *(the AWS credential chain)* | Static keys; set both or neither. |
| `s3.sse-kms-key-id` | *(SSE-S3)* | A KMS key for server-side encryption. |
| `gcs.bucket` | *(required for gcs)* | The bucket. |
| `gcs.credentials` | *(Application Default Credentials)* | A service-account key file. |
| `gcs.project` | *(empty)* | The project to create the bucket in on first use; empty means the bucket must exist. |
| `gcs.endpoint` | *(Google)* | Another endpoint, such as an emulator; must be `https`. |
| `azure-blob.connection-string` | *(required for azure-blob)* | The storage account connection string. |
| `azure-blob.container` | `jenesis-repository` | The blob container. |
| `s3.allow-insecure-endpoint / gcs.… / azure-blob.…` | `false` | Permit a plain-HTTP endpoint - for an emulator, never a deployment. |
| `s3.conditional-write-probe / gcs.… / azure-blob.…` | `true` | Check at startup that the store honours conditional writes, and refuse to start if it does not. |
| `quota` | *(empty - no cap)* | The most the deployment may store, such as `10G`; a publish over it is refused. |

### Access

See [Access](/repository/access/).

| Key | Default | Effect |
| --- | --- | --- |
| `auth` | `true` | Require a key on every request. `false` serves everyone, and is reported as a security advisory. |
| `anonymous-rights` | *(empty)* | Rights granted to a request without a key, such as `repository:read`. |
| `read-only` | `false` | Refuse every write at the store. |
| `bootstrap-key` | *(empty)* | A key provisioned at startup with every right on its tenant, for automation that needs one before anyone signs in. |
| `credential-default-lifetime` | *(90 days)* | How long a key issued without an expiry lives, as an ISO-8601 duration. |
| `credential-max-lifetime` | *(no cap)* | The longest any key may live. |
| `ui.admin-key` | *(empty)* | The administrator key that key sign-in accepts. |
| `ui.admins` | *(empty)* | Provider-qualified identifiers seeded as the deployment's administrators on every start. |
| `ui.oidc.issuer-uri / .client-id / .client-secret` | *(empty - off)* | The OpenID Connect issuer and client. |
| `ui.oidc.name` | `Single sign-on` | The label on the OpenID Connect sign-in button. |
| `ui.github.client-id / .client-secret` | *(empty - off)* | A GitHub OAuth app. |
| `ui.ldap.url` | *(empty - off)* | The directory to sign people in against. |
| `ui.ldap.user-dn-pattern` | *(empty)* | The distinguished name to bind as, with `{0}` for the name typed. |
| `ui.ldap.user-search-base / .user-search-filter` | *(empty)* / `(uid={0})` | Where and how to search for a person instead. |
| `ui.ldap.bind-dn / .bind-password` | *(empty)* | The account to search with. |
| `ui.ldap.group-search-base / .group-search-filter` | *(empty)* / `(member={0})` | Where and how to find a person's groups. |
| `ui.ldap.admin-group` | *(empty)* | The group whose members administer the deployment. |
| `ui.ldap.start-tls / .allow-plaintext` | `false` | Upgrade a plain `ldap://` connection with StartTLS, or accept it as private. |

### Serving

See [Repositories](/repository/repositories/).

| Key | Default | Effect |
| --- | --- | --- |
| `tenancy` | `fixed` | How a request's tenant is decided, read once at startup. `fixed` serves the one tenant `default-tenant` names and answers `404` for a URL naming any other; a name no installed routing answers to refuses to start. |
| `repositories.<name>` | *(empty)* | A repository definition, as on **Settings → Repository definitions**. It routes a repository that exists; it does not create one. |
| `proxy.<format>` | *(empty)* | The upstream a format fetches a miss from, as on **Settings → Format upstreams**. |
| `proxy-miss-ttl` | `60s` | How long an upstream miss is remembered. |

### Several servers

See [Running in production](/repository/deploying/#several-servers).

| Key | Default | Effect |
| --- | --- | --- |
| `consistency.enabled` | `false` | Have every server record a fingerprint of what it has seen, so a server that falls behind or disagrees is reported. |
| `consistency.node-id` | *(the host name)* | This server's stable name among its peers. |

## Runtime settings

The settings catalogue, as **Settings → Settings** shows it, grouped the same way. *Applies* says whether a change takes effect at once or on the next restart.

### Compliance

Explained in [Screening what comes in](/repository/screening/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `allow-redeploy` | `false` | at once | Off by default: release-version immutability refuses re-pointing an already-published immutable release coordinate at different bytes (a 409), a supply-chain / dependency-confusion guard. |
| `deny-list` | *(empty)* | at once | Comma-separated coordinates an operator forbids; |
| `deny-list-action` | `REJECT` | at once | Verdict for a coordinate the deny list names. |
| `github` | `false` | on restart | Consult the GitHub Advisory Database. |
| `github-endpoint` | `https://api.github.com` | on restart | The GitHub REST API base URL, for a self-hosted GitHub or a proxy. |
| `inspection.oversized` | `STREAM` | at once | What to do with an artifact larger than the inspection prefix - jenreg.inspection.prefix-bytes, 32 MiB by default - which is the most of one artifact an inspector is ever handed in memory. |
| `malware-action` | `REJECT` | at once | Verdict for a package the feed marks malicious. |
| `openssf` | `false` | on restart | Consult the curated OpenSSF malicious-packages feed (MAL- records, served by OSV.dev). |
| `openssf-endpoint` | `https://api.osv.dev` | on restart | The OSV API base URL serving the dataset, for a mirror or a proxy. |
| `osv` | `false` | on restart | Consult the OSV (osv.dev) vulnerability feed. |
| `osv-endpoint` | `https://api.osv.dev` | on restart | The OSV API base URL, for a mirror or a proxy. |
| `policy-rules` | *(empty)* | at once | Expression-based gate rules, one per line (or separated by ';'), each '<verdict> <expression>' where verdict is allow, quarantine or reject - e.g. |
| `provenance-admission-action` | `QUARANTINE` | at once | Verdict for an artifact whose inbound attestation fails verification - unsigned by a trusted key, signed for a different artifact, or an unexpected builder or source. |
| `provenance-admission-builder` | *(empty)* | at once | Comma-separated builder identities an inbound attestation must name, e.g. |
| `provenance-admission-key` | *(empty)* | at once | PEM public key(s) an inbound attestation's DSSE signature must verify against - the builder keys the tenant trusts. |
| `provenance-admission-source` | *(empty)* | at once | Comma-separated source repository URIs an inbound attestation's provenance must have built from, e.g. |
| `provenance-attestation-sweep` | `false` | at once | Reclaim provenance attestations whose artifact is gone. |
| `provenance-attestation-sweep-interval` | `P1D` | at once | How often the attestation sweep runs. |
| `scan-full-every` | `24` | at once | Every Nth scheduled pass of the advisory scan re-reads every published version; the passes between read only what was published since. |
| `scan-interval-millis` | `3600000` | at once | Milliseconds between scheduled scans; each pass hits the upstream feeds. |
| `scan-lookback` | `PT1M` | at once | How far before the last full pass's stamp an incremental pass still looks. |
| `scheduled-scan` | `true` | at once | Re-scan every repository's inventory against the advisory feeds on a schedule. |
| `signature-attestation-lookup` | *(empty)* | at once | The attestation stores asked, by the artifact's digest, for the bundles they hold for an artifact just published, one <ecosystem> = <url> per line; |
| `signature-invalid` | `REJECT` | at once | Verdict for an artifact whose signature does not match its bytes - the artifact was altered after signing, or the signature was made for different content. |
| `signature-key-discovery` | *(empty)* | at once | Sources to fetch the signing keys this deployment does not hold from, comma-separated, asked in the order named; |
| `signature-key-discovery-accept` | `false` | at once | Trust the keys the discovery sources served: |
| `signature-key-discovery-interval` | `PT1H` | at once | How often the key-discovery pass asks the named sources for the keys still wanted, as a duration; |
| `signature-key-discovery-ubuntu-url` | `https://keyserver.ubuntu.com` | at once | Where keyserver.ubuntu.com is reached - the public instance by default, or any host speaking the HKP lookup (op=get&options=mr&search=0x<key id>), which every SKS-descended keyserver and most internal mirrors do. |
| `signature-key-discovery-url` | `https://keys.openpgp.org` | at once | Where keys.openpgp.org is reached - the public instance by default, or an internal mirror of it that speaks the same lookup by key id. |
| `signature-missing` | `ALLOW` | at once | Verdict for an artifact carrying no signature where its format expects one. |
| `signature-missing-proxy` | `ALLOW` | at once | Verdict for a proxied artifact carrying no signature where its format expects one. |
| `signature-provenance-accept` | *(empty)* | at once | The OIDC issuers whose keyless identities are trusted by provenance, comma- or newline-separated - GitHub Actions' https://token.actions.githubusercontent.com being the one to name first. |
| `signature-quality-action` | `ALLOW` | at once | What a signature below the quality floor does. |
| `signature-quality-floor` | `none` | at once | The grade below which a signature raises a finding - none (the default, quality is reported and never gated), unusable, weak, acceptable or strong. |
| `signature-signer-changed` | `QUARANTINE` | at once | Verdict for a coordinate signed by a different signer than its earlier versions carried. |
| `signature-sigstore-trusted-root` | *(empty)* | at once | The Sigstore trusted root this deployment verifies bundles against - the JSON a `cosign trusted-root` or the public-good TUF repository serves, naming the Fulcio certificate authorities and the Rekor transparency logs to believe. |
| `signature-sigstore-trusted-root-interval` | `P1D` | at once | How often the trusted root is fetched again, as a duration. |
| `signature-sigstore-trusted-root-url` | *(empty)* | at once | Where the Sigstore trusted root is fetched from when none is pasted above. |
| `signature-sweep` | `false` | at once | Apply the signature dials below to what is already published: |
| `signature-sweep-interval` | `P1D` | at once | How often the signature sweep runs while switched on, as a duration; |
| `signature-trusted-certificates` | *(empty)* | at once | The PEM certificates a PKCS#7 (CMS) publisher signature must chain to - one or more concatenated -----BEGIN CERTIFICATE----- blocks: |
| `signature-trusted-keys` | *(empty)* | at once | The armoured OpenPGP public keys this deployment verifies publisher signatures against - one or more concatenated -----BEGIN PGP PUBLIC KEY BLOCK----- sections. |
| `signature-trusted-public-keys` | *(empty)* | at once | The PEM public keys a bare RSA publisher signature is verified against - an Alpine package's signature member, whose key the client keeps in /etc/apk/keys/. |
| `signature-trusted-signers` | *(empty)* | at once | Per-namespace pinned signers, e.g. "org.apache.* = openpgp:0x1234ABCD", comma- or newline-separated, a trailing * matching a whole namespace. |
| `signature-untrusted` | `QUARANTINE` | at once | Verdict for a well-formed signature by a signer this deployment has no reason to believe - no key for it, or a key not admitted for that namespace. |
| `strict-hold-mapping` | `false` | at once | Off by default: after an accepted publish through a blobs-namespace format, the publish-time hold-mapping round-trip check verifies the format's blobKeys/servedPaths resolve the served path and content hash just laid out (so a retroactive KEV/license hold could retract it). |
| `vulnerability-action` | `REJECT` | at once | Verdict for an artifact whose advisories reach the threshold above. |
| `vulnerability-threshold` | `CRITICAL` | at once | Reject vulnerabilities at or above this CVSS band; |

### Proxy

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `immaturity-hold-days` | `2` | at once | Quarantine proxied artifacts the upstream published within this many days; |
| `proxy-allow-internal` | `false` | on restart | Permit proxy upstreams, and the download URLs an upstream document advertises, that are plain http or resolve to a loopback, private, link-local or cloud-metadata address. |
| `proxy-enabled` | `true` | at once | Proxy reads that miss locally from the upstreams, caching and bridging them. |

### Hardening proxy

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `harden-rescreen` | `false` | at once | Back-fill a repository switched to `harden` late: |
| `harden-rescreen-interval` | `P1D` | at once | How often the migration re-screen sweep runs, as an ISO-8601 duration. |

### Retention

Explained in [Retention, pins and cleanup](/repository/retention/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `cleanup-interval` | `PT1H` | at once | How often the scheduled reaps run. |
| `collect` | `true` | at once | Reclaim the space of content nothing refers to any more, on the walks that carry the collector. |
| `gc` | `mark-sweep` | on restart | The collector to use, by name. |
| `gc.grace` | `PT0S` | at once | The least time between marking content unreferenced and deleting it, on top of the two-pass rule. |
| `gc.stride` | `20000` | at once | Items the collector handles between checkpoints. |
| `import-job-ttl` | `P7D` | at once | Auto-dismiss completed or failed migration jobs (and their remembered sources) this ISO-8601 duration after the sweep first sees them finished; |
| `keep-last` | `0` | at once | Keep at most this many newest versions per coordinate; |
| `max-age` | *(empty)* | at once | Evict versions older than this ISO-8601 duration; |
| `not-downloaded-for` | *(empty)* | at once | Evict versions not downloaded within this ISO-8601 duration; |
| `prerelease-expiry` | *(empty)* | at once | Evict prereleases older than this ISO-8601 duration; |
| `quarantine-log-cap` | `0` | at once | Keep at most this many newest gate-decision log rows; |
| `quarantine-log-retention` | `P180D` | at once | Remove gate-decision log rows older than this ISO-8601 duration on the scheduled cleanup pass; |
| `retention` | *(empty)* | at once | Select the retention engine by name; empty resolves the single enabled engine, and more than one enabled engine needs this setting to disambiguate them. |
| `scheduled-cleanup` | `true` | at once | Run the scheduled reaps: finished import jobs past their time-to-live and a quota'd tenant's usage recount. |
| `staging-ttl` | `P30D` | at once | On the scheduled cleanup pass, drop open staging repositories untouched for this ISO-8601 duration (their staged artifacts are unpublished and garbage-collected) and remove promoted/dropped staging markers of the same age. |

### Maintenance

Explained in [Operations](/repository/operations/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `counters.flush` | `PT1M` | on restart | How long a node holds the quota and folder-size deltas its publishes produce before folding them into one compare-and-set per counter; |
| `inventory-backfill` | `true` | on restart | Let the shared rebuild pass restore the published/ inventory row of a blobs-namespace release whose row is missing, reading the coordinate back out of the release's own stored pointer. |
| `listing-rebuild` | `true` | at once | Regenerate, at the end of a walk of the store, the stored listings - the packuments, Simple pages, Packages files, repodata, sparse-index files, tag lists and search documents a client fetches, each maintained incrementally by the write that changes it and materialised on first read - so any drift an interrupted write could have left is corrected by the walk (jenreg.walks) and never by a read. |
| `rebuild` | `true` | at once | Drive every discovered walk consumer (a derived-metadata rebuilder's back-fill, refresh and self-heal route) from one shared enumeration of the pointer roots. |
| `reconcile` | `true` | at once | Rebuild the publish-time inventory facts from the live pointer tree, in both directions, whenever a walk of the store runs: |
| `torn-write` | `true` | at once | Judge crash-torn intermediate states whenever a walk of the store runs - a pointer whose blob is missing (flagged loudly; |
| `torn-write-apply` | `false` | at once | When the torn-write reconcile is on, actually remove the dangling pointers a walk finds (a pointer that serves nothing because its blob is gone) rather than only flagging and counting them. |
| `walks` | *(see the setting)* | at once | The walks of the store this deployment schedules, as a JSON array of entries - each a name, a cron expression (Spring's grammar with seconds, in UTC) and the consumers that ride it ("*" for every one installed), enabled unless said otherwise. |
| `withheld-reconcile` | `true` | at once | Lift, whenever a walk of the store runs, a content-addressed withheld/<hash> serving marker for which no live holder remains - a marker stranded by two byte-identical aliases releasing at once, by a crash in the enforce sweep's marker-before-pointer window, or a pre-existing orphan. |

### Operations

Explained in [Operations](/repository/operations/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `auth.cache-ttl` | `PT15M` | on restart | How long a node serves a credential's documents before asking the store again. |
| `batch-upload` | `false` | at once | Explode a single PUT carrying the Jenesis-Explode: |
| `batch-upload-max-entries` | `10000` | at once | The most members one exploded archive may publish; |
| `cache.document-ttl` | `PT30S` | on restart | How long a node serves a listing it has already read - a packument, a Simple page, a maven-metadata.xml, a Packages file, a tag list - from memory before reading the store again, so a burst of builds starting at once costs the store one read per document rather than one per build. |
| `cache.miss-ttl` | `PT10S` | on restart | How long a node remembers that a coordinate it looked for was not there, and answers the same probe from memory instead of reading the store again - a build tool asking for a version range, a missing snapshot or an optional classifier asks the same question of the same repositories many times in a row. |
| `cache.ttl` | `PT5M` | on restart | How long a node serves a credential, a settings document, a ceiling or a tenant list it has already read before asking the store again. |
| `cleanup-lease` | `PT10M` | on restart | How long one node holds the background-maintenance lease; |
| `demo` | `false` | on restart | Seed a fresh, completely empty repository with real artifacts (including old, benign-but-vulnerable coordinates like log4j-core 2.14.1 and lodash 4.17.11) so an evaluator has data to look at - pulled through the formats' own upstreams, screened by the compliance gate, with a small demo gate config applied. |
| `logs-buffer` | `1000` | on restart | How many recent log entries `/api/logs` keeps. |
| `download-flush-interval` | `PT6H` | on restart | How long download hits are held in memory before one compare-and-set adds them to the version's document and refreshes its last-download instant - at most one write per coordinate version per interval, and a count that lags by at most that. |
| `store-families` | `false` | on restart | Count every store operation by the key family it touched as well as by its name, reported as jenreg.store.family.<operation>.<family> beside jenreg.store.ops.<operation>. |
| `track-downloads` | `true` | on restart | Run the download-tracking worker; needed for the not-downloaded-for criterion. |
| `track-key-usage` | `true` | on restart | Stamp each credential's last use, at most once a day. |

### Consistency

Explained in [Running in production](/repository/deploying/#several-servers). Read only where `consistency.enabled` is set.

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `consistency.sweep-interval` | `PT1M` | on restart | How often a server records its fingerprint and compares its peers'. |
| `consistency.heartbeat` | *(the sweep interval)* | on restart | How often a server records its own fingerprint, if more often than it compares. |
| `consistency.staleness-window` | `PT5M` | on restart | How recently a server must have recorded its fingerprint to be compared. |
| `consistency.sweep-intervals` | `3` | on restart | How many sweeps a server may fall behind before it is reported stuck. |
| `consistency.dead-after` | `PT15M` | on restart | How long a silent server has before it is reported gone. |
| `consistency.forget-after` | `PT24H` | on restart | How long a gone server is remembered. |

### Webhooks

Explained in [Operations](/repository/operations/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `webhook` | `false` | on restart | Deliver per-tenant HTTP callbacks over the background drain when an artifact is published or unpublished, the gate quarantines one, a hold is released or discarded, a finding is recorded, or a staged set is promoted. |
| `webhook-allow-internal` | `false` | on restart | Permit webhook endpoints that resolve to a loopback, private, link-local or cloud-metadata address, AND plaintext http:// endpoints. |
| `webhook-attempts` | `5` | on restart | How many times a failing delivery is retried (with exponential backoff) before it is parked. |
| `webhook-endpoints` | *(empty)* | on restart | One endpoint per line or semicolon: '<https-url> [events]'. |
| `webhook-interval` | `PT1M` | on restart | How often the webhook outbox is drained. |
| `webhook-secrets` | *(empty)* | on restart | Per-endpoint HMAC-SHA256 signing secrets, one '<https-url>=<secret>' per line, keyed by the endpoint URL as it appears in 'webhook-endpoints'. |

### Outboxes

Explained in [Operations](/repository/operations/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `outbox-parked-cap` | `0` | on restart | A hard ceiling on a parked backlog: everything beyond the newest N is reclaimed whatever its age. |
| `outbox-parked-retention` | `P30D` | on restart | How long a terminally-failed (parked) forward or webhook delivery is kept before its drain reclaims it. |

### Index

Explained in [Repositories](/repository/repositories/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `index` | `false` | on restart | Publish an incremental, resumable repository index (Zstandard seekable chunks + descriptor) on the background sweep. |
| `index-interval` | `P1D` | on restart | How often an incremental index chunk is published. |
| `index-max-chunk` | `8388608` | on restart | Maximum compressed size in bytes of one published index chunk before it rotates. |
| `index-rebase` | `true` | at once | Rebase the published index onto a fresh chunk chain from every served pointer at the end of a walk of the store that carries this consumer (jenreg.walks). |

### Build cache

Explained in [The build cache](/repository/build-cache/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `build-cache` | `true` | on restart | Whether this deployment serves the remote build cache. |

### Console

Explained in [Access](/repository/access/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `console` | `true` | on restart | Whether this deployment serves the admin console. |
| `key-login` | `false` | on restart | Whether the console accepts a pasted login key as a sign-in method - a demo / simple-deployment on-ramp usable without SSO, disabled by default. |
| `setup-wizard` | `true` | at once | Send a super-admin who signs in with the starter key to the first-run setup screen, which walks the decisions a new deployment should make: |

### Defaults

Explained in [Settings](/repository/settings/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `block-private-import-hosts` | `true` | on restart | Reject a migration URL that is plaintext http, or that resolves to a loopback, link-local or private address. |
| `default-tenant` | `default` | on restart | The tenant this deployment serves - the first part of every URL, `/repository/<tenant>/…`, `/v2/<tenant>/…` and `/build/<tenant>/…`. |
| `public-url` | *(empty)* | on restart | The address clients reach this deployment at (https://repo.example.com), for the absolute URLs generated indexes carry. |
| `rate-limit` | `6000` | on restart | Requests a minute per tenant before `429`; `0` removes the limit, and a tenant's own ceiling on the **Repositories** page replaces it. |
| `trusted-proxies` | *(empty)* | on restart | Comma-separated CIDRs of reverse proxies whose X-Forwarded-For, X-Forwarded-Proto and X-Forwarded-Host are believed. |

### Formats

Explained in [Connecting your build tools](/repository/formats/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `terraform.prefix` | `/repository/default/terraform/registry` | on restart | The path this deployment serves its Terraform registry under, as the discovery document at /.well-known/terraform.json reports it. |

### Maven

Explained in [Connecting your build tools](/repository/formats/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `maven-metadata-compute` | `false` | on restart | Compute the artifact-level maven-metadata.xml on read rather than serving the publisher's stored document verbatim: |

### PyPI

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `pypi-provenance-url` | *(empty)* | on restart | Where the provenance document (PEP 740) of a proxied distribution is fetched from, the base of an integrity API answering <base>/<project>/<version>/<file>/provenance. |

### RubyGems

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Applies | Effect |
| --- | --- | --- | --- |
| `rubygems-attestations-url` | *(empty)* | on restart | Where the Sigstore attestations of a proxied gem are fetched from, the base of an API answering <base>/<name>-<version>.json with an array of bundles. |
