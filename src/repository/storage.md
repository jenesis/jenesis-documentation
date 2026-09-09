---
order: 4
title: Storage
description: Where your artifacts live - the filesystem, S3-compatible, Google Cloud Storage and Azure Blob backends, how to select one, the storage quota, and how to back a repository up.
---

Jenesis Repository keeps everything it owns in **one store**. A jar, a Docker layer, a checksum, a
`maven-metadata.xml`, the pointer that says which blob a path serves - all of it is an object in that store,
and there is no database beside it. This chapter is about choosing where that store lives: a directory on
disk, an S3-compatible bucket, Google Cloud Storage, or Azure Blob.

## One store, four backends

The store is content-addressed and streamed. An upload is digested as it is written and lands under
`blobs/<sha256>`, so identical bytes are stored once - a re-deploy of unchanged content costs no space, and
a Docker layer dedupes against a jar with the same bytes. Bytes move from the network straight to storage
and back without being held whole in memory, so a 4 KB POM and a 4 GB image layer cost the same fixed heap.
Pointers are written with compare-and-set, which is how several server instances can share one bucket
without a lock service.

Every artifact lives under a `<tenant>/<repository>/…` prefix. Both names default to `default`, so a fresh
server writes under `default/default/`. You never edit objects under the root by hand.

A backend is a discovered module, chosen **once, at startup, for the whole deployment**. You select it with
`jenreg.store` (environment variable `JENREG_STORE`); leaving it unset uses the filesystem.

| `jenreg.store` | Backend | Required setting |
|---|---|---|
| *(unset)* or `filesystem` | A directory on disk *(default)* | `jenreg.filesystem.root` |
| `s3` | AWS S3 or any S3-compatible store (MinIO, Ceph, LocalStack) | `jenreg.s3.bucket` |
| `gcs` | Google Cloud Storage | `jenreg.gcs.bucket` |
| `azure-blob` | Azure Blob Storage | `jenreg.azure-blob.connection-string` |

What each request costs a store that charges per operation is the subject of
[What it costs to run](/repository/cost/).

<div class="warning">
  A selected backend is never silently replaced. Naming a backend whose module is not on the path, or one
  that is missing a required setting, <strong>fails the boot</strong> with a message naming every missing
  key - and so does a backend you did not select but configured in full, such as
  <code>JENREG_S3_BUCKET</code> set while <code>filesystem</code> is selected, because a deployment has
  exactly one store. Persisting against the wrong store is never the safe default.
</div>

Every object-store backend also probes its endpoint at boot: four writes of one small key of the server's
own, checking that the service honours the write preconditions compare-and-set is built on. An endpoint
that ignores them - some S3-compatible services do - is refused with the reason named, because several
nodes over such a store would silently overwrite each other. `jenreg.<backend>.conditional-write-probe=false`
skips the probe, and the server warns at every start that it did.

## Filesystem - the default

The filesystem backend keeps objects under a root directory. It is the right choice for a local run, for a
single instance, and for several instances over one shared mount - see the note below - and it needs only a path:

