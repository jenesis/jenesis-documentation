---
order: 3
title: Architecture
description: The plugin model, the content-addressed store every module writes through, and the path an upload takes from bytes to a served artifact.
---

*[Getting started](/repository/getting-started/)* got a server running and moving artifacts. This chapter
explains the shape underneath it in three ideas: a small core that discovers **plugins** at startup, one
**content-addressed store** they all persist through, and a single **publication path** every upload follows.
Each later chapter is one of those plugins in detail; this is the map.

## Everything is a module

Jenesis Repository has almost no fixed behaviour of its own. Each capability - a package format, a storage
backend, an import connector, the upstream fetcher, the rate limiter - is a **Java module on the server's
module path**. At startup the server looks at what is there and uses exactly that. It never names a format or
a backend itself, so there is no central table to edit and nothing to fork when you want less or more.

Three kinds of module do most of the work:

- A **format** speaks one client ecosystem's protocol. It recognises the request paths it owns and serves or
  accepts them. The Maven layout, the Jenesis module layout, the OCI/Docker registry and the raw layout are
  the four that ship.
- A **storage backend** turns the store's small set of operations into calls against a real medium - a
  directory, an S3-compatible bucket, Google Cloud Storage or Azure Blob.
- An **import connector** reads an existing repository - Nexus, Artifactory, a plain Maven repository or
  another Jenesis Repository - so its contents can be copied in.

You do not write any of these to run a repository; the built-ins come in the box. What matters is that the
set is **discoverable and switchable**. Module names follow the kind they plug in - a format is
`build.jenesis.repository.format.<name>`, a backend `build.jenesis.repository.store.<name>` - so the list of
modules on a deployment's path reads as the list of what it can do.

The name in the module and the name you configure with usually match. The Azure backend is the exception:
the module is `build.jenesis.repository.store.azure`, and you select it as `jenreg.store=azure-blob`.

### Switching a capability off

A module on the path is on until you configure it off. `jenreg.<name>=false` - `JENREG_MAVEN=false`,
`JENREG_OCI=false` - disables a capability exactly as if its module were missing. Where only one
implementation can apply at a time, `jenreg.<kind>=<name>` selects it: `JENREG_STORE=s3` picks the S3
backend, and the filesystem is what you get when you select nothing.

In a Jenesis build you can also build a narrower server by selecting modules, for example one that carries
only the S3 backend and what it depends on:

```bash
java build/jenesis/Project.java +source+store+s3
```

A server with **no format at all** is still a valid repository: every request is answered `404` until a
format that handles it is on the path.

<div class="note">
  The two rules to remember: a selected implementation that is not installed is a failed start, never a
  silent fallback; and an optional capability that is absent is simply not there, with the rest of the server
  unaffected. The chapters on storage and proxying show both in practice.
</div>

## The store underneath it all

Every module persists through **one store**, and the store is the **only durable state** - there is no
database. A blob, a checksum, an index, a pointer from a path to a blob, a settings document: all of them are
objects written through the same storage operations, so the same server runs unchanged on a disk or in a
bucket.

Two properties of the store shape everything above it:

- **Content addressing.** Bytes are stored under their own SHA-256 hash, at `blobs/<sha256>`. Identical
  bytes are stored once, so a re-deploy of unchanged content costs no space, and an OCI layer - whose digest
  already *is* a `sha256:` - dedupes against everything else for free.
- **Streaming.** An artifact moves from the network into the store and back out without ever being held
  whole. A 4 KB POM and a 4 GB image layer cost the same fixed heap.

A third property matters once you run more than one server: the store supports **compare-and-set** writes,
so several stateless instances agree on a pointer through the store itself, with no lock service. Every
object lives under a `<tenant>/<repository>/…` scope, both `default` unless you configure otherwise, which is
why a fresh deployment writes under `default/default/`. *Storage* covers the backends and their settings.

## The publication path

The one flow worth learning in full is what happens when an upload commits, because every later chapter
hangs something off it. An accepted publish takes four steps, in order:

1. **The blob is stored first.** The request body streams through the digest into `blobs/<sha256>`. The bytes
   now exist, but nothing points at them yet - the artifact is not visible under any path.
2. **It is screened.** A chain of publication screens may inspect the upload and return a verdict: accept,
   quarantine, or reject.
3. **The pointer is linked.** On accept, a pointer links the request path to the stored blob. *Now* the
   artifact is served. A quarantined or rejected publish never gets this link, so its bytes are never served.
4. **Observers are notified.** Once the artifact is linked, observer modules learn about it - the hook a
   webhook or a replication feed would ride. An observer has no say in the verdict, and its failure is logged
   and contained. Removal is symmetric: when a version is deleted, the same observers are told.

Screens and observers are plugins, and **no screen ships**: out of the box every upload is accepted and
served exactly as it arrives, and a deployment that wants publishes screened adds a module at that point.
Observers do ship: the Maven, OCI and raw formats each install one, and they are the listing maintainers
described next. A deployment that wants a publish announced elsewhere adds its own beside them.

### Listings are written, not computed

A repository answers many more reads than writes, so the work of keeping a listing current is done by the
write that changes it. An OCI `tags/list` or `_catalog`, a computed `maven-metadata.xml`: each is a
**stored document** under `listing/` that the server streams to a client as it is. When a tag is pushed, the
image's tag list is rewritten with the one new entry and the catalog with the one image; when a manifest is
withheld or released, the same two documents are rewritten the same way. A read never enumerates the store,
never screens a name, and never re-renders anything - its cost is one read of one document, however large
the repository has grown.

The cost of a write is therefore one rewrite of the listings the artifact belongs to, and nothing that
scales with the rest of the repository. Concurrent publishes to the same listing are merged into one rewrite
per server, and a compare-and-set write keeps several servers consistent. A listing a server has never
written - a repository from before this layout - is generated from the store the first time it is read and
stored from then on. The rebuild pass (`jenreg.rebuild.interval`) regenerates every stored listing on its
cadence, so a write that could not complete is repaired without a read ever paying for it.

## The map

Every capability in this section is one of these modules. This is where each plugs in:

| Capability | Chapter |
| --- | --- |
| Storage backends and the quota | *Storage* |
| Package formats - Maven, module layout, OCI, raw | *Formats* |
| The upstream fetcher and pull-through caching | *Proxying* |
| Access control | *Authentication & access* |
| The request ceiling | *Rate limiting* |
| Import connectors, batch upload, the asset listing | *Migration & import* |
| Logs, metrics, posture, multi-node consistency | *Observability* |
| The web console and its panels | *The console* |

Each chapter opens with what the capability does for you, then the implementations you can choose from, then
the settings that switch it on and tune it. *Storage* comes first because everything else writes through it.
