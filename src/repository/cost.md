---
order: 5
title: What it costs to run
description: Where the bill of a Jenesis Repository deployment comes from - the store's storage, egress and operations - with the operation counts the server makes per request and the providers' list prices they meet.
---

Jenesis Repository keeps no database. Everything it knows - an artifact's bytes, the pointer that names them, a
hold marker, a credential, a listing - is an object in the store you configured in [Storage](/repository/storage/).
That makes the bill unusually easy to read: it is the store's bill, and nothing else. Storage is charged per
gigabyte-month, transfer out per gigabyte, and every request the server makes to the store per thousand
operations. This chapter says how many operations a request costs, what that comes to at the providers' list
prices, and when a store without request charges is the cheaper choice.

## What a request costs the store

The bytes of an artifact are one object read per download and one object write per publish, on any design - a
repository with a database stores and serves them from the same kind of bucket. What a design decides is the
metadata traffic around them: the reads that resolve a path to a blob, and the writes that make a publish visible.
Those are counted here, for the Maven layout, over an idle server.

| Request | Read-class operations | Write-class operations |
|---|---|---|
| Download an artifact (`GET`) | 4 - the pointer, the hold marker, the blob's length, the bytes | 0 |
| Probe an artifact (`HEAD`) | 3 - the same without the bytes | 0 |
| Read a listing (`maven-metadata.xml`, an OCI tag list) | 1 - the stored document, however many versions it lists | 0 |
| Publish a POM | 2 | 2 |
| Publish a jar | 12 | 10 |

A download writes nothing and reads only small objects before the bytes, so its cost is the read class every
provider prices lowest. A publish is where the write class is paid: a POM is its bytes and the pointer that names them; a jar adds the module name the server records for it and the module-layout view of a modular jar, which is what makes the jar cost more. A proxied miss is a
download from the upstream followed by the same writes a publish makes, and every later download is a local hit.

Two things keep those counts from growing with the repository. A listing is a stored document that each publish
updates in place, so reading it costs one read over ten versions or ten thousand. And a request never enumerates a
namespace: a folder page reads one level, a version page reads one coordinate, and both resume from a cursor.

## What the background costs

One scheduled pass reads the store whole: the rebuild walk that regenerates every stored listing from the
artifacts, so a listing a crash left stale is repaired. It runs weekly by default (`jenreg.rebuild.interval`,
`P7D`), and at once after a node that stopped unclean starts again. It is the one line of the bill that grows
with the store rather than with the traffic, which is why it is weekly and not hourly, and why it can be switched
off (`false`) on a deployment whose listings are never left stale.

## The providers' list prices

The figures below are the providers' published prices for their standard storage class in one region, read on
**7 September 2026** from the sources named. They change; the sources are where to check them.

