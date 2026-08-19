---
order: 5
title: Crawling it yourself
description: The crawler behind the public catalogue is a program you can run - what the main crawl does, the knobs it takes, and the companion tools that repair, extend, and report on a catalogue of your own.
---

The catalogue the public service serves is produced by an ordinary Java program, and that program is
available to run yourself. Reach for it when the public catalogue is not the one you need: a mirror your
network can reach when Central is not, an internal repository whose modules are never published publicly, or
an experiment with a different ownership policy.

Everything here runs from source with a JDK 25 and no build step - the JDK compiles it on demand:

```bash
java sources/build/jenesis/crawler/Crawl.java \
     https://maven-central.storage-download.googleapis.com/maven2/ \
     https://repo.maven.apache.org/maven2/.index/
```

## The crawl

`Crawl` is the program that produces a catalogue. It takes two URIs, and neither has a default: the first is
where artifacts are fetched from, the second where the repository's index is read. Pairing them separately is
deliberate - a fast, range-supporting mirror serves the jars while the canonical location serves the index.
Give one URI and it is used for both.

From there the crawl streams the index, and for every artifact that looks like a jar it fetches just enough of
the file to read whether it declares a module name. What it finds lands under `data/`, in the same
tab-separated files the [service reads](/modules/resolving/) - so a finished crawl is directly servable.

A run is bounded rather than exhaustive, because a full sweep of Maven Central takes many hours. It works to a
wall-clock budget, checkpoints as it goes, and resumes exactly where it stopped, so a catalogue is built up
over as many runs as it takes. Try it against a small budget first:

```bash
java -Djenesis.crawler.data=smoke-data -Djenesis.crawler.budget=3 \
     sources/build/jenesis/crawler/Crawl.java <artifact-uri> <index-uri>
```

The knobs you are likely to touch:

| Property | Default | Effect |
| --- | --- | --- |
| `jenesis.crawler.data` | `data` | Where the catalogue and the crawl's own state are written. |
| `jenesis.crawler.budget` | `180` | Wall-clock minutes this run may spend scanning before it stops cleanly. |
| `jenesis.crawler.concurrency` | `64` | Artifact fetches in flight, which is what bounds peak memory. |
| `jenesis.crawler.resume` | `true` | Set `false` to restart the index sweep; already-scanned artifacts are still skipped. |

There are more - checkpoint frequency, tail size, git publishing - and the repository's README documents them
next to the code that reads them.

### When the repository has no index

The file the crawl streams is a *Maven Indexer* index (`nexus-maven-repository-index.gz`), and that is not
part of the Maven repository layout - Maven itself never reads it. Maven Central publishes one and a
repository manager can be configured to generate one, but plenty of real repositories serve none at all.
Point `Crawl` at one of those and there is nothing to stream.

The way in is then the part of the layout *every* Maven repository does have: `maven-metadata.xml`, which
lists an artifact's versions. `LoadCoordinates` reads it for coordinates you name and `ReconcileMetadata` for
coordinates already recorded, so a catalogue of an internal repository is built by naming what it publishes
rather than by sweeping an index.

## The companion programs

A catalogue is never finished in one pass, so the crawler ships as a family of small programs around the main
one. Each is a `main` class you run the same way; the first three re-use the crawl's scanner, the rest only
read what is already on disk.

| Program | What it does |
| --- | --- |
| `RetryFailed` | Re-scans artifacts recorded as permanently failed, optionally narrowed by a regex over the recorded error. What you run after fixing a scanner bug. |
| `ReconcileMetadata` | Recovers versions the repository index omits entirely, by diffing each artifact's `maven-metadata.xml` against what was scanned. |
| `LoadCoordinates` | Scans every version of a `groupId:artifactId` you name, read from its `maven-metadata.xml` - a targeted add rather than a sweep, and the way into a repository with no index. |
| `IndexProbe` | Prints index records matching a search term, and a histogram of the extensions main records carry. A forensic tool for "why was this artifact never scanned?". |
| `ModuleSummary` | Regenerates the coverage summary from the catalogue. |
| `Regenerate` | Rebuilds the resolved views from the recorded history, which is how an ownership or filtering change is rolled out without re-fetching a single jar. |
| `DriftReport` | Lists module names published by more than one group whose ownership has not been settled, classified by what the collision looks like. |
| `ModuleMaven` | Writes the whole catalogue as a flat `<module-name>=<groupId>:<artifactId>` properties file, for a tool that only needs the mapping. |

The [reports chapter](/modules/reports/) describes what the last four produce; the public catalogue regenerates
them daily.

## Serving your own catalogue

A catalogue on disk becomes a service by pointing the reference deployment at it: the worker reads its data
from `DATA_BASE` and redirects to `ARTIFACT_BASE`, both plain environment variables. Set them at your own data
and your own artifact mirror and the [URL shapes](/modules/resolving/) are unchanged, so every client that
resolves against the public service resolves against yours without knowing the difference.

<div class="note">
  Crawling Maven Central end to end is a long job - roughly a hundred million index records, of which a few
  million are jars worth opening - so a first sweep runs for hours across however many budgeted runs it takes.
  A crawl of an internal repository is a different matter entirely, and usually finishes in one.
</div>

<div class="tip">
  The crawler lives in
  <a href="https://github.com/raphw/jenesis-modules">raphw/jenesis-modules</a>, whose README documents the
  remaining properties, the scheduled workflows that keep the public catalogue current, and the on-disk file
  formats - the detail you need when running a crawl of your own rather than using one.
</div>
