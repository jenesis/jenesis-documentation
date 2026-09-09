---
order: 5
title: What it costs to run
description: Where the bill of a Jenesis Repository deployment comes from - the store's storage, transfer and operations - which lines grow with your traffic and which grow with your repository, where the traps are on each provider, and when a store that does not charge per request is the cheaper choice.
---

Jenesis Repository keeps no database. Everything it knows - an artifact's bytes, the pointer that names them, a
hold marker, a credential, a listing - is an object in the store you configured in [Storage](/repository/storage/).
That makes the bill unusually easy to read: it is the store's bill, and nothing else. There are three lines on it,
they grow with entirely different things, and knowing which is which is most of what this page is for.

| Line | Charged for | Grows with |
|---|---|---|
| Storage | Gigabyte-months held | **What you keep** |
| Transfer out | Gigabytes leaving the provider | **What people download** |
| Operations | Requests the server makes to the store | Partly your traffic, partly **the size of your repository** |

The first two are the same on any repository design, because the bytes are the bytes: a product with a database in
front of the same bucket stores and serves exactly what this one does. The third is where a design shows, and it is
the only line that can grow while nobody is using the repository at all.

<div class="tip">
  Deliberately no per-request operation counts appear on this page. They are a property of a release rather than of
  the design, they improve, and a number written here would be quietly wrong within a version or two. What is stable
  is the <em>shape</em>: which line grows with what, and what makes one of them surprise you. Your provider counts the
  operations for you - S3 request metrics, and the request counters Cloud Storage and Azure Blob Storage publish - so
  measure your own rather than trusting a table.
</div>

## What each line does as you grow

**Storage** is linear in what you keep and holds no surprises, other than the traps further down this page. A
repository that never deletes anything grows for ever, which is what retention policies and the collector are for.

**Transfer out** is linear in what people download, and for almost every deployment it is the largest line by a wide
margin. It is also the one that has nothing to do with this software: the same artifacts served by any other tool
cost the same to send. A caching proxy in front of your build agents, or agents in the same region as the bucket,
moves this line far more than any choice made here.

**Operations** has two halves that behave differently, and conflating them is the usual mistake.

- The **request half** is what serving a download or accepting a publish costs. It is a small, fixed number of small
  object reads per request, and it does *not* grow as the repository fills: a listing is a stored document that each
  publish updates in place, so reading it costs the same over ten versions or ten thousand, and no request ever walks
  a namespace - a folder page reads one level and resumes from a cursor. Ten times the artifacts, same cost per
  download.
- The **background half** is what the scheduled passes cost, and this one *is* proportional to the number of
  artifacts you hold. It is charged whether or not anybody used the repository that week.

## Reclaiming space is the line that grows with the store

One pass reads the store whole: the rebuild walk that regenerates every stored listing from the artifacts, so a
listing a crash left stale is repaired (`jenreg.rebuild.interval`, weekly by default, `off` to disable). Where the
[garbage collector](/repository/storage/) is enabled, its pass reads the store whole too, and for a reason worth
understanding before you tune anything.

Deciding that a stored blob is unreferenced means establishing that *nothing anywhere* points at it. That cannot be
answered from the blob: it takes an enumeration of everything that could name it. So a collection's cost splits the
same way the bill does:

- **Its reads grow with what you hold.** Every pointer is read to learn which blob it names, and the pool is listed
  to find the blobs. A repository that deletes nothing and reclaims nothing still pays this, in full, every pass -
  which is the single most counter-intuitive thing on this page. The enumeration is the price of knowing, not the
  price of deleting.
- **Its writes grow with what you reclaim.** Deleting N blobs costs at least N deletes, and no design avoids that
  floor. Write-class operations are priced around twelve times a read on every hyperscaler, so a pass that reclaims
  a lot is dominated by its writes, and a pass that reclaims nothing is dominated by its reads.

The design pays for the enumeration deliberately. The alternative is a database holding reference counts - a second
system to run, back up, and keep consistent with the store, whose disagreement with the store is a data-loss bug
rather than a stale number. Where the store charges per request, that choice shows up on the bill. Where it does
not, it costs nothing at all.

The practical consequence: **the operations line matters most for a large, quiet repository.** A busy one drowns it
in egress. An archive of ten million artifacts that nobody downloads pays for its passes and little else, and that
is exactly the deployment that should either lengthen the cadence, switch the passes off, or move to a store that
does not meter requests.

## A worked month, per million artifacts

Assumptions, all of them arguable and all of them yours to change:

- **one million artifacts**, averaging **1 MB** each, so **1 TB** stored;
- a few small metadata objects per artifact - a pointer, checksums, a listing entry - which cost almost nothing to
  store and are counted by every pass;
- **3,000 publishes a month**;
- Amazon S3 Standard in US East at the list prices in the next section;
- and two traffic levels, because this is where deployments differ most: a **quiet** internal repository where each
  artifact is fetched about once a month (1 TB out), and a **busy** one serving a million downloads a day (30 TB out).

