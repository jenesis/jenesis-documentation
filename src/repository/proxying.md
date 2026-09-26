---
order: 6
title: Proxying upstreams
description: Serving what the repository does not hold yet from Maven Central, npm, Docker Hub or a private registry - format upstreams, repository definitions with fallbacks and groups, upstream credentials, and how a fetched artifact is checked and kept.
---

A repository is most useful as a build's **single front door**: it serves your own packages and, on a miss,
fetches the public ones from upstream, screens them, keeps them, and serves them from then on. Nothing is
fetched from anywhere until you name an upstream, so a new deployment makes no outbound call on its own.

## A format upstream

The quickest way is one upstream per format, under **Settings → Settings → Format upstreams**: enter a format
and the URL it fetches its misses from, and save.

| Format | A common upstream |
| --- | --- |
| `maven` | `https://repo1.maven.org/maven2/` |
| `npm` | `https://registry.npmjs.org/` |
| `pypi` | `https://pypi.org/` |
| `oci` | `https://registry-1.docker.io/` |

From then on every repository holding that format fetches its misses from the upstream: a Maven build pointed at
a Maven repository named `libraries` - `/repository/releases/libraries/maven/` - resolves everything on Maven Central
as well as what you published, and with an `oci` repository named `images`,
`docker pull repo.example.com/releases/images/library/debian` fetches the image through your server - the tenant
and the repository lead the image's name, and the rest is its name upstream. The repository has to exist first; a
request to one that was never created is answered `404`, upstream or not. The same setting can be given in the
environment, as `JENREG_PROXY_MAVEN=https://repo1.maven.org/maven2/`.

## Signed packages from upstream

Maven Central signs what it serves, and the gate checks every signature it finds. A new deployment trusts no
signer yet, so the first time it fetches a signed artifact from Maven Central, the artifact is **held in
Quarantine** with the reason *No trusted signer*, and the build that asked gets `404`. Decide once, under
**Settings → Settings** in the **Compliance** group, how this deployment should treat signers it does not know:

- **Trust the signers you rely on.** Paste their public keys into `signature-trusted-keys`, and optionally pin
  them to their namespaces with `signature-trusted-signers` - `org.apache.* = openpgp:…`. The strictest choice, and
  the most work.
- **Look the keys up.** `signature-key-discovery=keyserver.ubuntu.com,keys.openpgp.org` fetches each signer's key
  from the public keyservers in the background, and `signature-key-discovery-accept=true` trusts what they serve.
- **Allow signatures from unknown signers.** `signature-untrusted=ALLOW` admits them. A signature that does not match
  its bytes is still refused, and a package whose signer changes between versions is still held.

A setting changes what happens from then on; an artifact already held stays in **Quarantine** until an editor
releases it.

## Repository definitions

A **definition** says what a repository is made of, and is where more than one upstream, or a mix of hosted and
fetched content, is described. It describes a repository rather than creating one: the repository is created with
its type as [Repositories](/repository/repositories/) describes, and the definition then routes what it serves.
Definitions are edited under **Settings → Settings → Repository definitions**, a name and a definition each:

| Definition | The repository |
| --- | --- |
| `hosted` | Accepts uploads and fetches nothing - what a repository is when it has no definition. |
| `proxy https://repo1.maven.org/maven2/` | Only fetches from the upstream, and refuses uploads. |
| `group internal,central` | Serves from each named repository in turn, and refuses uploads. |
| `writable fallback https://repo1.maven.org/maven2/` | Accepts uploads *and* fetches misses from the upstream. |

A fallback may be another repository by name instead of a URL, and several fallbacks are tried in order. Each
can carry options:

| Option | Effect |
| --- | --- |
| `nocache` | Serve what the upstream returns without keeping it. |
| `harden` | Screen every fetched file in full before serving a byte of it. |
| `unscreened` | Skip the gate for this upstream - flagged as a warning on the Repositories page. |
| `match=<ecosystem>:<pattern>` | Only send matching coordinates to this fallback, such as `match=maven:com.example.*`. |

A definition is checked when it is saved: one that could not work is refused with the reason, and one that works
but is risky - a plaintext upstream, mixed screening - is saved and listed under **Definition warnings** on the
**Repositories** page.

## Private upstreams

An upstream that needs credentials gets them under **Settings → Settings → Upstream credentials**: the host name,
and a user name and password, a bearer token, or a header name and value. The credential is sent to that host
alone, whichever repository fetches from it.

An upstream must be `https` on a public address: a plaintext URL, or one that resolves to a private, loopback or
cloud-metadata address, is refused unless `proxy-allow-internal` permits it - a fetch carries your credentials,
and an unscreened address would turn the proxy into a way into your own network.

## What happens on a miss

A request is always answered locally first. On a miss, the repository fetches from the upstream and:

- **checks it** - against the digest the upstream publishes where there is one, a Maven artifact against its
  `.sha1`, an image layer against its `sha256:` name - and refuses a mismatch rather than keeping it;
- **screens it** through the same gate a publish passes, as described in [Screening what comes
  in](/repository/screening/);
- **keeps it**, so the next request is a local hit that never reaches the upstream.

An index that changes upstream - a `maven-metadata.xml`, an npm package document - is fetched fresh each time,
with a conditional request so an unchanged one costs no transfer. A definite `404` from upstream is remembered for
a minute (`proxy-miss-ttl`), so a build probing for things that do not exist does not flood the upstream.

Where an index names each artifact's download URL, the served copy points those URLs back at this repository, so
a client installs through it rather than straight from the upstream. A Helm chart repository is one: the
`index.yaml` is served with each version's `urls` rewritten to this repository's `charts/`, its `digest` unchanged,
and a chart fetched through it is checked against that digest.
An Ivy repository is proxied file by file, each file checked against the `.sha1` the upstream publishes beside it.
A module's directory listing, which Ivy reads to resolve a revision such as `1.+`, is relayed as the upstream lists it.

## The cooldown on fresh versions

A version the upstream published **within the last two days** is held for review rather than served. A brand-new
release is the most likely moment for a compromised or malicious package, before anyone has noticed; two days lets
the feeds catch up. The hold is a quarantine, not a refusal: an editor can release it from **Quarantine**
at once. `immaturity-hold-days` changes the window, and `0` removes it.

<div class="note">
  <code>proxy-enabled</code> switches fetching off for the whole deployment while keeping every upstream you
  configured - useful for a deployment that must serve only what it already holds for a while.
</div>
