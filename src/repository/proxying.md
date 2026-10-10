---
order: 6
title: Proxying upstreams
description: Serving what the repository does not hold yet from Maven Central, npm, Docker Hub or a private registry - format upstreams, a repository's routing with fallbacks and groups, upstreams a module's or group's own domain names, upstream credentials, how a fetched artifact is checked and kept, how long an upstream's documents are remembered, and what a repository that both hosts and proxies answers.
---

A repository is most useful as a build's **single front door**: it serves your own packages and, on a miss,
fetches the public ones from upstream, screens them, keeps them, and serves them from then on. Nothing is
fetched from anywhere until you name an upstream, so a new deployment makes no outbound call on its own.

## A format upstream

Each format fetches its misses from one upstream per deployment, named under **Settings → Upstreams → Format
upstreams**. A format with one public registry lists it there with a **Use** button:

| Format | Public registry |
| --- | --- |
| `maven` (and `java`) | `https://repo1.maven.org/maven2/` |
| `npm` | `https://registry.npmjs.org/` |
| `pypi` | `https://pypi.org/` |
| `go` | `https://proxy.golang.org/` |
| `cargo` | `https://index.crates.io/` |
| `nuget` | `https://api.nuget.org/` |
| `rubygems` | `https://rubygems.org/` |
| `composer` | `https://repo.packagist.org` |
| `conan` | `https://center2.conan.io` |
| `cocoapods` | `https://cdn.cocoapods.org` |
| `debian` | `https://deb.debian.org/debian/` |
| `huggingface` | `https://huggingface.co/` |

For any other format - `oci`, `rpm`, `helm`, `conda`, `apk`, `swift`, `terraform` and the rest - or another
registry, enter the format and the URL it fetches its misses from, and save. Docker Hub, for instance, is
`https://registry-1.docker.io/` for the `oci` format.

From then on every repository holding that format fetches its misses from the upstream: a Maven build pointed at
a Maven repository named `libraries` - `/repository/releases/libraries/maven/` - resolves everything on Maven Central
as well as what you published, and with an `oci` repository named `images`,
`docker pull repo.example.com/releases/images/library/debian` fetches the image through your server - the tenant
and the repository lead the image's name, and the rest is its name upstream. The repository has to exist first; a
request to one that was never created is answered `404`, upstream or not. The same setting can be given in the
environment, as `JENREPO_PROXY_MAVEN=https://repo1.maven.org/maven2/`.

A tenant can name its own upstream for a format under the same page's section for that tenant; its repositories
then fetch from it instead of the deployment's, and a repository's **Overview** says which one it fetches through.

## Signed packages from upstream

Maven Central signs what it serves, and the gate checks every signature it finds. A new deployment trusts no
signer yet, so every signed artifact it fetches reads as signed by an untrusted signer: it is served, and that
outcome is recorded on its version for you to see. A signature that does not match its bytes is still refused, and a
package whose signer changes between versions is held for review.

To make signatures decide what is served, tell the deployment whom it trusts, under **Settings → Settings** in the
**Compliance** group:

- **Trust the signers you rely on.** Paste their public keys into `signature-trusted-keys`, and optionally pin
  them to their namespaces with `signature-trusted-signers` - `org.apache.* = openpgp:…`. The strictest choice, and
  the most work.
- **Look the keys up.** `signature-key-discovery=keyserver.ubuntu.com,keys.openpgp.org` fetches each signer's key
  from the public keyservers in the background, and `signature-key-discovery-accept=true` trusts what they serve.

Then set `signature-untrusted` to `QUARANTINE` to hold what anyone else signed for review, or to `REJECT` to refuse
it. A setting changes what happens from then on; an artifact already held stays in **Quarantine** until an editor
releases it.

## A repository's routing

A repository's **routing** says what it is made of, and is where more than one upstream, or a mix of uploaded and
fetched content, is described. It is a setting of the repository, `routing`, and it describes the repository
rather than creating one: the repository is created with its type as [Repositories](/repository/repositories/)
describes, and its routing then decides what it serves.

