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

## When a request-free store wins

The comparison changes shape on a store that charges nothing per request and little for transfer. On Scaleway the
operations line disappears and the same 30 TB of egress is about €300; on a self-hosted S3-compatible store such
as MinIO or Ceph behind your own network, both lines are your hardware and your bandwidth. The server does not
care which: every backend in [Storage](/repository/storage/) sees the same operation counts. Your provider
counts them for you - S3 request metrics, and the request counters Cloud Storage and Azure Blob Storage
publish - so the figures above can be checked against your own traffic rather than taken on trust.

<div class="tip">
  Watch your provider's request counts across one day of your real traffic before choosing a region or a
  provider: the ratio of writes to reads is the whole difference between the price columns, and a repository
  that is read a thousand times for every publish sits almost entirely in the cheapest column.
</div>
