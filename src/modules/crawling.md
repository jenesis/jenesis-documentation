---
order: 5
title: Crawling it yourself
description: The crawler behind the public Jenesis Module Index is a program you can run - what the main crawl does, the knobs it takes, the companion tools that repair, curate, and report on an index of your own, and how to serve it.
---

The Jenesis Module Index is produced by an ordinary Java program, and that program is available to run
yourself. Reach for it when the public index is not the one you need. That might be a mirror your network can
reach when Central is not, an internal repository whose modules are never published publicly, or an
experiment with a different ownership policy.

Everything here runs from source with a JDK 25 and no build step, because the JDK compiles it on demand:

```bash
java sources/build/jenesis/crawler/Crawl.java \
     https://maven-central.storage-download.googleapis.com/maven2/ \
     https://repo.maven.apache.org/maven2/.index/
```

## The crawl

`Crawl` is the program that produces an index. It takes two URIs, and neither has a default: the first is
where artifacts are fetched from, the second where the repository's index is read. Pairing them separately
is deliberate, so a fast, range-supporting mirror can serve the jars while the canonical location serves
the index. Give one URI and it is used for both.

From there the crawl streams the index and, for every artifact that looks like a jar, fetches just enough
of the file to read whether it declares a module name. What it finds lands under `data/`, in the same
tab-separated files the [service reads](/modules/resolving/), so a finished crawl is directly servable.

A run is bounded rather than exhaustive, because a full sweep of Maven Central takes many hours. It works
to a wall-clock budget, checkpoints as it goes, and resumes exactly where it stopped, so an index is built
up over as many runs as it takes. Try it against a small budget first:

```bash
java -Djenesis.crawler.data=smoke-data -Djenesis.crawler.budget=3 \
     sources/build/jenesis/crawler/Crawl.java <artifact-uri> <index-uri>
```

The knobs you are likely to touch:

| Property | Default | Effect |
| --- | --- | --- |
| `jenesis.crawler.data` | `data` | Where the index and the crawl's own state are written. |
| `jenesis.crawler.budget` | `180` | Wall-clock minutes this run may spend scanning before it stops cleanly. |
| `jenesis.crawler.concurrency` | `64` | Artifact fetches in flight, which is what bounds peak memory. |
| `jenesis.crawler.resume` | `true` | Set `false` to restart the index sweep; already-scanned artifacts are still skipped. |

There are more - checkpoint frequency, tail size, git publishing - and the project's README lists them.

### When the repository has no index

The file the crawl streams is a *Maven Indexer* index (`nexus-maven-repository-index.gz`), and that is not
part of the Maven repository layout - Maven itself never reads it. Maven Central publishes one and a
repository manager can be configured to generate one, but plenty of real repositories serve none at all.
Point `Crawl` at one of those and there is nothing to stream.

The way in is then the part of the layout *every* Maven repository does have: `maven-metadata.xml`, which
lists an artifact's versions. `LoadCoordinates` reads it for coordinates you name, and `ReconcileMetadata`
for coordinates already recorded. An index of an internal repository is therefore built by naming what it
publishes rather than by sweeping an index:

```bash
java sources/build/jenesis/crawler/LoadCoordinates.java \
     https://nexus.example.com/repository/maven2/ com.example:widgets com.example:gadgets
java sources/build/jenesis/crawler/Regenerate.java
```

`LoadCoordinates` writes audit rows only. Run `Regenerate` afterwards to derive the resolved views the
service reads; until then there is nothing to serve.

## The companion programs

An index is never finished in one pass, so the crawler ships as a family of small programs around the
main one. Each is a `main` class you run the same way; the ones that read the index honour
`jenesis.crawler.data` unless noted.

Programs that fetch from the repository:

| Program | What it does |
| --- | --- |
| `RetryFailed` | Re-scans artifacts recorded as permanently failed, optionally narrowed by a regex over the recorded error. What you run after fixing a scanner bug. |
| `ReconcileMetadata` | Recovers versions the repository index omits, by diffing each recorded artifact's `maven-metadata.xml` against what was scanned. |
| `LoadCoordinates` | Scans every version of a `groupId:artifactId` you name, read from its `maven-metadata.xml` - a targeted add rather than a sweep, and the way into a repository with no index. |
| `IndexProbe` | Streams a remote index and prints the records matching a search term, plus a histogram of the extensions it carries. A forensic tool for "why was this artifact never scanned?". |

Programs that only read what is on disk:

| Program | What it does |
| --- | --- |
| `Regenerate` | Rebuilds the resolved views from the audit log, which is how an ownership or filtering change is rolled out without re-fetching a single jar. `-Djenesis.crawler.regenerate.scope=artifacts\|modules` narrows it, `-Djenesis.crawler.regenerate.dry.run=true` previews it. |
| `SetOwners` | Applies an ownership policy from a properties file - module name to a comma-separated list of `groupId` or `groupId:artifactId` owners - writing each module's `owners.tsv` and regenerating its views. Publishers not listed are rejected. |
| `ListOwners` | Prints the current owners of every module matching a glob, in the format `SetOwners` reads, so you can review and edit a policy before applying it. |
| `DriftReport` | Writes the drift report. With `-Djenesis.crawler.drift.emit=<category>` it also writes a `SetOwners` file proposing an owner for every module in that category. |
| `ModuleSummary` | Regenerates the coverage summary. |
| `TopModules` | Writes a top-modules report for each `data/top/<year>.txt` list you pass; `-Djenesis.crawler.top.bleeding=true` produces the bleeding-edge variant. |
| `ModuleMaven` | Prints the named modules of the index as a flat `<module-name>=<groupId>:<artifactId>` properties stream, for a tool that only needs the mapping. Reads `data/modules/` in the working directory. |

The [reports chapter](/modules/reports/) describes what the summary, top-modules and drift reports contain;
the public index regenerates them daily. The checked-in `owners-republisher-fixes.properties` in the
project is a worked example of an ownership policy, ready for `SetOwners`.

## Serving your own index

An index on disk becomes a service by publishing its `data/modules/` tree over HTTP - a static file host,
an object store, or a git hosting service's raw view all work - and pointing the reference service at it.
The service reads `DATA_BASE`, the HTTP(S) base URL of that tree, and redirects to `ARTIFACT_BASE`, your
artifact mirror; both are plain environment variables. With those two set, the [URL
shapes](/modules/resolving/) are unchanged, so every client that resolves against the public service
resolves against yours without knowing the difference.

<div class="note">
  Crawling Maven Central end to end is a long job - roughly a hundred million index records, of which a
  few million are jars worth opening - so a first sweep runs for hours across however many budgeted runs
  it takes. A crawl of an internal repository is a different matter entirely, and usually finishes in
  one.
</div>

<div class="tip">
  The crawler lives in <a href="https://github.com/jenesis/jenesis-modules">jenesis/jenesis-modules</a>,
  whose README documents the remaining properties, the scheduled runs that keep the public index
  current, and the on-disk file formats - the detail you need when running a crawl of your own.
</div>
