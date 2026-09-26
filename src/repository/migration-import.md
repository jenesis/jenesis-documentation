---
order: 14
title: Migrating in and out
description: Bringing an existing repository's contents into Jenesis Repository - the Import page, the Nexus, Artifactory, Maven, index and Jenesis connectors, archive uploads - and moving everything out again, by listing it or by exporting it to another repository.
---

Most teams adopting Jenesis Repository already have artifacts somewhere else. This chapter shows how to move
them in, how to follow and resume the job, how to load an archive of files in one go, and how to take
everything back out when you leave - as a listing, or by exporting it straight into another repository.

## Starting an import

An import is a background job that walks another repository manager and publishes every artifact it finds
into this repository, through the same gate a client's upload passes. The repository is created first, with the
type of what you are bringing in (see [Repositories](/repository/repositories/)): an import into a repository that
holds no type is refused before it starts, and a repository holds one type, so an import lays out only the formats
it holds - a Nexus instance with Maven and Docker repositories is brought into a `maven` repository and an `oci`
one, one import each. Open the repository you are importing into and choose **Import**. Under **Start a
migration**:

| Field | Meaning |
| --- | --- |
| **Source** | The connector to walk with - Nexus, Artifactory, a Maven repository, a package index or another Jenesis Repository. |
| **Base URL** | The address of the source. It must be `https` and resolve to a public host (see below). |
| **Source repository** | The repository to read - a Nexus or Artifactory repository name, or the path under the base URL. |
| **Format** | For Artifactory and index sources, the ecosystem of the source repository. |
| **Username**, **Password / token** | Credentials sent to the source, if it needs them. |

**Start migration** answers at once, and **Migrations** below lists every job with how many artifacts it has
imported, skipped, held for review and rejected, refreshing while one runs. A job that stopped part-way offers
**Resume from cursor**, which continues from its last checkpoint rather than starting over; **Dismiss** removes a
finished job from the list, and finished jobs are dismissed on their own after seven days.

The same import can be started from a script with a `POST` to `/api/repository/import`, naming the repository in
`?repo=`, and a key that may write to the repository:

```bash
curl -X POST 'https://repo.example.com/api/repository/import?repo=libraries' \
  -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{
        "source": "nexus",
        "url": "https://nexus.example.com",
        "repository": "maven-releases",
        "username": "migrator",
        "password": "…"
      }'
# 202  {"job":"a1b2c3…","state":"running"}
```

The request fields, which match the form:

| Field | Required | Meaning |
|---|---|---|
| `source` | yes | The connector to walk with: `nexus`, `artifactory`, `maven`, `index` or `jenesis`. |
| `url` | yes | The base URL of the source. It must be `https` and resolve to a public host (see below). |
| `repository` | yes | The source repository to read - a Nexus or Artifactory repository name, or the path under the base URL. |
| `format` | Artifactory | The ecosystem of the source repository, as Artifactory names its package type: `maven`, `npm`, `pypi`, `nuget`, `docker`, `alpine`, `swift`, `terraform`, `raw` and the others this product serves. |
| `format` | index | The installed format whose own index is walked. The OCI format is the one that enumerates its index, so `oci` is the format to name; any other finds nothing to import. |
| `username`, `password` | no | Credentials sent to the source. The `jenesis` connector takes its API key as the `password`. |
| `resume` | no | The id of an earlier job. The walk continues under that same id, from its recorded position. |

The other connectors report a format per asset, so they take none. Only `POST` starts a job; any other
method on `/api/repository/import` answers `405`, and an import into a repository that holds no type answers `400`. A
deployment in read-only mode refuses imports with `403`.

<div class="warning">
  The import URL is screened before anything is fetched: it must be <code>https</code>, and it must not resolve
  to a private, loopback or link-local address. A migration carries your upstream credentials and is walked
  from inside the server, so an unscreened URL would hand those credentials to a plaintext hop, or turn the
  importer into a proxy for your own network. Set <code>jenreg.block-private-import-hosts=false</code> only for a
  controlled migration from an internal or plaintext mirror, and switch it back on afterwards. Running with it
  off raises the <code>jenreg.importer.ssrf</code> advisory.
</div>

## Following and resuming a job

The job writes its state into the store, so it survives a restart and any node can answer for it. Read it
with the id the `POST` returned:

