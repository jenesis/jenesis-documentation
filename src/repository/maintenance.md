---
order: 7
title: Maintenance
description: The two background primitives that keep a store healthy - the shared, resumable artifact walk every store-sweeping pass rides, and the opt-in mark-sweep garbage collector that reclaims blobs nothing points at any more.
---

A repository accumulates. Versions are superseded, pointers are removed, and the blobs behind them stay on
disk until something reclaims them. Two primitives handle that, and both are built for a store far too large
to sweep in one pass: an **artifact walk** that enumerates the store resumably, and a **garbage collector**
that rides it.

Both are background work, so both are designed around the same constraint - a pass may be interrupted at any
moment, and must be able to pick up where it stopped rather than start again.

## The shared artifact walk

Each pass above visits what it already knows how to find - a repository's versions, its stored SBOMs. A pass
that must visit **everything the store holds** rides a different primitive: the **shared artifact walk**, one
ordered, resumable enumeration of the store's keys that every store-sweeping consumer uses instead of writing
its own listing loop. The walk is itself a discovered capability - `jenreg.walk` selects an
implementation by name, and the shipped `store` walk descends the store's own key layout through ordered
paging - and it hands every rider the same guarantees:

- **It resumes, never restarts.** Progress is committed as a compare-and-set cursor every
  `jenreg.walk.checkpoint` keys (default `1000`). A node that dies mid-pass loses at most the uncommitted
  tail, which is re-visited on resume - so a consumer is written to tolerate seeing an item twice, and a pass
  over a huge store survives any interruption.
- **Replicas split the work without a coordinator.** A pass is planned as up to `jenreg.walk.segments`
  contiguous ranges (default `32`), and each node claims a segment with a compare-and-set write - a claim is
  refused, never stolen. A dead node's claim expires after `jenreg.walk.ttl` seconds (default `900`) and
  another node resumes the segment from its last cursor.
- **State lives only in the store.** Like everything else, a pass's manifest and cursors are objects in the
  object store - there is no scheduler database, and a pass survives the death of any process that ran it.

The walk also carries a **rebuild seam**: one enumeration of the published pointers can feed every installed
walk consumer its retained items. A plug-in enabled late - a new index, a new gauge - back-fills its whole
view from one shared pass rather than shipping a scan of its own.

## Garbage collection

Content addressing splits removal in two. Deleting a version removes its *pointer*; the *blob* it pointed at
may be shared with other versions, so blobs are reclaimed separately, once nothing references them. A store
also accrues blobs no pointer ever named - the orphan of a rejected or crashed upload, bytes whose every
pointer is long gone. The **garbage collector** is the capability that finds and reclaims them.

Deleting data is the one unrecoverable act, so garbage collection is the most strictly opt-in capability in
the product: **with no collector module installed, nothing is ever reclaimed** - the standard image ships
without one, and its absence costs only disk. Installing one is a deliberate choice, and
`jenreg.gc` selects among installed collectors by name; **`mark-sweep`** is the shipped
implementation.

The `mark-sweep` collector rides the shared artifact walk - never a listing loop of its own - and is built so
a live blob can never be deleted:

- **Mark, sharded.** A walk over the serving pointers records every referenced blob hash, flushed durably
  *before* each cursor commit - so a committed cursor never lies about a reference that was still sitting in
  a buffer. The sweep then reads the content-addressed namespace in hash order, one leading-byte shard at a
  time, so memory stays bounded on a store of any size.
- **Condemn, then collect.** A pass that finds an unreferenced blob does not delete it - it **condemns** it
  with a marker. Only a *later* pass that finds the blob still unreferenced deletes it, with the marker
  re-read immediately before the delete. Every blob therefore gets at least one full pass interval of grace.
- **The write path cooperates.** Landing a pointer - a publish, a promotion, a deduplicated re-deploy of
  bytes already stored - clears the blob's condemned marker, so content that becomes referenced again between
  passes is never collected.
- **Only blobs are judged.** The collector only ever evaluates content-addressed blob objects; every other
  object in the store - pointers, indexes, configuration - is untouched by construction.
- **A dry run first.** The collector distinguishes a read-only **plan** - what a collection *would* reclaim,
  writing nothing - from the collection itself, so a first run can be previewed before anything is deleted.

The walk and collector read **startup keys, spelled in full** (they are not per-repository dials):

| Key | Default | Meaning |
|-----|---------|---------|
| `jenreg.walk` | *(first enabled - `store`)* | Selects the artifact-walk implementation store-sweeping passes enumerate through. |
| `jenreg.walk.checkpoint` | `1000` | Keys visited between durable cursor commits of a walk segment. |
| `jenreg.walk.segments` | `32` | Target number of ranges a pass is split into across nodes. |
| `jenreg.walk.ttl` | `900` | Seconds before a dead node's segment claim expires and its segment is resumed elsewhere. |
| `jenreg.gc` | *(none installed - nothing reclaimed)* | Selects the garbage collector; `mark-sweep` is the shipped implementation. |
| `jenreg.gc.stride` | `20000` | Checkpoint stride of the collector's own walk passes. |
| `jenreg.gc.grace` | *(none)* | Optional ISO-8601 wall-clock floor on the condemn-to-collect grace, on top of the one-pass gap. Set it so a blob is never reclaimed until it has carried its condemned marker at least this long - a guard for when several nodes collect, or a node re-collects after a lease expiry, and generations advance faster than the collection interval. |

## Settings

The walk's dials are runtime-tunable; garbage collection is off until you turn it on.

| Key | Default | Meaning |
|-----|---------|---------|
| `jenreg.walk` | `store` | Which walk implementation the store-sweeping passes ride, selected by name. |
| `jenreg.walk.checkpoint` | `1000` | Keys between resumable cursor writes. |
| `jenreg.walk.segments` | `32` | How many contiguous ranges a pass is planned as, so replicas can claim one each. |
| `jenreg.walk.ttl` | `900` | Seconds a segment claim survives a dead node before another may resume it. |
| `jenreg.gc.stride` | `20000` | Objects scanned per garbage-collection pass. |
| `jenreg.gc.grace` | *(see below)* | How long an unreferenced object survives before the collector may reclaim it. |

The grace period is the safety margin that makes collection safe to run against a live server: a blob that
has just been written but not yet pointed at must not be mistaken for garbage. Leave it long enough to cover
your slowest publish.

Because every cursor and manifest these passes keep lives only in the scoped object store, there is nothing
extra to back up: delete a derived index and the next sweep rebuilds it.
