---
order: 4
title: How the index is produced
description: A short overview, for trust - how Maven Central is scanned, how each artifact's module name is read, how current and complete the index is, and how a name's owner is chosen.
---

You do not need any of this to use the service; the [resolving](/modules/resolving/) and
[reports](/modules/reports/) chapters are the whole user story. This chapter is background for **trust**:
where the numbers in the Jenesis Module Index come from, how fresh they are, and why a resolved answer is
the right one.

The module index is built by a **crawler** that scans Maven Central and, for every artifact that carries a
module name, records that name. Everything the service redirects to is derived from that record. The
crawler and its live progress live in the [`jenesis/jenesis-modules`](https://github.com/jenesis/jenesis-modules)
repository.

## Reading each artifact's real module name

The crawler does not guess a module name from coordinates or a POM. It opens the actual jar and reads the
name the publisher shipped, looking in order for:

1. a `module-info.class` at the jar root → the artifact is a **named** module;
2. the highest-versioned `module-info.class` inside a multi-release jar (`META-INF/versions/<N>/…`) → also
   **named**;
3. an `Automatic-Module-Name` entry in the manifest → an **automatic** module.

An artifact that has none of these carries no stable module name and is not added to the index.

This is why the [reports](/modules/reports/) can distinguish **named** from **automatic** with confidence:
the split reflects what is really inside each jar, not a heuristic.

## How current it is

The crawler runs on a schedule, **twice a day**, and records only what is new since the last run, so the
index tracks Maven Central continuously. Each report - the summary, the top-modules lists, the drift
report - is regenerated daily and states the date it was generated for. Once a week, a separate pass
reconciles every recorded artifact against Maven Central's own version lists to pick up what the index
stream missed.

<div class="warning">
  Maven Central's own index lags behind freshly published artifacts by <strong>up to a week</strong>, so a
  release from the last few days may not have been scanned yet. The service still redirects a request for
  an unrecorded version on a best-effort basis (see <a href="/modules/resolving/">Resolving</a>), so a
  build that names the version keeps working in the meantime.
</div>

You can watch the crawl in progress: [`data/STATUS.md`](https://github.com/jenesis/jenesis-modules/blob/main/data/STATUS.md)
is rewritten at every checkpoint with the current position, throughput, and sync mode.

## How it stays complete and self-heals

Scanning about a hundred million index records is not a clean, one-shot job, so the crawler is built to
converge on a complete picture rather than trust a single pass:

- **Every artifact is scanned once and remembered.** Maven Central coordinates are immutable, so once a jar
  has been read it is never fetched again. A scan that is interrupted resumes exactly where it left off,
  without losing or double-counting anything.
- **Transient failures are retried automatically.** A network blip or a temporary server error leaves the
  coordinate unrecorded, so the next run tries it again. Only genuinely broken artifacts - a malformed
  jar, a deleted coordinate - are recorded as permanent and skipped.
- **Gaps in Maven Central's index are recovered.** The index the crawler streams can omit brand-new
  releases or occasionally misreport an artifact. The weekly reconciliation compares each artifact's
  `maven-metadata.xml` against what was scanned and fills in the versions the index missed.
- **A rebuilt upstream index does not lose data.** If Maven Central republishes its index from scratch, the
  crawler re-sweeps automatically. The already-scanned record is preserved, so the re-sweep mostly re-reads
  the index without re-downloading jars.
- **Deletions are ignored.** A coordinate that was modular and is later removed from Central stays
  recorded, so a pinned build does not lose its answer.

## Why the resolved answer is trustworthy

A module name is not owned by anyone on Maven Central. It is just a string a jar carries, and unrelated
publishers routinely declare the same one. When the index has to pick a single authoritative publisher for
a name, it awards it to **whoever published that name first**. That keeps shaded copies and later
name-grabs out of the resolved view.

That rule is only as good as the publication dates behind it, so the crawler is careful about them. It
takes each artifact's real upload time from Maven Central's storage layer rather than the index's own
timestamp, because the index occasionally re-stamps older releases, which would distort who was really
first. Every claim on a name stays visible in the module's `versions.tsv` audit log, whoever won.

Where the first-publisher rule is wrong - a legitimate group rename, say - an operator overrides it with an
explicit ownership policy, the module's `owners.tsv`, which marks each publishing groupId `allowed` or
`rejected`. The resolved views are then rebuilt from the audit log without rewriting any history, and the
[drift report](/modules/reports/) lists the names where that decision is still open.