```bash
curl -H "Jenesis-Repository-Key: $KEY" 'https://repo.example.com/api/repository/import/a1b2c3…?repo=libraries'
```

```json
{"state":"completed","imported":128,"skipped":0,"held":0,"rejected":0,
 "skippedFormats":[],"cursor":null,"asset":"maven/org/example/app/1.0/app-1.0.jar","error":null}
```

| Field | Meaning |
|---|---|
| `state` | `running`, `completed` or `failed`. |
| `imported`, `skipped`, `held`, `rejected` | Running counts. An asset is skipped when its format is not one the repository holds, when no installed importer handles its format, and when that format is switched off. |
| `skippedFormats` | The formats that were skipped, so you can see what the repository's type or a missing format module left behind. |
| `cursor` | The walk's last checkpoint, kept for a resume. `null` once the walk is finished. |
| `asset` | The last asset imported. |
| `error` | The failure message when `state` is `failed`. |

A job that stopped - a network fault, a restart - is continued by submitting the same request again with
`"resume": "<job id>"`. The walk resumes under that same job id, from its recorded cursor, carrying
`imported` and `skipped` forward; `held` and `rejected` restart at zero and count the resumed run alone.

The content-addressed store makes any overlap free: re-importing bytes that are already stored needs no
space and changes nothing, so a re-run after a partial migration is always safe.

## The connectors

Each connector reads one kind of source. All of them stream every artifact straight into the store, and all
but one checkpoint as they go: the Artifactory Pro deep listing arrives as a single response, so a job
walking it has no mid-walk resume point.

### Nexus

`nexus` pages the Sonatype Nexus 3 components API and downloads every asset a component lists. Nexus names
a format per asset (`maven2`, `docker`, `raw`, and others), so one job can migrate a Nexus instance that
holds repositories of several formats. The credentials you pass travel only to the base origin; a download
URL on another host is fetched without them.

### Artifactory

`artifactory` lists a repository with the storage API and downloads each file. An Artifactory repository has
a single package type, so the request must name its `format`. Against Artifactory Pro it uses the deep file
listing, which is one response and carries no resume point; against an OSS instance, which refuses that
API, it falls back to the per-folder listing and checkpoints after every top-level entry, folder or file,
so an interrupted OSS migration resumes without re-walking.

Each file is published through its format's own publish path, so it is read, screened and indexed as if a client
had published it. Indexes and other documents the format derives are skipped, since the import rebuilds them. Three
package types are read at the paths Artifactory documents for them:

| Package type | Source path | Imported as |
|---|---|---|
| `alpine` | `<branch>/<repository>/<architecture>/<package>.apk` | the package, in the apk repository named by `<repository>`. |
| `swift` | `<scope>/<name>/<name>-<version>.zip` | the release `<scope>.<name>` at `<version>`, published as a Swift client publishes it. |
| `terraform` | `<namespace>/<provider>/<version>/terraform-provider-<provider>_<version>_<os>_<arch>.zip` | the provider's zip for that platform, unchanged. |
| `terraform` | `<namespace>/<module>/<system>/<version>.zip` | the module version, repacked as the `.tar.gz` this registry serves every module as. The files are the same, and Terraform checks no checksum on a module. |

Alpine branches have no level of their own here. Packages from two branches of one repository and architecture
end up in one apk repository, and a version both branches hold with different bytes is refused as a republish.
The incumbent's `APKINDEX.tar.gz` and a provider's `SHA256SUMS` are signed with the incumbent's key, so they are
not carried over: this repository signs its own.

### Maven

`maven` walks any repository that serves the Maven layout over plain HTTP - a Nexus or Artifactory repository
root, an `nginx` or `httpd` directory listing, a static bucket, or another Jenesis Repository. Where the
server exposes a listing, the tree is walked; where it does not, the connector falls back to the
`.index/nexus-maven-repository-index.gz` index and refreshes each coordinate through its `maven-metadata.xml`.
Every asset is reported as `maven`.

### Index

`index` walks a format's own published index rather than a vendor API, which is why it needs the `format`
up front. It migrates whatever the installed format can enumerate from the source.

### Jenesis

`jenesis` walks another Jenesis Repository through its `/api/assets` listing (below), so one instance
migrates into another. `repository` names the source repository, and the credential is the source's API key,
passed as the `password`. Each asset is downloaded from the path the listing says the source serves it at, so
nothing about the source's layout needs configuring.