Routing is the deployment administrators' decision, since it names where the server fetches from. They set it on the
wizard's **Routing** step when a repository is created, and later on the repository's **Settings** page. A script
sets it with a key of the operator tenant:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"writable fallback https://repo1.maven.org/maven2/"}' \
  'https://repo.example.com/api/repository/settings/routing?repo=libraries'
jenrepo repos settings libraries set routing "writable fallback https://repo1.maven.org/maven2/"
```

Routing is written in two clauses - `writable`, and `fallback` followed by an upstream URL or a repository name -
and nothing else is accepted:

| Routing | The repository |
| --- | --- |
| `writable` | Accepts uploads and fetches nothing - what a repository is when it has no routing and its format no upstream. |
| `fallback https://repo1.maven.org/maven2/` | Only fetches from the upstream, and refuses uploads. |
| `fallback internal fallback central` | Serves from each named repository in turn, and refuses uploads. |
| `writable fallback https://repo1.maven.org/maven2/` | Accepts uploads *and* fetches misses from the upstream. |

A fallback may be another repository by name instead of a URL, and several fallbacks are tried in order. Each
can carry options:

| Option | Effect |
| --- | --- |
| `nocache` | Serve what the upstream returns without keeping it. |
| `harden` | Screen every fetched file in full before serving a byte of it. |
| `unscreened` | Skip the gate for this upstream - flagged as a warning on the Repositories page. |
| `match=<ecosystem>:<pattern>` | Only send matching coordinates to this fallback, such as `match=maven:com.example.*`. |

A container-image upstream may carry a path, which names the namespace its images are looked up in: a repository
`core` defined as `fallback https://ghcr.io/homebrew/core` serves ghcr.io's `homebrew/core/<name>` as `<name>`.

Routing is checked when it is saved: routing that could not work is refused with the reason, and routing that works
but is risky - a plaintext upstream, mixed screening - is saved and listed under **Definition warnings** on the
**Repositories** page.

Routing has no deployment-wide or tenant-wide default, since one would point every repository at the same upstream.
What the deployment can hold instead is a **definition** of a repository name, under **Settings → Upstreams →
Repository routing**, written the same way: it routes the repository of that name in every tenant, and a
repository's own routing wins over it. A definition can also be a startup setting, `repositories.<name>`.

## A discovered upstream

A module name or a Maven group ID is a reversed domain, and a domain can say where its modules and artifacts are
published: in a file at `https://<domain>/.well-known/java-repository.properties`, which the
[discovery chapter](/tool/discovery/) of the build tool describes. A repository routed `fallback discovered` fetches
each miss from where that file says, instead of from one upstream:

```
writable fallback discovered fallback https://repo1.maven.org/maven2/
```

serves what was published here, then what the domain of each name says, and then Maven Central for names whose
domain publishes no file. `discovered` takes the options an upstream URL takes, and works in a Maven repository and
in a `jenesis` module repository.

What a domain's file names is fetched, checked, screened and kept as any upstream's files are:

- **A file of a version** - a jar, a POM, a module's jar - is fetched from the location the file names and kept.
  Where the file names a template, the file it fills in is checked against the strongest `.sha512`, `.sha256` or
  `.sha1` published beside it, and a mismatch is neither kept nor served; under a root - a Maven repository or a
  module service - a file is fetched as from any upstream of that kind.
- **A module's own jar** must declare the module it is asked for, in its `module-info` or as its
  `Automatic-Module-Name`, or it is neither kept nor served, so a domain cannot answer for one module with another.
- **A version list** comes from a root itself, and for a template from what its latest link names - the versions a
  `maven-metadata.xml` lists, or the one version a redirect names. A module's latest pointer is served as the domain
  answers it now and never kept.
- **A version the file does not serve** - one before its `.since`, or with a qualifier its `.suffixes` leave out -
  and a name whose domain publishes no file are left to the next fallback.

Each domain's file is read once an hour on each node, and an absent file is remembered as absent for as long;
`discovery-ttl` changes the period. A file is only read over `https`, and only from a public address, as an
upstream is: a domain that resolves to a private, loopback or cloud-metadata address is not asked, and a file
naming such a location is refused, unless `proxy-allow-internal` permits it. A file that breaks the format's rules -
a key without a value, a location that is not `https` - fails the requests it would answer with `502` and is
logged, rather than being read as no file.