```bash
JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

The root is required: without `jenreg.filesystem.root` the server refuses to start and names the key, rather than inventing a folder that vanishes with a container. Point it at durable storage - a mounted volume, an NFS
share - and the server is complete. File permissions on the root are the only access control the backend
itself applies.

**Several nodes may share one mount.** The compare-and-set that every multi-node mechanism rests on is exclusive
across processes as well as threads: a writer holds an operating-system lock on one of sixty-four stripe files
under the root, from the comparison to the move, and the stripe comes from the key relative to the root rather
than from the absolute path - so two nodes mounting one share at different paths meet on the same lock. Before
that lock existed, two JVMs making three thousand compare-and-set increments to one key over one directory came
up short, and two nodes publishing versions of one Go module dropped one from the module's list; both now hold.

Two conditions apply, and both are about the mount rather than the server. The lock is advisory, so **an export
that does not honour file locks - NFS without its lock daemon - must not be shared**: writes will appear to
succeed and overwrite one another silently. And availability is the file system's own: a shared directory is a
single point of failure unless whatever serves it is not. The backend gives consistency across nodes and says
nothing about what happens when the mount goes away.

## S3 - AWS, MinIO, Ceph

The S3 backend stores every object in a bucket, which makes the server **stateless**: an instance can die
and lose nothing, and you can run several behind a load balancer. Select it and name the bucket:

```bash
JENREG_STORE=s3
JENREG_S3_BUCKET=my-artifacts
JENREG_S3_REGION=eu-central-1          # default us-east-1
```

Credentials come from the standard AWS chain - environment variables, a shared profile, an instance or task
role - so a server on AWS usually needs no keys in its configuration. To supply keys explicitly, the path a
self-hosted MinIO or Ceph takes, set both `JENREG_S3_ACCESS_KEY_ID` and `JENREG_S3_SECRET_ACCESS_KEY`.

An S3-compatible store is reached through an endpoint, which switches the client to path-style access:

```bash
JENREG_S3_ENDPOINT=https://minio.internal:9000
```

The endpoint must be `https`. A plain-http endpoint - a MinIO on a laptop, say - is refused at boot unless
you opt in with `JENREG_S3_ALLOW_INSECURE_ENDPOINT=true`, because credentials and artifact bytes would
otherwise cross the network unencrypted.

Objects are written with server-side encryption: SSE-S3 by default, or `aws:kms` when
`JENREG_S3_SSE_KMS_KEY_ID` names a key. The object ETag is the compare-and-set token, so several instances
coordinate through the bucket alone. Because S3 needs an object's length up front, a streamed upload of
unknown length is spilled to a temporary file rather than to the heap.

## Google Cloud Storage

The GCS backend speaks Google's own JSON API, and its compare-and-set token is the object **generation**.

```bash
JENREG_STORE=gcs
JENREG_GCS_BUCKET=my-artifacts
```

It authenticates the way Google's clients do. A service-account key file named in `JENREG_GCS_CREDENTIALS`
is used when set; otherwise the backend takes Application Default Credentials - `GOOGLE_APPLICATION_CREDENTIALS`,
a `gcloud` login, or the metadata server - so a node on Compute Engine, GKE or Cloud Run runs without a key
under Workload Identity. `JENREG_GCS_PROJECT` lets the backend create the bucket on first use; without it
the bucket must exist. `JENREG_GCS_ENDPOINT` points the backend at an emulator and must be `https` unless
`JENREG_GCS_ALLOW_INSECURE_ENDPOINT=true`; `JENREG_GCS_CREDENTIALS=none` is for an emulator that
authenticates nobody.

## Azure Blob

The Azure backend stores objects in a blob container and behaves like the S3 backend for scaling and
coordination, with the blob ETag as the compare-and-set token:

```bash
JENREG_STORE=azure-blob
JENREG_AZURE_BLOB_CONNECTION_STRING='DefaultEndpointsProtocol=https;AccountName=…'
JENREG_AZURE_BLOB_CONTAINER=artifacts   # default jenesis-repository
```

The endpoint the connection string resolves to must be `https`; a plain-http one (an Azurite emulator)
needs `JENREG_AZURE_BLOB_ALLOW_INSECURE_ENDPOINT=true`.

## Capping storage

A repository-wide storage cap is optional. Once stored content reaches the limit, a new artifact is refused
with `507 Insufficient Storage`:

```bash
JENREG_QUOTA=10G       # a byte count, or a K/M/G/T suffix (1024-based)
```

The quota counts the bytes held: content blobs, plus the chunks of an OCI upload that is still in
progress. A deduplicated re-deploy of bytes already stored needs no new space and is never refused.

## Reclaiming space

Content is stored once and addressed by its hash, so deleting a version removes the pointer that named it and
leaves the bytes: another version may name the same bytes. What frees them is a collector, which marks every
blob a live pointer references and sweeps the rest. It rides the rebuild walk the server already runs
(`jenreg.rebuild.interval`, weekly by default), so reclaiming costs no enumeration of its own.

Deletion is the one act that cannot be undone, so the collector is deliberately slow to it. A blob is
**condemned** on one pass and deleted on the next, and a pointer that links it in between clears the mark, so a
blob has to be unreferenced across two whole passes before it goes. `jenreg.gc.grace` adds a wall-clock floor on
top of that when several nodes collect, and only ever delays a deletion.

| Key | Default | Effect |
|---|---|---|
| `jenreg.gc` | `mark-sweep` | The collector, by name. A name nothing answers to fails the boot rather than quietly reclaiming nothing. |
| `jenreg.collect` | `true` | Switch off the walk pass that runs the collector; the store then only grows. |
| `jenreg.gc.stride` | `20000` | Items the collector's own pass handles between checkpoints - the reference batch it holds, the re-work a crash costs, and how often it renews a segment claim. |
| `jenreg.gc.grace` | `PT0S` | A wall-clock floor on the condemned-to-deleted gap, on top of the two-pass rule. |

Three signals report it once a collection has run: `jenreg.gc.condemned` (blobs marked and awaiting the
confirming pass), `jenreg.gc.collected` (blobs reclaimed so far) and the `jenreg.gc.lastrun` task status. A
deployment with no collector contributes none of them, which the capability surface reports rather than leaving
as a silent zero.

<div class="tip">
  <strong>On a versioned bucket, none of this frees any space</strong>, and the signals above will not tell you so:
  they count what the collector did, which is not what the bucket kept. An ordinary delete against a bucket with
  versioning - or GCS soft delete, or Azure blob soft delete - leaves the prior version in place and still billed.
  That is the correct behaviour: versioning is a safety net you enabled, and reaching past it with versioned deletes
  would destroy the protection you are paying for. Freeing the bytes is the bucket owner's half of the job, through a
  noncurrent-version expiration rule. See
  <a href="/repository/cost/">What it costs to run</a> for what to check on each provider.
</div>

## Backing up and moving

Because the store is the server's only state, a backup is a copy of the store: the root directory on the
filesystem backend, or the bucket or container on a cloud backend, using whatever snapshot or sync tooling
you already run for that medium. Moving a repository between backends is a copy too - copy the objects
across with their keys unchanged, point `jenreg.store` and the backend's settings at the new medium, and
restart.

<div class="note">
  The server's own records - the credentials it authenticates keys against, its settings, its locks and
  node markers - live under <code>.system/</code> at the store root, outside the
  <code>&lt;tenant&gt;/&lt;repository&gt;/</code> prefix. A backup of the whole root carries them; a copy of
  one repository prefix alone does not.
</div>

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.store` | `filesystem` | The backend: `filesystem`, `s3`, `gcs` or `azure-blob`. |
| `jenreg.filesystem.root` | *(required for `filesystem`)* | Root directory of the filesystem backend; the server refuses to start without one. |
| `jenreg.s3.bucket` | *(required for `s3`)* | The bucket. |
| `jenreg.s3.region` | `us-east-1` | The signing region. |
| `jenreg.s3.endpoint` | *(AWS)* | An S3-compatible endpoint; enables path-style access. Must be `https`. |
| `jenreg.s3.access-key-id` / `jenreg.s3.secret-access-key` | *(AWS credential chain)* | Static keys; set both or neither. |
| `jenreg.s3.sse-kms-key-id` | *(SSE-S3)* | A KMS key for `aws:kms` server-side encryption. |
| `jenreg.s3.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.gcs.bucket` | *(required for `gcs`)* | The bucket. |
| `jenreg.gcs.credentials` | *(Application Default Credentials)* | A service-account key file, or `none` for an emulator. |
| `jenreg.gcs.project` | *(unset - the bucket must exist)* | The project the bucket is created in on first use. |
| `jenreg.gcs.endpoint` | *(Google)* | An emulator endpoint. Must be `https`. |
| `jenreg.gcs.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.azure-blob.connection-string` | *(required for `azure-blob`)* | The storage-account connection string. |
| `jenreg.azure-blob.container` | `jenesis-repository` | The blob container. |
| `jenreg.azure-blob.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.s3.conditional-write-probe` / `jenreg.gcs.conditional-write-probe` / `jenreg.azure-blob.conditional-write-probe` | `true` | Probe at boot that the endpoint honours write preconditions, and refuse to start when it does not; `false` skips the probe and warns at every start. |
| `jenreg.s3.streaming-writes` / `jenreg.gcs.streaming-writes` / `jenreg.azure-blob.streaming-writes` | `true` | Stream a compare-and-set body to the store; `false` buffers it in heap first, for an endpoint that cannot take a streamed one. |
| `jenreg.quota` | *(unset - no cap)* | Storage ceiling; a write over it answers `507`. |
| `jenreg.tenant` / `jenreg.repository` | `default` | The prefix every artifact is stored under. |

Every key is also an environment variable in upper case with underscores (`JENREG_S3_BUCKET`), a `-D`
system property, or an `allinone.properties` entry.