## What the importers write

A connector hands each asset to the importer for its format. Every format except Ivy and the Jenesis module layout
carries one, and each accepts the names Nexus and Artifactory give that format as well as its own - `yum` for RPM,
`apt` for Debian, `alpine` for apk, `golang`, `gems`, `crates`, `huggingfaceml` - and publishes each asset through
the format's own publish path. Three are worth knowing in detail:

| Importer | Accepts source formats | Writes |
|---|---|---|
| Maven | `maven`, `maven2` | The artifact at its Maven path. A jar that carries a module name is cross-published into the module layout, exactly as a normal Maven publish is, which a `java` repository serves. |
| OCI / Docker | `oci`, `docker` | Layers, configs and manifests into the content-addressed store, where they dedupe against everything else. |
| Raw | `raw`, `generic` | The file at its path under the raw layout. |

Two Maven details matter before you cut clients over. The source's `maven-metadata.xml` files are always
left behind - their checksums describe bytes the source served, not the copy you now hold. Jenesis Repository
serves a stored `maven-metadata.xml` verbatim, so an imported coordinate has no version listing until one is
published, and a client asking "which versions exist?" gets a `404`. Switch on
`jenreg.maven-metadata-compute=true` and the server derives the listing from the version folders it holds
instead. The `maven` connector also skips checksum sidecars (`.sha1`, `.md5`), and the server does not derive
them, so a client that verifies checksums warns until one is published beside the artifact. The Nexus and
Artifactory connectors import the sidecars they list.

When a job finishes, the server builds the listings the imported artifacts imply - an OCI repository's tag
list and catalogue, a raw folder's listing - before it reports `completed`, and regenerates ones that
already existed, so a client pointed at the new repository sees a correct listing on its first read. A
listing that cannot be built is a slow first read, never a failed migration.

## Loading an archive in one request

For a one-off load without a source to walk - a backup, a hand-built tree - upload a zip and let the server
publish each entry as if it had been deployed on its own. The feature is off by default; switch it on with
`jenreg.batch-upload=true`, then `PUT` or `POST` the archive to the repository path the entries are relative
to, with the `Jenesis-Explode: zip` header:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/releases/libraries/maven/ \
  -H 'Jenesis-Explode: zip' \
  --data-binary @artifacts.zip
```

Every entry is published through the same path a single deploy takes, so a Maven jar is laid out and
cross-published, and an entry no format claims is reported rather than stored. The response is a per-entry
manifest (`path` and `status` - `stored`, `quarantined`, `rejected` or `unclaimed`), with `"capped": true`
when the walk stopped at `jenreg.batch-upload-max-entries` (default 10 000). An entry whose name tries to
escape its folder is rejected before it reaches the store, and a malformed archive answers `400`. Only `zip`
is understood; another encoding answers `415`.

## Listing everything back out

Leaving is as easy as arriving. `GET /api/assets?repo=<repository>` lists every published artifact in a
repository as a flat, stably ordered, paged JSON list - the same listing the `jenesis` connector reads when
another instance imports from this one:

```bash
curl -H "Jenesis-Repository-Key: $KEY" 'https://repo.example.com/api/assets?repo=libraries&limit=500'
```

```json
{"repository":"libraries",
 "assets":[{"path":"/maven/org/example/app/1.0/app-1.0.jar",
            "served":"/repository/releases/libraries/maven/org/example/app/1.0/app-1.0.jar",
            "size":48213,"sha256":"9f3b…",
            "format":"maven","ecosystem":"Maven","coordinate":"org.example:app","version":"1.0",
            "prerelease":false}],
 "cursor":"bWF2ZW4v…"}
