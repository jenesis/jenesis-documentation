---
order: 4
title: Repositories
description: What a repository is, the Repositories page, and the pages inside one - its overview, browsing and searching what it holds, staging a release, and importing from elsewhere.
---

A repository is a named space of artifacts. It holds every format at once - a Maven jar, an npm package and a
container image can sit side by side in one repository - and it is the thing the **Repositories** section of
the console is about. This chapter covers the section and the **Contents** pages inside a repository; the
screening and lifecycle pages have chapters of their own.

## The repository your clients reach

Every client URL under `/repository/` reaches the deployment's repository - `releases`, unless
`JENREG_DEFAULT_REPOSITORY` names another. A Maven client at `/repository/maven/`, npm at `/repository/npm/`
and pip at `/repository/pypi/simple/` all read and write that one repository, each through its own format. It
comes into being with the first artifact published to it, and appears on the **Repositories** page from then on.

Other repositories exist to feed that one. A repository can be **defined** to fetch what it does not hold from
an upstream registry, or to group several others behind one name - which is how a single client URL serves both
your own packages and Maven Central. [Proxying upstreams](/repository/proxying/) shows how.

## The Repositories page

**Repositories → All repositories** lists the repositories that hold something, each with the marks of the
formats stored in it and badges that describe its shape:

| Badge | Meaning |
| --- | --- |
| **writable** | It accepts uploads into its own store. |
| **read-only** | It serves only what it fetches or groups; a publish to it is refused. |
| **host+proxy** | It accepts uploads *and* fetches misses from an upstream. |
| **fallback cached** / **fallback pass-through** | Where a miss goes, and whether what comes back is kept. |

A definition that is valid but risky - an upstream over plain HTTP, a fallback that skips screening - is listed
under **Definition warnings** at the top, so it is seen rather than discovered.

Two tenant-wide limits sit at the foot of the page:

- **Storage quota** - the most the deployment may store, across every repository, in bytes; a publish that
  would exceed it is refused. `0` means no limit, and the page shows how much is stored now.
- **Rate limit** - how many requests a minute the deployment serves before answering `429`; `0` falls back to the
  deployment default. [Operations](/repository/operations/) explains how requests are counted.

## Overview

Opening a repository lands on its **Overview**: what it is and what it published last.

- **Shape** - the repository's definition as badges, with its warnings, when it has a definition.
- **Hardened proxy screening** - shown when the repository screens every upstream body in full before serving
  a byte of it.
- **Absent formats** - an ecosystem the repository holds data for that no installed format can serve any more.
  Nothing is deleted because a format is missing; the data waits for the format to return, or for you to press
  **Forget ecosystem**, which retires those records so the space can be reclaimed.
- **Published index** - the state of the repository's content index, an incremental catalogue an external tool
  can sync against.
- **Releases** - the 200 most recent releases, newest first. Each opens that package's page, which lists its
  versions with when each was published, whether it is pinned, its download count where downloads are counted,
  and the paths it is served at.

## Browse & search

**Browse & search** walks the repository as its clients see it: the request paths artifacts are published
under - `maven/com/example/…`, `npm/…`, `raw/…` - rather than how they are stored underneath.

- A folder opens in place with the arrow beside it, one level at a time, so a large repository browses as
  quickly as a small one. A folder with a very large number of children is cut short with a notice that says so.
- The columns sort by name, type and size.
- **Search** finds packages by coordinate across every format, and opens a hit in the tree.
- An artifact's page shows its size, checksum, the coordinate and version its format read from it, the gate's
  verdict, its signature and provenance where it has them, and - for an artifact fetched from upstream - where
  it came from.

An artifact the gate is holding for review is not listed; it is on the **Quarantine** page instead, described
in [Screening what comes in](/repository/screening/).

## Staging

A staging upload holds a set of files back from the repository until you decide. A client publishes under a
staging id of its choosing instead of straight to the release path:

```bash
curl -H "Jenesis-Repository-Key: $KEY" -T app-1.0.jar \
  http://localhost:8080/repository/releases/staging/rc1/maven/com/example/app/1.0/app-1.0.jar
```

Nothing staged is resolvable. **Staging** lists the open ids with how many files each holds, and each has two
buttons: **promote** publishes everything staged under the id as one release, and **drop** discards it. Both need
the editor role, and a dropped id is gone for good.

## Import

**Import** copies another repository manager's contents into this repository - from Nexus, Artifactory, any
Maven repository, a package index or another Jenesis Repository. The page starts an import, shows each job's
progress as it runs, and resumes one that was interrupted. [Migrating in and
out](/repository/migration-import/) covers the connectors and what each copies.

<div class="tip">
  A repository's other pages - what the gate held, what the advisory feeds say, how long versions are kept - are
  the subject of <a href="/repository/screening/">Screening what comes in</a> and <a
  href="/repository/retention/">Retention, pins and cleanup</a>.
</div>
