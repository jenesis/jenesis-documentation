---
order: 9
title: Migration & import
description: Bringing an existing repository's contents into Jenesis Repository - the import job, the Nexus, Artifactory, Maven, index and Jenesis connectors, archive uploads, and listing everything back out again.
---

Most teams adopting Jenesis Repository already have artifacts somewhere else. This chapter shows how to move
them in with one request, how to follow and resume the job, how to load an archive of files in one go, and
how to list everything back out when you leave.

## Starting an import

An import is a background job. You `POST` a small JSON body to `/repository/admin/import`, the server answers
at once with a job id, and the job walks the source and publishes every artifact it finds into this
repository. The walk runs server-side through the same upstream fetcher that pull-through proxying uses, so
the upstream fetcher module must be installed - without it the request is refused with `501`.

```bash
curl -X POST http://localhost:8080/repository/admin/import \
  -H 'Content-Type: application/json' \
  -d '{
        "source": "nexus",
        "url": "https://nexus.example.com",
        "repository": "maven-releases",
        "username": "migrator",
        "password": "…"
      }'
# 202  {"job":"a1b2c3…","state":"running"}
```

On a deployment that enforces authentication, add the `Jenesis-Repository-Key` header with a key that may
write to the target repository. With authentication switched off, no header is needed.

The request fields:

| Field | Required | Meaning |
|---|---|---|
| `source` | yes | The connector to walk with: `nexus`, `artifactory`, `maven`, `index` or `jenesis`. |
| `url` | yes | The base URL of the source. It must be `https` and resolve to a public host (see below). |
| `repository` | yes | The source repository to read - a Nexus or Artifactory repository name, or the path under the base URL. |
| `format` | Artifactory and index | The ecosystem of the source repository: `maven`, `docker` or `raw`. The other connectors report a format per asset. |
| `username`, `password` | no | Credentials sent to the source. The `jenesis` connector takes its API key as the `password`. |
| `resume` | no | The id of an earlier job; the new job continues from that job's recorded position and counts. |

Only `POST` starts a job; any other method on `/repository/admin/import` answers `405`. A deployment in
read-only mode refuses imports with `403`.

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
curl http://localhost:8080/repository/admin/import/a1b2c3…
```

```json
{"state":"completed","imported":128,"skipped":0,"held":0,"rejected":0,
 "skippedFormats":[],"cursor":null,"asset":"maven/org/example/app/1.0/app-1.0.jar","error":null}
```

| Field | Meaning |
|---|---|
| `state` | `running`, `completed` or `failed`. |
| `imported`, `skipped`, `held`, `rejected` | Running counts. An asset is skipped when no installed importer handles its format. |
| `skippedFormats` | The formats that were skipped, so you can see what a missing format module cost you. |
| `cursor` | The walk's last checkpoint, kept for a resume. `null` once the walk is finished. |
| `asset` | The last asset imported. |
| `error` | The failure message when `state` is `failed`. |

A job that stopped - a network fault, a restart - is continued by submitting the same request again with
`"resume": "<job id>"`. The new job picks up the recorded cursor and counts, and the content-addressed store
makes any overlap free: re-importing bytes that are already stored needs no space and changes nothing, so a
re-run after a partial migration is always safe.

## The connectors

Each connector reads one kind of source. All of them stream every artifact straight into the store, and
all of them checkpoint as they go.

### Nexus

`nexus` pages the Sonatype Nexus 3 components API and downloads every asset a component lists. Nexus names
a format per asset (`maven2`, `docker`, `raw`, and others), so one job can migrate a Nexus instance that
holds repositories of several formats. The credentials you pass travel only to the base origin; a download
URL on another host is fetched without them.

### Artifactory

`artifactory` lists a repository with the storage API and downloads each file. An Artifactory repository has
a single package type, so the request must name its `format`. Against Artifactory Pro it uses the deep file
listing; against an OSS instance, which refuses that API, it falls back to the per-folder listing and
checkpoints after every top-level folder, so an interrupted OSS migration resumes without re-walking.

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
migrates into another. Its credential is the source's API key, passed as the `password`.

## What the importers write

A connector hands each asset to the importer for its format. Three ship with the server:

| Importer | Accepts source formats | Writes |
|---|---|---|
| Maven | `maven`, `maven2` | The artifact at its Maven path. A jar that carries a module name is cross-published into the module layout, exactly as a normal Maven publish is. |
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

## Loading an archive in one request

For a one-off load without a source to walk - a backup, a hand-built tree - upload a zip and let the server
publish each entry as if it had been deployed on its own. The feature is off by default; switch it on with
`jenreg.batch-upload=true`, then `PUT` or `POST` the archive to the repository path the entries are relative
to, with the `X-Jenesis-Explode: zip` header:

```bash
curl -X PUT http://localhost:8080/repository/maven/ \
  -H 'X-Jenesis-Explode: zip' \
  --data-binary @artifacts.zip
```

Every entry is published through the same path a single deploy takes, so a Maven jar is laid out and
cross-published, and an entry no format claims is reported rather than stored. The response is a per-entry
manifest (`path` and `status` - `stored`, `quarantined`, `rejected` or `unclaimed`), with `"capped": true`
when the walk stopped at `jenreg.batch-upload-max-entries` (default 10 000). An entry whose name tries to
escape its folder is rejected before it reaches the store, and a malformed archive answers `400`. Only `zip`
is understood; another encoding answers `415`.

## Listing everything back out

Leaving is as easy as arriving. `GET /api/assets` lists every published artifact in a repository as a flat,
stably ordered, paged JSON list - the same listing the `jenesis` connector reads when another instance
imports from this one:

```bash
curl 'http://localhost:8080/api/assets?limit=500'
```

```json
{"repository":"default",
 "assets":[{"path":"maven/org/example/app/1.0/app-1.0.jar","size":48213,"sha256":"9f3b…",
            "format":"maven","ecosystem":"Maven","coordinate":"org.example:app","version":"1.0",
            "prerelease":false}],
 "cursor":"bWF2ZW4v…"}
```

Each entry carries the request path, size and SHA-256 straight from the publication record - no artifact is
opened - plus the format's reading of it: `format`, `ecosystem`, `coordinate`, `version` and `prerelease`.
Pass the returned `cursor` back as `?cursor=` for the next page; it is `null` once the listing is exhausted.
`limit` defaults to 500 and is capped at 1 000, and `repo` names another repository than the one the
request routed to. The read needs `repository:read` on the repository it lists.

The web console offers the same walk as a download (`assets.ndjson`, one object per line with `path`,
`size` and `sha256`), described in [The console](/repository/console/). The bytes themselves are addressed by
the paths the listing returns, so any HTTP client can copy a repository out.

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.block-private-import-hosts` | `true` | Refuse an import URL that is not `https` or that resolves to a private, loopback or link-local address. |
| `jenreg.batch-upload` | `false` | Honour the `X-Jenesis-Explode` header and publish an archive entry by entry. |
| `jenreg.batch-upload-max-entries` | `10000` | The most entries one exploded archive may publish; the walk stops there and reports `capped`. |
| `jenreg.maven-metadata-compute` | `false` | Derive `maven-metadata.xml` from the stored version folders instead of serving only what was published. |

Every key is also an environment variable (`JENREG_BATCH_UPLOAD=true`) or a `-D` system property.