```

Each entry carries the path, size and SHA-256 straight from the publication record - no artifact is opened -
plus `served`, the URL path a client downloads it from, and the format's reading of it: `format`, `ecosystem`,
`coordinate`, `version` and `prerelease`. Pass the returned `cursor` back as `?cursor=` for the next page; it is
`null` once the listing is exhausted. `repo` is required and names a repository of the tenant the server serves;
`limit` defaults to 500 and is capped at 1 000. The read needs `repository:read` on the repository it lists.

The bytes themselves are addressed by the `served` paths the listing returns, so any HTTP client can copy a
repository out - and another Jenesis Repository imports one directly with the `jenesis` connector above.

## Moving to another repository

An export publishes every version a repository holds into another repository - another Jenesis Repository, or any
repository manager - through the protocol the format's own client publishes with, so the other side needs no
importer and sees nothing it would not see from a client. It is a background job, like an import.

Choose **Export** in the console. Name the repository to export, the **Target URL** - the URL the format's own
client would be pointed at to publish into the other repository - and a credential for it: a **Username** with a
**Password**, or a **Token**. **Start export** answers at once, and the list below shows each job's state, how many
versions it published, how many the target already held and how many it withheld, refreshing while one runs.

The same job starts from a script with a `POST` to `/api/repository/export`, naming the repository in `?repo=`:

```bash
curl -X POST 'https://repo.example.com/api/repository/export?repo=libraries' \
  -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"url": "https://other.example.com/repository/maven-releases/", "token": "…"}'
# 202  {"job":"d4e5f6…","state":"running"}

curl -H "Jenesis-Repository-Key: $KEY" \
  'https://repo.example.com/api/repository/export/d4e5f6…?repo=libraries'
# {"state":"completed","published":412,"present":0,"withheld":3,…}
```

and from the command line, where `--refresh` follows the job until it finishes:

```bash
jenesis-repo export libraries --url https://other.example.com/repository/maven-releases/ --token "$TOKEN"
jenesis-repo export status libraries d4e5f6… --refresh
```

| Field | Required | Meaning |
|---|---|---|
| `url` | yes | Where the format's client would be pointed to publish into the target. It must be `https` and resolve to a public host, under the same setting as an import's URL. |
| `username`, `password` | no | Sent as HTTP Basic. |
| `token` | no | Sent as a bearer token, or in the header the format's client uses (`X-NuGet-ApiKey` for NuGet, a bare `Authorization` for Cargo and RubyGems). |
| `resume` | no | The id of an earlier job, which continues from where it stopped. The credential is never stored, so it is named again. |

What an export sends, per format, relative to the target URL:

| Format | Sent as |
|---|---|
| Maven, Ivy, Jenesis, raw | Each file of a version `PUT` at its path, artifacts before signatures, checksums and metadata. |
| npm | The version's `PUT` to the package, with its tarball attached, as `npm publish` sends it. |
| PyPI | The legacy upload form `POST`ed to the URL, as `twine upload` sends it. |
| NuGet | The `.nupkg` `PUT` to `v3/package`, as `dotnet nuget push` sends it. |
| Cargo | The publish frame `PUT` to `api/v1/crates/new`, as `cargo publish` sends it. |
| RubyGems | The `.gem` `POST`ed to `api/v1/gems`, as `gem push` sends it. |
| OCI | Each blob, then the manifest by tag, through the registry API, as `docker push` sends them. |
| Swift | The release `PUT` as a form, with its metadata, manifest and signature. |
| Conan | Each recipe and package file of every revision, under the revision the client computed. |
| Helm | The chart `PUT` under `charts/`, its provenance file after it. |
| Go, conda, Debian, RPM, apk, Composer, CocoaPods, Terraform, Homebrew, Hugging Face, winget | Each file `PUT` at the path this format publishes it to; winget's manifest goes before its installers. |

Before sending a file the export asks the target whether it already holds it, and a file the target serves with the
same bytes is not sent again - so a job can be run twice, or resumed, and a repository already partly moved is
completed rather than duplicated. A target that refuses a file it already holds with the same bytes - a release
repository refusing a second deploy - is not a failure. A version the gate is holding is never sent. Finished
export jobs are removed after seven days.

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.block-private-import-hosts` | `true` | Refuse an import or export URL that is not `https` or that resolves to a private, loopback or link-local address. |
| `jenreg.import-job-ttl` | `P7D` | How long a finished import job stays before the scheduled cleanup removes it. |
| `jenreg.export-job-ttl` | `P7D` | How long a finished export job stays before the scheduled cleanup removes it. |
| `jenreg.batch-upload` | `false` | Honour the `Jenesis-Explode` header and publish an archive entry by entry. |
| `jenreg.batch-upload-max-entries` | `10000` | The most entries one exploded archive may publish; the walk stops there and reports `capped`. |
| `jenreg.maven-metadata-compute` | `false` | Derive `maven-metadata.xml` from the stored version folders instead of serving only what was published. |

Every key is also an environment variable (`JENREG_BATCH_UPLOAD=true`) or a `-D` system property.
