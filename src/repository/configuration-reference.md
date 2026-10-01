---
order: 18
title: Configuration reference
description: Every setting Jenesis Repository reads - the startup settings given in its environment, and the runtime settings changed in the console - with its environment variable, its default and what it does.
---

A deployment is configured in two ways, and this page lists both. **Startup settings** are given in the
environment the server starts in and change with a restart. **Runtime settings** are changed in the console under
**Settings → Settings**, where each shows whether it applies at once or on the next restart; they can be given in
the environment too, which then pins them.

Every setting is a key under `jenrepo.`, and its environment variable is the key upper-cased with dots and dashes
as underscores: `filesystem.root` is `JENREPO_FILESYSTEM_ROOT`. A format, feed or other module is switched off with
`JENREPO_<MODULE>=false`, as described in [Settings](/repository/settings/#modules).

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
| `operator-tenant` | *(the default tenant)* | The tenant whose keys may administer the whole deployment - its settings, upstreams, logs and tenants. |
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
| `repositories.<name>` | *(empty)* | A repository definition, as on **Settings → Upstreams → Repository routing**. It routes a repository that exists; it does not create one. |
| `proxy.<format>` | *(empty)* | The upstream a format fetches a miss from, as on **Settings → Upstreams → Format upstreams**. |
| `proxy-miss-ttl` | `60s` | How long an upstream miss is remembered. |

### Several servers

See [Running in production](/repository/deploying/#several-servers).

| Key | Default | Effect |
| --- | --- | --- |
| `consistency.enabled` | `false` | Have every server record a fingerprint of what it has seen, so a server that falls behind or disagrees is reported. |
| `consistency.node-id` | *(the host name)* | This server's stable name among its peers. |

## Runtime settings

The settings catalogue, as **Settings → Settings** shows it, grouped the same way. *Level* is the narrowest
level a value may be set at: the deployment's alone, or also a tenant's, one repository's or one build-cache
project's, each wider level holding the default the narrower one inherits - *own only* marks a setting with no wider
default. *Tier* says whether the wizard of that level asks it (*essential*), the settings pages show it
(*standard*), or fold it away as tuning (*advanced*). *Applies* says whether a change takes effect at once or on the
next restart.

### Access

Explained in [Access](/repository/access/#what-a-refused-caller-is-told).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `access-denied-status` | `not-found` | deployment | standard | at once | What a request for a tenant, a repository or an artifact the caller may not reach is answered, on every surface - the repository and registry paths, the build cache, the API and the console. not-found answers 404, exactly as a name that does not exist, so nobody can learn which tenants, repositories or artifacts exist by probing names and reading the status. forbidden answers 403, which tells a caller that their credential does not reach the name rather than that nothing is there, whether or not the name exists. |

### Build cache

Explained in [The build cache](/repository/build-cache/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `build-cache` | `true` | deployment | standard | on restart | Whether this deployment serves the remote build cache. |

### Build cache project

Explained in [The build cache](/repository/build-cache/#keeping-its-size-in-check).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `project-lru` | `true` | project | advanced | at once | Which entries a size-cap sweep evicts first: the least recently used (the default), or the most recently used when switched off. |
| `project-size` | `0` | project | essential | at once | How many bytes a project's entries may take together; past it the least recently used entries are evicted after a write, and by the reaper. 0 is no cap. |
| `project-ttl` | *(empty)* | project | essential | at once | How long an entry nobody has read or written is kept before the reaper removes it (P30D, 30d); unset inherits the tenant's or the deployment's, none keeps entries for ever. |

### Caches

Explained in [Operations](/repository/operations/#caches).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `auth.cache-ttl` | `PT15M` | deployment | advanced | on restart | How long a node serves a credential's documents before asking the store again. |
| `cache.document-ttl` | `PT30S` | deployment | advanced | on restart | How long a node serves a listing it has already read - a packument, a Simple page, a maven-metadata.xml, a Packages file, a tag list - from memory before reading the store again, so a burst of builds starting at once costs the store one read per document rather than one per build. |
| `cache.miss-ttl` | `PT10S` | deployment | advanced | on restart | How long a node remembers that a coordinate it looked for was not there, and answers the same probe from memory instead of reading the store again - a build tool asking for a version range, a missing snapshot or an optional classifier asks the same question of the same repositories many times in a row. |
| `cache.ttl` | `PT5M` | deployment | advanced | on restart | How long a node serves a credential, a settings document, a ceiling or a tenant list it has already read before asking the store again. |

### Collection

Explained in [Retention, pins and cleanup](/repository/retention/#how-space-is-reclaimed).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `collect` | `true` | deployment | essential | at once | Run the collector at the end of a walk, so the storage of content no live pointer names any more is freed. |
| `gc` | `mark-sweep` | deployment | essential | on restart | The collector to use, by name. |
| `gc.grace` | `PT2H` | deployment | advanced | at once | A wall-clock floor on the gap between condemning a blob and deleting it, on top of the two-pass rule, so an upload whose pieces are unreferenced for a while - a push's layers before its manifest - is not collected when collection runs often. |
| `gc.stride` | `20000` | deployment | advanced | at once | Items the collector handles between checkpoints: the reference batch it holds in memory, the re-work a crash costs, and how often it renews a segment claim. |

### Compliance

Explained in [Screening what comes in](/repository/screening/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `allow-redeploy` | `false` | tenant | standard | at once | Off by default: release-version immutability refuses re-pointing an already-published immutable release coordinate at different bytes (a 409), a supply-chain / dependency-confusion guard. |
| `deny-list` | *(empty)* | deployment | standard | at once | Comma-separated coordinates an operator forbids; always refused. |
| `deny-list-action` | `REJECT` | deployment | standard | at once | Verdict for a coordinate the deny list names. |
| `github` | `false` | deployment | essential | on restart | Consult the GitHub Advisory Database. |
| `github-endpoint` | `https://api.github.com` | deployment | advanced | on restart | The GitHub REST API base URL, for a self-hosted GitHub or a proxy. |
| `inspection.oversized` | `STREAM` | deployment | advanced | at once | What to do with an artifact larger than the inspection prefix - jenrepo.inspection.prefix-bytes, 32 MiB by default - which is the most of one artifact an inspector is ever handed in memory. |
| `kev-auto-hold` | `true` | deployment | standard | on restart | When a scheduled scan finds an already-published artifact whose CVE is on a known-exploited catalogue, quarantine it for review (the same hold the gate writes). |
| `kev-auto-release` | `true` | deployment | advanced | on restart | When a scheduled scan finds a retroactively KEV-held artifact whose CVE is no longer on any known-exploited catalogue (delisted, or the advisory retracted), automatically release the hold - the self-healing counterpart to KEV auto-hold. |
| `malware-action` | `REJECT` | deployment | essential | at once | Verdict for a package the feed marks malicious. |
| `openssf` | `false` | deployment | essential | on restart | Consult the curated OpenSSF malicious-packages feed (MAL- records, served by OSV.dev). |
| `openssf-endpoint` | `https://api.osv.dev` | deployment | advanced | on restart | The OSV API base URL serving the dataset, for a mirror or a proxy. |
| `osv` | `false` | deployment | essential | on restart | Consult the OSV (osv.dev) vulnerability feed. |
| `osv-endpoint` | `https://api.osv.dev` | deployment | advanced | on restart | The OSV API base URL, for a mirror or a proxy. |
| `policy-rules` | *(empty)* | tenant | standard | at once | Expression-based gate rules, one per line (or separated by ';'), each '&lt;verdict&gt; &lt;expression&gt;' where verdict is allow, quarantine or reject - e.g. 'quarantine #ecosystem == "npm" and #advisoryCount &gt; 0' or 'quarantine !#licenses.?[#this matches "(?i).*agpl.*"].empty'. |
| `provenance-admission-action` | `QUARANTINE` | tenant | standard | at once | Verdict for an artifact whose inbound attestation fails verification - unsigned by a trusted key, signed for a different artifact, or an unexpected builder or source. |
| `provenance-admission-builder` | *(empty)* | tenant | standard | at once | Comma-separated builder identities an inbound attestation must name, e.g. "https://github.com/acme/.github/workflows/release.yml@refs/tags/*". |
| `provenance-admission-key` | *(empty)* | tenant | standard | at once | PEM public key(s) an inbound attestation's DSSE signature must verify against - the builder keys the tenant trusts. |
| `provenance-admission-source` | *(empty)* | tenant | standard | at once | Comma-separated source repository URIs an inbound attestation's provenance must have built from, e.g. "git+https://github.com/acme/*". |
| `provenance-attestation-sweep` | `false` | deployment | standard | at once | Reclaim provenance attestations whose artifact is gone. |
| `provenance-attestation-sweep-interval` | `P1D` | deployment | advanced | at once | How often the attestation sweep runs. |
| `scan-full-every` | `24` | deployment | advanced | at once | Every Nth scheduled pass of the advisory scan, and of every other pass that re-reads what the repository holds, re-reads every published version; the passes between read only the versions published since the last full pass, and a catalogue that changed asks for a full pass at once. |
| `scan-interval-millis` | `3600000` | deployment | advanced | at once | Milliseconds between scheduled scans; each pass hits the upstream feeds. |
| `scan-lookback` | `PT1M` | deployment | advanced | at once | How far before the last full pass's stamp an incremental pass still looks. |
| `scheduled-scan` | `true` | deployment | standard | at once | Re-scan every repository's inventory against the advisory feeds on a schedule. |
| `signal-refresh-interval-millis` | `300000` | deployment | advanced | at once | Milliseconds between passes that draw a mirroring security signal (the known-exploited catalogue) into its stored snapshot, so a gate decision renders that snapshot instead of fetching on the publish thread. |
| `signature-attestation-lookup` | *(empty)* | tenant | advanced | at once | The attestation stores asked, by the artifact's digest, for the bundles they hold for an artifact just published, one &lt;ecosystem&gt; = &lt;url&gt; per line; the answer is kept beside the artifact and read as its evidence. |
| `signature-invalid` | `REJECT` | tenant | standard | at once | Verdict for an artifact whose signature does not match its bytes - the artifact was altered after signing, or the signature was made for different content. |
| `signature-key-discovery` | *(empty)* | tenant | standard | at once | Sources to fetch the signing keys this deployment does not hold from, comma-separated, asked in the order named; empty (the default) fetches nothing and the pass does not run, so an installation makes no outbound call until this names a source. |
| `signature-key-discovery-accept` | `false` | tenant | standard | at once | Trust the keys the discovery sources served: a key looked up by its own id as if the operator had pasted it into the trusted signing keys, a key found through a maintainer for the artifacts that name that maintainer. |
| `signature-key-discovery-interval` | `PT1H` | deployment | advanced | at once | How often the key-discovery pass asks the named sources for the keys still wanted, as a duration; a key a source did not have is asked for again after a day. |
| `signature-key-discovery-ubuntu-url` | `https://keyserver.ubuntu.com` | tenant | advanced | at once | Where keyserver.ubuntu.com is reached - the public instance by default, or any host speaking the HKP lookup (op=get&options=mr&search=0x&lt;key id&gt;), which every SKS-descended keyserver and most internal mirrors do. |
| `signature-key-discovery-url` | `https://keys.openpgp.org` | tenant | advanced | at once | Where keys.openpgp.org is reached - the public instance by default, or an internal mirror of it that speaks the same lookup by key id. |
| `signature-missing` | `ALLOW` | tenant | standard | at once | Verdict for an artifact carrying no signature where its format expects one. |
| `signature-missing-proxy` | `ALLOW` | tenant | standard | at once | Verdict for a proxied artifact carrying no signature where its format expects one. |
| `signature-provenance-accept` | *(empty)* | tenant | standard | at once | The OIDC issuers whose keyless identities are trusted by provenance, comma- or newline-separated - GitHub Actions' https://token.actions.githubusercontent.com being the one to name first. |
| `signature-quality-action` | `ALLOW` | tenant | standard | at once | What a signature below the quality floor does. |
| `signature-quality-floor` | `none` | tenant | standard | at once | The grade below which a signature raises a finding - none (the default, quality is reported and never gated), unusable, weak, acceptable or strong. |
| `signature-signer-changed` | `QUARANTINE` | tenant | standard | at once | Verdict for a coordinate signed by a different signer than its earlier versions carried. |
| `signature-sigstore-trusted-root` | *(empty)* | tenant | standard | at once | The Sigstore trusted root this deployment verifies bundles against - the JSON a `cosign trusted-root` or the public-good TUF repository serves, naming the Fulcio certificate authorities and the Rekor transparency logs to believe. |
| `signature-sigstore-trusted-root-interval` | `P1D` | deployment | advanced | at once | How often the trusted root is fetched again, as a duration. |
| `signature-sigstore-trusted-root-url` | *(empty)* | tenant | advanced | at once | Where the Sigstore trusted root is fetched from when none is pasted above. |
| `signature-sweep` | `false` | tenant | standard | at once | Apply the signature dials below to what is already published: the sweep re-judges the signature outcome and grade the gate recorded for each version under the current dials and holds a version they no longer admit, in the same review queue as a publish-time hold. |
| `signature-sweep-interval` | `P1D` | deployment | advanced | at once | How often the signature sweep runs while switched on, as a duration; every version is judged on its first and every Nth pass, the versions published since between. |
| `signature-trusted-certificates` | *(empty)* | tenant | standard | at once | The PEM certificates a PKCS#7 (CMS) publisher signature must chain to - one or more concatenated -----BEGIN CERTIFICATE----- blocks: a NuGet author or repository signing root, a Swift registry's. |
| `signature-trusted-keys` | *(empty)* | tenant | standard | at once | The armoured OpenPGP public keys this deployment verifies publisher signatures against - one or more concatenated -----BEGIN PGP PUBLIC KEY BLOCK----- sections. |
| `signature-trusted-public-keys` | *(empty)* | tenant | standard | at once | The PEM public keys a bare RSA publisher signature is verified against - an Alpine package's signature member, whose key the client keeps in /etc/apk/keys/. |
| `signature-trusted-signers` | *(empty)* | tenant | standard | at once | Per-namespace pinned signers, e.g. "org.apache.* = openpgp:0x1234ABCD", comma- or newline-separated, a trailing * matching a whole namespace. |
| `signature-untrusted` | `QUARANTINE` | tenant | standard | at once | Verdict for a well-formed signature by a signer this deployment has no reason to believe - no key for it, or a key not admitted for that namespace. |
| `strict-hold-mapping` | `false` | deployment | advanced | at once | Off by default: after an accepted publish through a blobs-namespace format, the publish-time hold-mapping round-trip check verifies the format's blobKeys/servedPaths resolve the served path and content hash just laid out (so a hold placed after the publish could retract it). |
| `vulnerability-action` | `REJECT` | deployment | essential | at once | Verdict for an artifact whose advisories reach the threshold above. |
| `vulnerability-threshold` | `CRITICAL` | deployment | essential | at once | Reject vulnerabilities at or above this CVSS band; NONE disables the check. |

### Consistency

Explained in [Running in production](/repository/deploying/#several-servers).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `consistency.dead-after` | `PT15M` | deployment | advanced | on restart | How long a node may publish nothing before the fleet reports it dead rather than stale. |
| `consistency.forget-after` | `PT24H` | deployment | advanced | on restart | How long a dead node's fingerprint is kept before the sweep removes it, so a decommissioned node leaves the report rather than sitting in it for good. |
| `consistency.heartbeat` | *(empty)* | deployment | advanced | on restart | How often this node publishes its own fingerprint for the fleet to compare. |
| `consistency.staleness-window` | `PT5M` | deployment | advanced | on restart | How recently a node must have published its fingerprint to be counted live. |
| `consistency.sweep-interval` | `PT1M` | deployment | advanced | on restart | How often a node publishes its own fingerprint and compares the fleet's. |
| `consistency.sweep-intervals` | `3` | deployment | advanced | on restart | How many sweep intervals a node may fail to advance its cursor before it is reported stuck rather than merely behind. |

### Console

Explained in [Access](/repository/access/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `console` | `true` | deployment | standard | on restart | Whether this deployment serves the admin console. |
| `key-login` | `true` | deployment | essential | on restart | Whether the console accepts a pasted login key as a sign-in method - the way into a deployment before single sign-on is set up, on by default. |

### First run

Explained in [Settings](/repository/settings/#first-run-setup).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `demo` | `false` | deployment | standard | on restart | Seed a fresh, completely empty repository with real artifacts (including old, benign-but-vulnerable coordinates like log4j-core 2.14.1 and lodash 4.17.11) so an evaluator has data to look at - pulled through the formats' own upstreams, screened by the compliance gate, with a small demo gate config applied. |
| `setup-wizard` | `true` | deployment | essential | at once | Send a super-admin who signs in with the starter key to the first-run setup screen, which walks the decisions a new deployment should make: the starter credentials, the compliance verdicts, the advisory feeds, retention. |

### Formats

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `terraform.git-hosts` | *(empty)* | deployment | standard | on restart | The git hosts a proxied Terraform module's git source may be fetched from, so the module downloads through this repository rather than being cloned by the client. |
| `terraform.git-refuse-unlisted` | `false` | deployment | standard | on restart | Whether a proxied Terraform module whose git source cannot be fetched through this repository - its host is not in the git hosts, or it names no single ref - is refused rather than handed to the client to clone. |
| `terraform.prefix` | `/repository/releases/terraform/registry` | deployment | advanced | on restart | The path this deployment serves its Terraform registry under, as the discovery document at /.well-known/terraform.json reports it. |

### Hardening proxy

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `harden-rescreen` | `false` | deployment | standard | at once | Back-fill a repository switched to `harden` late: a Lease-guarded, idempotent background pass re-screens the artifacts cached before hardening was enabled from their local bytes, records the digest-pinned verdict, and evicts any that re-screen non-ALLOW so a subsequent request re-fetches through the hardened leg. |
| `harden-rescreen-interval` | `P1D` | deployment | advanced | at once | How often the migration re-screen sweep runs, as an ISO-8601 duration. |

### Index

Explained in [Repositories](/repository/repositories/#overview).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `index` | `false` | deployment | standard | on restart | Publish an incremental, resumable repository index (Zstandard seekable chunks + descriptor) on the background sweep. |
| `index-interval` | `P1D` | deployment | advanced | on restart | How often an incremental index chunk is published. |
| `index-max-chunk` | `8388608` | deployment | advanced | on restart | Maximum compressed size in bytes of one published index chunk before it rotates. |
| `index-rebase` | `true` | deployment | advanced | at once | Rebase the published index onto a fresh chunk chain from every served pointer at the end of a walk of the store that carries this consumer (jenrepo.walks). |

### Limits

Explained in [Repositories](/repository/repositories/#limits).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `rate-limit` | `6000` | tenant | essential | on restart | Request ceiling in permits per minute per tenant; 0 disables. |
| `tenant-quota` | `0` | tenant | essential | at once | How many bytes of stored content a tenant's repositories may hold together; 0 is unlimited. |

### Maintenance

Explained in [Operations](/repository/operations/#walks).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `counters.flush` | `PT1M` | deployment | advanced | on restart | How long a node holds the quota and folder-size deltas its publishes produce before folding them into one compare-and-set per counter; the node itself counts them at once. 0 writes every delta as it happens, one compare-and-set per publish per counter. |
| `inventory-backfill` | `true` | deployment | advanced | on restart | Let the shared rebuild pass restore the inventory row of a blobs-namespace version whose row is missing, reading the coordinate back out of its own stored pointer - as a cached copy where its origin shows it was fetched from an upstream, as a release otherwise. |
| `listing-rebuild` | `true` | deployment | advanced | at once | Regenerate, at the end of a walk of the store, the stored listings - the packuments, Simple pages, Packages files, repodata, sparse-index files, tag lists and search documents a client fetches, each maintained incrementally by the write that changes it and materialised on first read - so any drift an interrupted write could have left is corrected by the walk (jenrepo.walks) and never by a read. |
| `rebuild` | `true` | deployment | advanced | at once | Drive every discovered walk consumer (a derived-metadata rebuilder's back-fill, refresh and self-heal route) from one shared enumeration of the pointer roots. |
| `reconcile` | `true` | deployment | advanced | at once | Rebuild the publish-time inventory facts from the live pointer tree, in both directions, whenever a walk of the store runs: a crash that skipped a sidecar write converges instead of leaving a served artifact invisible to retention and the search and license index, and a crashed eviction's orphan facts and derived rows go. |
| `torn-write` | `true` | deployment | advanced | at once | Judge crash-torn intermediate states whenever a walk of the store runs - a pointer whose blob is missing (flagged loudly; impossible under the blob-before-pointer ordering, so a signal of corruption) and a blob no pointer references (an orphan, confirmed and left to garbage collection). |
| `torn-write-apply` | `false` | deployment | advanced | at once | When the torn-write reconcile is on, actually remove the dangling pointers a walk finds (a pointer that serves nothing because its blob is gone) rather than only flagging and counting them. |
| `walks` | *(see the setting)* | deployment | essential | at once | The walks of the store this deployment schedules, as a JSON array of entries - each a name, a cron expression (Spring's grammar with seconds, in UTC) and the consumers that ride it ("*" for every one installed), enabled unless said otherwise. |
| `withheld-reconcile` | `true` | deployment | advanced | at once | Lift, whenever a walk of the store runs, a content-addressed withheld/&lt;hash&gt; serving marker for which no live holder remains - a marker stranded by two byte-identical aliases releasing at once, by a crash in the enforce sweep's marker-before-pointer window, or a pre-existing orphan. |

### Maven

Explained in [Connecting your build tools](/repository/formats/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `maven-metadata-compute` | `false` | deployment | advanced | on restart | Compute the artifact-level maven-metadata.xml on read rather than serving the publisher's stored document verbatim: reconcile only its &lt;versions&gt; list against the stored version folders (every other field preserved), and derive a document for a coordinate no client ever uploaded one for (an imported or batch-ingested repository). |

### Network

Explained in [Running in production](/repository/deploying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `block-private-import-hosts` | `true` | deployment | standard | on restart | Reject a migration URL - an import's source or an export's target - that is plaintext http, or that resolves to a loopback, link-local or private address. |
| `public-url` | *(empty)* | deployment | standard | on restart | The address clients reach this deployment at (https://repo.example.com), for the absolute URLs generated indexes carry. |
| `trusted-proxies` | *(empty)* | deployment | standard | on restart | Comma-separated CIDRs of reverse proxies whose X-Forwarded-For, X-Forwarded-Proto and X-Forwarded-Host are believed. |
| `trusted-sites` | *(empty)* | deployment | advanced | at once | Origins a browser may send a write from although they are not this deployment's own - comma-separated, each as a browser sends it (https://console.example.com). |

### Operations

Explained in [Operations](/repository/operations/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `cleanup-lease` | `PT10M` | deployment | advanced | on restart | How long one node holds the background-maintenance lease; keep under the task intervals. |
| `download-flush-interval` | `PT6H` | deployment | advanced | on restart | How long download hits are held in memory before one compare-and-set adds them to the version's document and refreshes its last-download instant - at most one write per coordinate version per interval, and a count that lags by at most that. 0 or off writes on every drain. |
| `logs-buffer` | `1000` | deployment | advanced | on restart | How many most-recent log entries the in-memory recent-logs ring retains (the ring behind GET /api/logs and the operator GET /api/admin/logs) before the oldest is evicted. |
| `store-families` | `false` | deployment | advanced | on restart | Count every store operation by the key family it touched as well as by its name, reported as jenrepo.store.family.&lt;operation&gt;.&lt;family&gt; beside jenrepo.store.ops.&lt;operation&gt;. |
| `track-downloads` | `true` | deployment | standard | on restart | Run the download-tracking worker; needed for the not-downloaded-for criterion. |
| `track-key-usage` | `true` | deployment | standard | on restart | Stamp each credential's last use, at most once per day. |

### Outboxes

Explained in [Operations](/repository/operations/#webhooks).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `outbox-parked-cap` | `0` | deployment | advanced | on restart | A hard ceiling on a parked backlog: everything beyond the newest N is reclaimed whatever its age. |
| `outbox-parked-retention` | `P30D` | deployment | advanced | on restart | How long a terminally-failed (parked) forward or webhook delivery is kept before its drain reclaims it. |

### Proxy

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `immaturity-hold-days` | `2` | deployment | essential | at once | Quarantine proxied artifacts the upstream published within this many days; 0 disables. |
| `proxy-allow-internal` | `false` | deployment | standard | on restart | Permit proxy upstreams, and the download URLs an upstream document advertises, that are plain http or resolve to a loopback, private, link-local or cloud-metadata address. |
| `proxy-enabled` | `true` | deployment | standard | at once | Proxy reads that miss locally from the upstreams, caching and bridging them. |
| `proxy-fetch-deadline` | `PT0S` | deployment | advanced | at once | The longest one upstream fetch may take, from the request to the last byte, before it is abandoned. |
| `proxy-throughput-floor` | `16384` | deployment | advanced | at once | The least an upstream fetch must deliver over each minute spent waiting on it, in bytes, or it is abandoned as the idle timeout abandons one that goes silent. |

### PyPI

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `pypi-provenance-url` | *(empty)* | deployment | advanced | on restart | Where the provenance document (PEP 740) of a proxied distribution is fetched from, the base of an integrity API answering &lt;base&gt;/&lt;project&gt;/&lt;version&gt;/&lt;file&gt;/provenance. |

### Record lifetimes

Explained in [Retention, pins and cleanup](/repository/retention/#other-things-that-expire).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `export-job-ttl` | `P7D` | deployment | advanced | at once | How long a finished export job's status stays before the scheduled cleanup dismisses it. |
| `import-job-ttl` | `P7D` | deployment | advanced | at once | Auto-dismiss completed or failed migration jobs (and their remembered sources) this ISO-8601 duration after the sweep first sees them finished; a running job is never touched. |
| `quarantine-log-cap` | `0` | deployment | advanced | at once | Keep at most this many newest gate-decision log rows; 0 disables the count cap. |
| `quarantine-log-retention` | `P180D` | deployment | standard | at once | Remove gate-decision log rows older than this ISO-8601 duration on the scheduled cleanup pass; a still-held path keeps its verdict whatever its age. |
| `staging-ttl` | `P30D` | deployment | standard | at once | On the scheduled cleanup pass, drop open staging repositories untouched for this ISO-8601 duration (their staged artifacts are unpublished and garbage-collected) and remove promoted/dropped staging markers of the same age. |

### Retention

Explained in [Retention, pins and cleanup](/repository/retention/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `cleanup-interval` | `PT1H` | deployment | advanced | at once | How often the scheduled reaps run. |
| `keep-last` | `0` | repository | essential | at once | Keep at most this many newest versions per coordinate; 0 disables the count cap. |
| `max-age` | *(empty)* | repository | essential | at once | Evict versions older than this duration (P30D, 30d); unset inherits the tenant's or the deployment's rule, none switches the rule off for this repository. |
| `not-downloaded-for` | *(empty)* | repository | essential | at once | Evict versions not downloaded within this duration - it needs download tracking; unset inherits the tenant's or the deployment's rule, none switches the rule off for this repository. |
| `prerelease-expiry` | *(empty)* | repository | essential | at once | Evict prereleases older than this duration; unset inherits the tenant's or the deployment's rule, none switches the rule off for this repository. |
| `retention` | *(empty)* | deployment | standard | at once | Select the retention engine by name; empty resolves the single enabled engine, and more than one enabled engine needs this setting to disambiguate them. |
| `scheduled-cleanup` | `true` | deployment | standard | at once | Run the scheduled reaps: finished import jobs past their time-to-live and a quota'd tenant's usage recount. |

### Routing

Explained in [Proxying upstreams](/repository/proxying/#a-repository-s-routing).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `routing` | *(empty)* | repository (own only) | essential | at once | Whether this repository accepts uploads and where it fetches what it lacks, as clauses: writable, fallback &lt;url&gt; [nocache] [harden] [unscreened], fallback &lt;repository&gt;. |

### RubyGems

Explained in [Proxying upstreams](/repository/proxying/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `rubygems-attestations-url` | *(empty)* | deployment | advanced | on restart | Where the Sigstore attestations of a proxied gem are fetched from, the base of an API answering &lt;base&gt;/&lt;name&gt;-&lt;version&gt;.json with an array of bundles. |

### Search

Explained in [Repositories](/repository/repositories/#browse-search).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `full-text-search` | `false` | repository | essential | at once | Keep a full-text index of this repository - package names, descriptions, keywords and authors - and answer searches from it. |
| `search-incremental` | `true` | deployment | advanced | on restart | Apply only what changed (from the dirty-index feed) each pass instead of a full rebuild - the O(delta) steady state. |
| `search-index-claim` | `PT10M` | deployment | advanced | on restart | How long an unfinished rebuild's claim on an index generation is honoured before another node's rebuild takes it over as a dead rebuild's - the cost a crashed or stalled node's rebuild puts on the fleet. |
| `search-index-interval` | `PT10M` | deployment | advanced | on restart | How often the search-index pass applies what was published or removed since it last ran, for each repository with full-text search on. |
| `search-rebuild` | `true` | deployment | advanced | at once | Rebuild the search index of each repository with full-text search on from truth, and compact its change feed, at the end of a walk of the store that carries this consumer (jenrepo.walks): the reconcile that heals whatever the feed missed. |
| `search-reconcile-interval` | *(empty)* | deployment | advanced | on restart | How long after its last full reconcile the pass rebuilds a repository's index from truth by itself, healing whatever the change feed missed; unset, the default, leaves the reconcile to the walk: the search-rebuild consumer rebuilds from truth and compacts the feed when a walk carrying it runs (jenrepo.walks). |

### Serving

Explained in [Connecting your build tools](/repository/formats/#maven).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `folder-listing` | `false` | repository | advanced | at once | Answer a folder URL of a Maven repository - a path ending in / - with a page listing what it serves, a thousand names at a time, for the clients that list a folder where maven-metadata.xml is missing (Coursier, sbt) and for people browsing. |

### Tenancy

Explained in [Settings](/repository/settings/#tenants).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `default-tenant` | `releases` | deployment | essential | on restart | Tenant a request resolves to when its key carries none. |

### Uploads

Explained in [Operations](/repository/operations/).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `batch-upload` | `false` | deployment | standard | at once | Explode a single PUT carrying the Jenesis-Explode: zip header into one publish per archive entry, each screened by the compliance gate. |
| `batch-upload-max-bytes` | `4294967296` | deployment | advanced | at once | The most bytes one exploded archive's entries may inflate to in all. |
| `batch-upload-max-entries` | `10000` | deployment | advanced | at once | The most members one exploded archive may publish; the walk stops at this cap. |
| `batch-upload-max-ratio` | `100` | deployment | advanced | at once | How many times the compressed bytes read an exploded archive may inflate to, once past a mebibyte - a ratio no archive of artifacts reaches and a zip bomb starts from. |
| `upload-max-bytes` | `10737418240` | deployment | standard | at once | The most one request may send, in bytes: a publish declaring a larger body is refused with 413 before any of it is read, and one streaming without a declared length is refused at the byte that crosses it, so nothing of it is kept. |

### Webhooks

Explained in [Operations](/repository/operations/#webhooks).

| Key | Default | Level | Tier | Applies | Effect |
| --- | --- | --- | --- | --- | --- |
| `webhook` | `false` | deployment | essential | on restart | Deliver per-tenant HTTP callbacks over the background drain when an artifact is published or unpublished, the gate quarantines one, a hold is released or discarded, a finding is recorded, or a staged set is promoted. |
| `webhook-allow-internal` | `false` | deployment | standard | on restart | Permit webhook endpoints that resolve to a loopback, private, link-local or cloud-metadata address, AND plaintext http:// endpoints. |
| `webhook-attempts` | `5` | deployment | advanced | on restart | How many times a failing delivery is retried (with exponential backoff) before it is parked. |
| `webhook-endpoints` | *(empty)* | tenant | essential | on restart | One endpoint per line or semicolon: '&lt;https-url&gt; [events]'. 'events' is a comma-list of 'publish,unpublish,quarantine,release,discard,finding,promotion' or '*' (all). |
| `webhook-interval` | `PT1M` | deployment | advanced | on restart | How often the webhook outbox is drained. |
| `webhook-secrets` | *(empty)* | tenant | standard | on restart | Per-endpoint HMAC-SHA256 signing secrets, one '&lt;https-url&gt;=&lt;secret&gt;' per line, keyed by the endpoint URL as it appears in 'webhook-endpoints'. |
