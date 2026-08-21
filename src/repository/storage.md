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

<div class="warning">
  A selected backend is never silently replaced. Naming a backend whose module is not on the path, or one
  that is missing a required setting, <strong>fails the boot</strong> with a message naming every missing
  key. Persisting against the wrong store is never the safe default.
</div>

## Filesystem - the default

The filesystem backend keeps objects under a root directory. It is the right choice for a single instance
or a local run, and it needs only a path:

```bash
JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

The root defaults to `/var/lib/jenesis-repository`. Point it at durable storage - a mounted volume, an NFS
share - and the server is complete. File permissions on the root are the only access control the backend
itself applies.

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

The GCS backend speaks Google's S3-compatible XML API with the GCS differences handled for you: the
compare-and-set token is the object **generation**, and uploads skip the chunked signing GCS does not decode.

```bash
JENREG_STORE=gcs
JENREG_GCS_BUCKET=my-artifacts
```

It authenticates with an HMAC key pair (Cloud Storage → Settings → Interoperability) in
`JENREG_GCS_ACCESS_KEY_ID` and `JENREG_GCS_SECRET_ACCESS_KEY`; when neither is set, the ambient AWS
credential chain is used. `JENREG_GCS_ENDPOINT` (default `https://storage.googleapis.com`) points the
backend at an emulator and must be `https` unless `JENREG_GCS_ALLOW_INSECURE_ENDPOINT=true`;
`JENREG_GCS_REGION` sets the signing region (default `auto`).

The plain `s3` backend pointed at `https://storage.googleapis.com` works as well. Pick the native backend
when you want generation-based compare-and-set rather than ETags.

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

The quota counts the bytes actually held: content blobs, plus the chunks of an OCI upload that is still in
progress. A deduplicated re-deploy of bytes already stored needs no new space and is never refused.

## Backing up and moving

Because the store is the server's only state, a backup is a copy of the store: the root directory on the
filesystem backend, or the bucket or container on a cloud backend, using whatever snapshot or sync tooling
you already run for that medium. Moving a repository between backends is a copy too - copy the objects
across with their keys unchanged, point `jenreg.store` and the backend's settings at the new medium, and
restart.

<div class="note">
  The credential objects the server reads for key authentication live under <code>auth/</code> at the store
  root, outside the <code>&lt;tenant&gt;/&lt;repository&gt;/</code> prefix. A backup of the whole root
  carries them; a copy of one repository prefix alone does not.
</div>

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.store` | `filesystem` | The backend: `filesystem`, `s3`, `gcs` or `azure-blob`. |
| `jenreg.filesystem.root` | `/var/lib/jenesis-repository` | Root directory of the filesystem backend. |
| `jenreg.s3.bucket` | *(required for `s3`)* | The bucket. |
| `jenreg.s3.region` | `us-east-1` | The signing region. |
| `jenreg.s3.endpoint` | *(AWS)* | An S3-compatible endpoint; enables path-style access. Must be `https`. |
| `jenreg.s3.access-key-id` / `jenreg.s3.secret-access-key` | *(AWS credential chain)* | Static keys; set both or neither. |
| `jenreg.s3.sse-kms-key-id` | *(SSE-S3)* | A KMS key for `aws:kms` server-side encryption. |
| `jenreg.s3.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.gcs.bucket` | *(required for `gcs`)* | The bucket. |
| `jenreg.gcs.access-key-id` / `jenreg.gcs.secret-access-key` | *(ambient chain)* | The HMAC pair; set both or neither. |
| `jenreg.gcs.endpoint` | `https://storage.googleapis.com` | An emulator endpoint. Must be `https`. |
| `jenreg.gcs.region` | `auto` | The signing region. |
| `jenreg.gcs.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.azure-blob.connection-string` | *(required for `azure-blob`)* | The storage-account connection string. |
| `jenreg.azure-blob.container` | `jenesis-repository` | The blob container. |
| `jenreg.azure-blob.allow-insecure-endpoint` | `false` | Permit a plain-http endpoint. |
| `jenreg.quota` | *(unset - no cap)* | Storage ceiling; a write over it answers `507`. |
| `jenreg.tenant` / `jenreg.repository` | `default` | The prefix every artifact is stored under. |

Every key is also an environment variable in upper case with underscores (`JENREG_S3_BUCKET`), a `-D`
system property, or an `application.properties` entry.