| Provider and region | Write-class operation (put, list, delete) | Read-class operation (get, head) | Storage | Transfer out to the internet |
|---|---|---|---|---|
| Amazon S3 Standard, US East (N. Virginia) | $5.00 per million | $0.40 per million | $0.023 per GB-month (first 50 TB) | 100 GB per month free, then $0.09 per GB (first 10 TB) |
| Azure Blob Storage, hot tier, LRS, East US | $5.00 per million | $0.40 per million | $0.0208 per GB-month (first 50 TB) | 100 GB per month free, then $0.08 per GB (first 10 TB) |
| Google Cloud Storage Standard, single region | $5.00 per million (class A) | $0.40 per million (class B) | $0.023 per GiB-month (the page's default region; varies by region) | $0.12 per GiB (first 10 TiB) |
| Scaleway Object Storage Standard, Multi-AZ | included | included | €0.016 per GB-month (€0.000022 per GB-hour) | 75 GB per month free, then €0.01 per GB |

Sources: the AWS Price List API's Amazon S3 and data-transfer offer files for `us-east-1`, published 31 August
2026; the Azure Retail Prices API for *General Block Blob v2, Hot LRS* and *Bandwidth, Routing Preference: Internet*
in East US (the operation meters are effective since 2016 and the egress meter since 2022); the Cloud Storage
pricing page at `cloud.google.com/storage/pricing`; and the storage pricing page at `scaleway.com/en/pricing/storage`.
Prices are without tax, and each provider's tiers fall with volume.

## A worked month

Take a repository serving a million downloads and a hundred publishes a day, with an average artifact of one
megabyte, on Amazon S3 in US East.

| Line | Operations or bytes per month | At list price |
|---|---|---|
| Download reads | 30 million × 4 = 120 million read-class | about $48 |
| Publish reads and writes | 3,000 publishes × (2 reads + 2 writes) | under $1 |
| Transfer out | 30 TB | about $2,600 |
| Storage of a 500 GB repository | 500 GB-months | about $12 |

The operations are a footnote next to the egress, and the egress is the same for any repository design because
it is the artifacts themselves. That is the rationale for keeping no database: a highly available managed
database is a second monthly bill and a second thing to operate, and what it would hold - the pointers, the
markers, the listings - costs cents a month to keep as objects and a dollar or two a month to read at this
traffic.

## Why a large store changes the answer

Two of the three lines on the bill scale with your traffic. Storage scales with what you keep, and transfer out
scales with what people download. Both are the same on any design, because the bytes are the bytes.

The operations line does not. A pass that reads the store whole costs a number of requests proportional to the
number of objects in it, not to how busy the repository is. A repository nobody touched all week still pays for
the pass, and it pays more every week as it grows. That is the line to watch, and it is the reason the pass is
weekly rather than hourly.

Reclaiming storage is the expensive part of that pass. Deciding that a stored blob is unreferenced means
establishing that nothing anywhere points at it, which cannot be answered from the blob itself: it takes an
enumeration. The design pays for that deliberately, because the alternative is a database holding the reference
counts, which is a second system to run, to back up and to keep consistent with the store. On a store that
charges per request, that choice shows up on the bill; on one that does not, it costs nothing at all.

So the arithmetic turns over somewhere. A small repository on a hyperscaler pays a few pounds a month for its
passes and should not think about it. A large one - millions of objects - pays for every one of them on every
pass, and at that size the operations line can exceed what serving your users costs. When it does, moving to a
store that does not charge per request removes the line rather than reducing it, and no amount of tuning the
software competes with that.

## Running your own S3-compatible store

Self-hosting is a supported deployment, not a workaround: the S3-compatible backend is tested against MinIO on
every build, so the same server binary and the same configuration work against your own store.

The realistic options differ in what they are built for.

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

What you take on is durability: replication or erasure coding, failure domains, capacity planning and upgrades
are yours. What you remove is a bill that grows with your object count whether or not anyone is using the
repository. For a large store that trade is usually worth making, and it is worth making before the store gets
large, because migrating a repository is easier when there is less of it.

<div class="tip">
  You do not have to guess where the turn is. The operation counts are the same on every backend, so measure a
  week of your own passes against your provider's request metrics, and compare the operations line with what the
  same hardware would cost you. The point at which they cross is specific to your repository, not to this table.
</div>

## When a request-free store wins

The comparison changes shape on a store that charges nothing per request and little for transfer. On Scaleway the
operations line disappears and the same 30 TB of egress is about €300; on a store you run yourself, as described
above, both lines become your hardware and your bandwidth. The server does not care which: every backend in
[Storage](/repository/storage/) sees the same operation counts. Your provider
counts them for you - S3 request metrics, and the request counters Cloud Storage and Azure Blob Storage
publish - so the figures above can be checked against your own traffic rather than taken on trust.

<div class="tip">
  Watch your provider's request counts across one day of your real traffic before choosing a region or a
  provider: the ratio of writes to reads is the whole difference between the price columns, and a repository
  that is read a thousand times for every publish sits almost entirely in the cheapest column.
</div>
