---
order: 6
title: Proxying
description: Serving what the repository does not hold yet - pointing a format at an upstream, how a miss becomes a cached local hit, the negative cache, revalidation, digest checks, and the settings behind them.
---

A repository is most useful as a build's **single front door**: it serves your own artifacts and, on a miss,
fetches the public ones from upstream, stores them, and serves them from then on. Jenesis Repository does
this per format - the Maven layout can pull through from Maven Central, the OCI registry from Docker Hub -
once you tell it where upstream is. Nothing is proxied until you do.

## Pointing a format upstream

One setting per format names its upstream, keyed by the format id:

```bash
JENREG_PROXY_MAVEN=https://repo1.maven.org/maven2/
JENREG_PROXY_OCI=https://registry-1.docker.io/
```

With `JENREG_PROXY_MAVEN` set, `http://localhost:8080/repository/maven/` resolves everything on Maven
Central as well as what you published, so a build needs one `<mirror>` entry. With `JENREG_PROXY_OCI` set,
`docker pull localhost:8080/library/debian` fetches the image through your server. An upstream should be
`https`: the server warns loudly at boot about one that is not, but proxies through it all the same.

## How a miss becomes a local hit

A `GET` or `HEAD` is served locally first. When that is a `404` and the format has an upstream, the format
maps the request to the upstream URL and fetches it. An **immutable artifact** - a jar, a POM of a released
version, an image layer - is stored content-addressed as it streams through, and served. The next request
for it is a plain local hit that never touches the network again. The copy is a stream, digest and all, so a
multi-hundred-megabyte layer is mirrored in a small, fixed heap.

A **mutable index** - a `maven-metadata.xml` - is never cached that way, because it changes upstream. It is
fetched fresh on each request, so an artifact published upstream after your first look shows through. To
avoid re-downloading an index that has not changed, the fetcher **revalidates** it: it remembers the `ETag`
or `Last-Modified` and sends a conditional request, and a `304 Not Modified` answers from the remembered
bytes. The upstream is still asked every time; only the transfer is saved.

### The negative cache

A build tool makes a flood of requests for things that are not upstream at all: a version range it probes,
a missing `SNAPSHOT`, an optional classifier, a `.sha256` a client guesses at. Re-asking upstream for each
one multiplies load and can trip its rate limit. So a definite upstream **`404` is remembered** for a short
window and answered from memory.

Only a definite `404` is cached. A transport failure or an auth challenge (`401`, `403`) is not, since it
is transient or resolvable, and every success passes through untouched. An entry expires after
`jenreg.proxy-miss-ttl` - one minute by default - so a newly published artifact is picked up within that
window.

### Verifying what upstream sent

Where upstream publishes a digest, the fetched bytes are held to it **before anything is linked**. The blob
may be stored first - that is how the digest is computed while the bytes stream - but nothing points at it
until the check passes. A Maven artifact is checked against the `.sha1` published beside it, and a mismatch
is refused rather than served. The OCI mirror verifies every blob against the `sha256:` digest that
addresses it, and a manifest against the digest the upstream registry reports.

The raw layout is the exception. A plain file mirror publishes no digest for what it serves, so a raw
pull-through is stored and served on the upstream's word alone.

That matters because the alternative is worse than a failed download. A proxy that stores whatever upstream
returned turns one bad response - a corrupted mirror, a tampered hop - into a durable local artifact that
every later client receives. Refusing at the point of fetch keeps a bad byte from becoming the repository's
own answer.

Two documents are answered `502` rather than `404` when this server could not read them upstream, or
refused what it read: a `maven-metadata.xml`, and Gradle's `.module` descriptor. A client resolves against
the absence of both, so a `404` would read as "this coordinate has nothing" and resolve something else
without an error.

### The OCI mirror

The OCI format follows the Distribution **bearer-token handshake** an upstream registry demands: a `401`
with a `Bearer` challenge is exchanged for a token and the fetch is retried. A multi-architecture image
index is fetched, stored and served as it is; the client then asks for the per-architecture manifest by
digest, and that fetch is proxied in turn. A mirrored layer dedupes against everything else the repository
holds, because an OCI digest is the store's own key.

Only blobs and manifests are proxied. `tags/list` and `_catalog` are served from this server's own stored
documents, so a mirrored registry's tag list shows what this server holds, never the upstream's catalogue.

## The fetcher module

All upstream traffic - a proxy fetch, an import, a revalidation - goes through one HTTP fetcher, which is a
discovered module like every other capability. Without it the server still runs: it serves only what it
holds, and an import is refused with `501`. An installed fetcher can be switched off with
`jenreg.http=false`, which has the same effect.

<div class="warning">
  Selecting a fetcher by name with <code>jenreg.fetcher=&lt;name&gt;</code> is different from leaving the
  choice to discovery. A named fetcher that no installed module answers to <strong>fails the boot</strong>,
  because an operator who named a transport and silently got none would see every proxy route answer
  <code>404</code> as if upstream held nothing.
</div>

A single fetch is bounded by `jenreg.proxy.request-timeout`, one minute by default, so a hanging upstream
cannot hold a request open indefinitely. This one key is read as a system property
(`-Djenreg.proxy.request-timeout=PT30S`), not from the environment.

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.proxy.<format>` | *(unset - no proxying)* | The upstream URL for a format: `jenreg.proxy.maven`, `jenreg.proxy.oci`, `jenreg.proxy.raw`. |
| `jenreg.proxy-miss-ttl` | `60s` | How long an upstream `404` is remembered; ISO-8601 (`PT90S`) or `90s` / `5m`; `0` disables the negative cache. |
| `jenreg.proxy.request-timeout` | `PT1M` | Per-request upstream timeout, ISO-8601 or plain seconds. System property only. |
| `jenreg.http` | `true` | Switch the HTTP fetcher off; the server then serves local content only. |
| `jenreg.fetcher` | *(discovered)* | Select a fetcher by name; a name nothing answers to fails the boot. |

Leave the miss window at its default unless an upstream publishes very frequently and you need a miss
re-checked sooner. Lowering it trades a little more upstream traffic for faster pickup of a just-published
artifact; raising it shields a rate-limited upstream from a build tool's probing.