To see what a name's domains say now, and where a request path would go, a super-admin asks under **Operations →
Discovery**, or from the command line:

```bash
jenrepo discovery check build.jenesis --path /maven/build/jenesis/build.jenesis/0.15.5/build.jenesis-0.15.5.jar
```

## Private upstreams

An upstream that needs credentials gets them under **Settings → Upstreams → Upstream credentials**: the host name,
and a user name and password, a bearer token, or a header name and value - or, for Amazon ECR and CodeArtifact, a
token issued to the deployment's own AWS identity. The credential is sent to that host alone, whichever repository
fetches from it.

An upstream must be `https` on a public address: a plaintext URL, or one that resolves to a private, loopback or
cloud-metadata address, is refused unless `proxy-allow-internal` permits it - a fetch carries your credentials,
and an unscreened address would turn the proxy into a way into your own network.

## What happens on a miss

A request is always answered locally first. On a miss, the repository fetches from the upstream and:

- **checks it** - against the digest the upstream's own registry declares for it, where it declares one - and
  refuses a mismatch rather than keeping it;
- **screens it** through the same gate a publish passes, as described in [Screening what comes
  in](/repository/screening/);
- **keeps it**, so the next request is a local hit that never reaches the upstream.

The digests checked are the ones a registry advertises: an npm version's `integrity` or `shasum`, the `#sha256=` a
PyPI page links a file with, the checksum a Debian `Packages` index or an RPM repository's `primary.xml` lists, a
Helm chart's `digest`, the checksum database's hash of a Go module, an image layer's `sha256:` name, and their kind.
A fetched file that does not match is not kept, not served, and fetched again on the next request. A checksum the
*publisher* uploaded beside a file - a Maven or Ivy `.sha1`, a Conan `conanmanifest.txt` - is not one of them: it is
relayed as the upstream serves it, for the client to check, and the file is kept without it being read. A definite
`404` from upstream is remembered for a minute (`proxy-miss-ttl`), so a build probing for things that do not exist
does not flood the upstream.

A fetch that stalls is given up rather than held open: an upstream that delivers less than 16 KiB over any minute
spent waiting on it is abandoned, as one that goes silent is, while a large file on a slow but steady link still
lands. `proxy-throughput-floor` changes the floor, and `0` removes it.

Where an index names each artifact's download URL, the served copy points those URLs back at this repository, so
a client installs through it rather than straight from the upstream. A Helm chart repository is one: the
`index.yaml` is served with each version's `urls` rewritten to this repository's `charts/`, its `digest` unchanged,
and a chart fetched through it is checked against that digest.
An Ivy repository is proxied file by file, each file kept as the upstream serves it and its checksums relayed beside it.
A module's directory listing, which Ivy reads to resolve a revision such as `1.+`, is relayed as the upstream lists it.
An Alpine repository's `APKINDEX.tar.gz` is relayed as the upstream signed it, so clients keep trusting the
upstream's key. A package fetched through it is checked twice: its control member against the checksum the index
declares, and its data against the hash that control member carries.
A Swift registry proxies another organisation's registry, since there is no public one. Its release lists are
served without the upstream's release URLs, so a client resolves each release through this repository, and a
source archive is checked against the checksum in its release metadata.
A Terraform registry's provider package documents are served naming this repository's paths. The upstream's
signed `SHA256SUMS` and signing keys are passed on unchanged, so `terraform init` verifies the provider as it would
against the upstream, and the zip is checked against its `shasum` before it is kept. A module whose source is a
`.tar.gz` downloads through this repository. A module whose source is a git repository, as most public modules are,
is fetched through this repository when its host is listed in `terraform.git-hosts` - `github.com`, `gitlab.com`,
`bitbucket.org`, or another host written `host=kind` with its kind (`github`, `gitlab` or `bitbucket`), as in
`git.example.com=gitlab`. The ref's archive is fetched, kept and served, its digest recorded on the first fetch, so
a tag that later moves to other contents is refused. The list is empty by default; a git source on an unlisted
host, or one that names no single ref, is handed to the client to clone, or refused when
`terraform.git-refuse-unlisted` is `true`.