| Line | Quiet (1 TB out) | Busy (30 TB out) |
|---|---|---|
| Storage, 1 TB | about $24 | about $24 |
| Transfer out | about $85 | about $2,700 |
| Operations, request half | pennies | a few tens of dollars |
| Operations, background half (weekly passes over a million artifacts) | a few dollars | a few dollars |

Read the columns rather than the cells. On the busy repository the store's own bill is a rounding error against
egress, and the background passes are invisible. On the quiet one, egress still dominates - but the background is
now a visible fraction, and it is the line that will keep growing as the repository fills while the others stand
still. At ten million artifacts the background half is ten times what it is here and the storage line is ten times
larger too; at a hundred million, the background half alone is worth a deployment decision.

<div class="tip">
  If you take one number away, take the ratio rather than the total: for most repositories, transfer out is between
  ten and a hundred times everything else combined. Optimising the store's operations while paying full egress to a
  build farm in another region is polishing the smallest line on the invoice.
</div>

## The traps

These are the ways a bill comes out several times larger than the arithmetic above, and none of them is specific to
this software. Every one of them has bitten somebody.

**Deleting does not free space on a versioned bucket.** This is the big one, because the collector will report
blobs reclaimed while your storage line does not move - both statements true, about different things. On a bucket
with versioning enabled, an ordinary delete writes a *delete marker*: the object stops being listed and served, and
every prior version stays, and is still billed. Only a delete that names a version, or a lifecycle rule that expires
noncurrent versions, frees the bytes. The server deliberately does not issue versioned deletes: versioning is a
safety net you turned on, and reaching past it would destroy the protection you are paying for. **If you enable
versioning, add a noncurrent-version expiration rule**, or storage grows without bound.

The same shape appears under other names, and the default differs by provider, so check the bucket rather than
assuming:

| Provider | The retention feature to check | What it does to reclamation |
|---|---|---|
| Amazon S3 | Bucket versioning; Object Lock | Deletes become delete markers; under Object Lock a version cannot be removed at all until its retention expires |
| Google Cloud Storage | Object versioning; **soft delete** | Soft delete retains and bills deleted objects for its retention window; it has been enabled by default on new buckets, so verify yours rather than assuming it is off |
| Azure Blob Storage | Blob soft delete; blob versioning | Deleted blobs and prior versions are retained and billed for the configured retention period |

**Cold storage classes are a trap for this workload specifically.** A repository stores a great many small objects
beside the artifacts. The colder classes bill a **minimum object size** - 128 KB on S3 Standard-IA and Glacier
Instant Retrieval, with comparable rules on the other providers - so a two-hundred-byte pointer moved there is
billed as 128 KB, several hundred times its size. They also bill a **minimum storage duration** (30, 90 or 180 days
depending on the class), and a collector reclaims exactly the short-lived objects, so early-deletion charges land on
precisely the wrong ones. And they charge **per gigabyte retrieved**, which a repository does constantly. If you
tier at all, tier the artifact bytes and leave the metadata namespaces in the standard class.

**Incomplete multipart uploads bill until they are aborted**, and they do not appear in an ordinary listing. A
lifecycle rule to abort them after a few days is worth having on any bucket that receives large artifacts.

**Lifecycle transitions are themselves charged per object.** Moving a million small objects to a cheaper class costs
a million write-class operations, which can exceed the storage saved for a year.

**Egress is charged per region boundary, not per internet boundary.** Build agents in a different region from the
bucket pay for every download, at rates comparable to internet egress. Co-locating them is usually the largest
saving available to any deployment on this page.

## What each backend must support, and what is checked at boot

Everything the server does across nodes - leases, listing edits, counters, the identity fold - rests on the store
honouring two write preconditions: *create only if absent*, and *replace only if unchanged*. Each protocol spells
them differently:

| Backend | How the precondition is expressed | Version token |
|---|---|---|
| `s3` (and S3-compatible) | `If-None-Match: *` on create, `If-Match: <etag>` on replace | the object ETag |
| `azure-blob` | `If-None-Match: *` on upload, `If-Match: <etag>` on replace | the blob ETag |
| `gcs` | `ifGenerationMatch=0` on insert, the current generation on replace | the object generation |
| `filesystem` | the local file system's own atomicity | last-modified paired with a digest of the bytes |

"S3-compatible" is a spectrum, and this is the part of it that matters. Some endpoints accept both headers and
ignore them; some honour the first and not the second. Over such an endpoint two nodes would each believe they won
every compare-and-set and overwrite one another without a trace, and **nothing at request time can tell** - the write
succeeds either way.

So the server asks once, at boot, and refuses to start if the answer is wrong. The probe writes one fresh key under
the system namespace four times: a create that must land, the same create again that must be refused, a replace under
the token the create left that must land, and the same replace under that now-stale token that must be refused. Any
other answer names the endpoint and stops the node. The key is deleted afterwards whatever happened.

It can be switched off per backend - `jenreg.s3.conditional-write-probe`, `jenreg.azure-blob.conditional-write-probe`,
`jenreg.gcs.conditional-write-probe`, all `false` - for an endpoint you have satisfied yourself about by other means,
or one that refuses writes under the system namespace. The node then boots with a warning saying what you have given
up. A single-node deployment is the case where that is defensible.

Two related switches exist for the same reason. `jenreg.<backend>.streaming-writes=false` buffers a conditional
write's body instead of streaming it, for an implementation that mishandles a streamed conditional PUT; it restores a
heap cost and does nothing else, so use it to work around a store and expect the memory ceiling to fall.
`jenreg.<backend>.allow-insecure-endpoint=true` permits a plain-HTTP endpoint, which is for an emulator on a
developer's machine and not for a deployment.

Beyond the preconditions, each backend needs only what any object store offers: ranged reads, prefix listing with
pagination, delete, and the object's length. The credentials each one takes, and the rest of its settings, are in
[Storage](/repository/storage/).

## The filesystem is a real answer for a small store

The filesystem backend is not a development-only mode. For a single node serving a team, with backups you already
take, it is the cheapest and simplest thing that works: no request charges, no egress inside your network, no
provider to reason about, and the traps above do not exist. Its limit is honest and absolute - **one node**. The
compare-and-set the multi-node story rests on is the local file system's, so a second server over the same directory
is not a supported deployment, whatever the directory is mounted from. Network file systems do not change that; they
change which failure you get.

Take the filesystem when the repository fits on one machine and one machine is enough. Move to an object store when
you need more than one node, not when the directory gets large.

## When a store that does not meter requests wins

On a provider that includes operations in the price, the entire operations line disappears - both halves, the
background passes included - and the calculus above collapses to storage and transfer. From the table below, the
same 30 TB of egress that costs about $2,700 on S3 is about €300 on Scaleway, and the passes cost nothing whatever
the repository's size.

Running the store yourself removes both lines and replaces them with your hardware and your bandwidth. Be honest
about the trade: durability, replication or erasure coding, failure domains, capacity planning and upgrades become
yours, and that is real operational work rather than a line item. It is worth it when the object count is large
enough that the background passes are a standing charge you resent - tens of millions of objects, not one million -
and it is worth doing *before* the store gets large, because migrating a repository is easier when there is less of
it.

Self-hosting is a supported deployment rather than a workaround: the S3-compatible backend is tested against MinIO
on every build, so the same server binary and the same configuration work against your own store. The realistic
options differ in what they are built for.

- **MinIO** is the usual choice. Distributed mode spreads erasure-coded data across nodes and drives, it handles
  small objects well, and it is the implementation this project tests against. Check its current licence terms
  before committing to it.
- **Ceph**, through its S3 gateway, is the heavyweight: proven at very large scale, self-healing, with erasure
  coding and replication you configure. It asks the most of whoever operates it, and its per-object overhead
  makes very small objects relatively expensive.
- **SeaweedFS** is built for enormous numbers of small files and offers an S3 gateway over that. A repository
  stores a great deal of small metadata beside the artifacts, so this suits the shape of the data well.
- **Garage** is worth considering for smaller or geographically spread deployments, where simple operation
  matters more than peak throughput.

Whichever you choose, run the conditional-write probe against it - that is, leave it on and let the node start. An
endpoint that fails it is one you would otherwise discover through silent data loss under two nodes.

## The providers' list prices

The figures below are the providers' published prices for their standard storage class in one region, read on
**7 September 2026** from the sources named. They change; the sources are where to check them.

| Provider and region | Write-class operation (put, list, delete) | Read-class operation (get, head) | Storage | Transfer out to the internet |
|---|---|---|---|---|
| Amazon S3 Standard, US East (N. Virginia) | $5.00 per million | $0.40 per million | $0.023 per GB-month (first 50 TB) | 100 GB per month free, then $0.09 per GB (first 10 TB) |
| Azure Blob Storage, hot tier, LRS, East US | $5.00 per million | $0.40 per million | $0.0208 per GB-month (first 50 TB) | 100 GB per month free, then $0.08 per GB (first 10 TB) |
| Google Cloud Storage Standard, single region | $5.00 per million (class A) | $0.40 per million (class B) | $0.023 per GiB-month (the page's default region; varies by region) | $0.12 per GiB (first 10 TiB) |
| Scaleway Object Storage Standard, Multi-AZ | included | included | EUR 0.016 per GB-month (EUR 0.000022 per GB-hour) | 75 GB per month free, then EUR 0.01 per GB |

Sources: the AWS Price List API's Amazon S3 and data-transfer offer files for `us-east-1`, published 31 August
2026; the Azure Retail Prices API for *General Block Blob v2, Hot LRS* and *Bandwidth, Routing Preference: Internet*
in East US (the operation meters are effective since 2016 and the egress meter since 2022); the Cloud Storage
pricing page at `cloud.google.com/storage/pricing`; and the storage pricing page at `scaleway.com/en/pricing/storage`.
Prices are without tax, and each provider's tiers fall with volume.

<div class="tip">
  Watch your provider's request counts across one day of your real traffic before choosing a region or a provider:
  the ratio of writes to reads is the whole difference between the price columns, and a repository that is read a
  thousand times for every publish sits almost entirely in the cheapest column.
</div>