## Upstream documents

A document that changes upstream - a `maven-metadata.xml`, an npm package document, a PyPI Simple page, a Helm
`index.yaml`, a Go module's version list - is relayed rather than kept, and the server remembers it for six hours
(`cache.upstream-ttl`), so a burst of builds costs the upstream one fetch. A release published upstream can
therefore take that long to be listed here; `0` switches the memory off, and every read then fetches the document
afresh. The memory is per repository, so a document fetched with one repository's upstream credentials never
answers another, and it holds only what the upstream served - never an error or a refusal. It is bounded: a node
keeps at most 64 MiB of such documents, none larger than 1 MiB, and a larger one is relayed every time. **Clear
caches on this node**, under [Operations](/repository/operations/#caches), drops it at once.

Some documents vouch for each other, and are remembered only together. A Debian suite's `InRelease`, `Release` and
`Release.gpg` are fetched in one go and remembered as one when the upstream declares `Acquire-By-Hash`; every index
the remembered `Release` names is then fetched by its digest, so what apt is given agrees with the release it was
given, however the upstream has moved since. An RPM repository's `repomd.xml` is remembered with its signature and
key when every metadata file it names carries its checksum in its name, as `createrepo` names them by default; if one
of those files is gone upstream, the node forgets the family and fetches the current one. A suite or repository that
cannot be pinned this way is relayed fresh on every read. So is the RubyGems compact index: `/versions` names each
gem's `info` file by a digest no upstream address serves it by, so the two can only agree when read at one moment.

A Hugging Face branch is resolved to its commit, and that resolution is remembered for the same six hours, so a
burst of downloads from one branch costs the upstream one lookup, and a branch that moved resolves again once it is
forgotten. A container image's tag works the same way: a tag pushed to this repository answers as it stands, while a
tag relayed from the upstream answers as remembered and is asked of the upstream again once forgotten - or, if the
upstream cannot answer then, as it last stood.

## A repository that hosts and proxies

A repository routed `writable fallback …` - **host+proxy** on the Repositories page - serves what was published into
it and fetches the rest. Every read is answered locally first, so wherever both sides hold an answer to one request,
what was published here wins.

For a file a client asks for by its own address, both sides resolve: an image by digest, a Go module's `.zip`, a
version's jar, a raw file - what was published here is served, and anything else is fetched. A document a client
finds versions through is different, because the copy published here answers in place of the upstream's:

- **A document per name** - an npm package document, a PyPI project page, a Go module's version list, a Conan
  recipe's revisions - answers from this repository once that name has something published here, so the upstream's
  versions of that name are no longer listed. Other names still answer from the upstream. Clients that ask for a
  version by its address rather than through the list - Go, Conan, Maven, Ivy and Hugging Face - still resolve an
  upstream version they name exactly.
- **An index of everything** - a Helm `index.yaml`, a Conda subdirectory's `repodata.json`, an Alpine architecture's
  `APKINDEX.tar.gz`, an RPM repository's metadata - answers from what was published here once anything is, and lists
  none of the upstream's packages.
- **A container image's tag** is the exception: a tag pushed here answers as it stands, and any other tag is asked of
  the upstream, as described above.

A name published here therefore hides the upstream's releases of it from the clients that list versions. A
`maven-metadata.xml` can instead merge both sides into one list, which [Connecting your build
tools](/repository/formats/#maven-metadata-xml) describes.

## The cooldown on fresh versions

A version the upstream published **within the last two days** is held for review rather than served. A brand-new
release is the most likely moment for a compromised or malicious package, before anyone has noticed; two days lets
the feeds catch up. When it was published is what the upstream says in `Last-Modified`, so a file an upstream
serves without that header is not held. The hold is a quarantine, not a refusal: an editor can release it from **Quarantine**
at once. `immaturity-hold-days` changes the window, and `0` removes it.

<div class="note">
  <code>proxy-enabled</code> switches fetching off for the whole deployment while keeping every upstream you
  configured - useful for a deployment that must serve only what it already holds for a while.
</div>
