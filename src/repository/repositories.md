---
order: 4
title: Repositories
description: What a repository is, the Repositories page, and the pages inside one - its overview, browsing and searching what it holds, staging a release, and importing from elsewhere.
---

A repository is a named space of artifacts of one **type**: a format such as `maven`, `npm`, `pypi` or `oci`, or
a combined type that holds several formats together, such as `java` - Maven and the Jenesis module layout in one.
It is the thing the **Repositories** section of the console is about. This chapter covers the section and the
**Contents** pages inside a repository; the screening and lifecycle pages have chapters of their own.

## How a repository comes into being

A repository is **created**, with its type, before anything is published into it or resolved from it - under
**Repositories → New repository**, or with a `PUT` of its URL naming the type:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"npm"}' https://repo.example.com/repository/default/npm
```

The answer is `201` when the repository is created and `200` when it already holds that type. A repository that
holds `maven` may be created again as `java`, which holds everything `maven` does, and becomes one - every URL it
answered still answers. Any other change of type is refused with `409`, since what is stored there would stop
answering, and a type the deployment does not offer is refused with `400` and the list of those it does. Creating a
repository is administration: the key needs `manage:write`, which the **admin** role grants, and in the console it
takes the editor role.

Nothing else creates a repository. A request to one that was never created is answered `404`, and a publish into
one is refused with `404` and a sentence saying so - so a misspelled name in a build's configuration fails rather
than becoming a repository. A repository whose format has been switched off answers `404` the same way until the
format is back.

## The URL a client reaches

Every URL names the tenant first and the repository second: `/repository/<tenant>/<repository>/…`, or
`/v2/<tenant>/<repository>/<image>` for container images. A deployment serves one tenant - `default`, unless
`JENREG_DEFAULT_TENANT` names another - and answers `404` for a URL that names any other.

A repository of one format leaves that format's name out of its URLs: an `npm` repository named `npm` is the
registry `/repository/default/npm/`, and a `pypi` one named `python` is installed from
`/repository/default/python/simple/`. Maven and the Jenesis module layout keep theirs - a Maven repository named
`releases` answers at `/repository/default/releases/maven/`, and a `java` repository at both `…/maven/` and
`…/module/` - which is what lets the two share one repository. [Connecting your build
tools](/repository/formats/) gives the URL for every client.

A repository can also be **defined** to fetch what it does not hold from an upstream registry, or to group
several others behind one name - which is how a single client URL serves both your own packages and Maven
Central. A definition describes a repository; it does not create one. [Proxying upstreams](/repository/proxying/)
shows how.

## The Repositories page

**Repositories → All repositories** lists the tenant's repositories, each with the mark of the type it holds, the
type's name, and badges that describe its shape:

| Badge | Meaning |
| --- | --- |
| **writable** | It accepts uploads into its own store. |
| **read-only** | It serves only what it fetches or groups; a publish to it is refused. |
| **host+proxy** | It accepts uploads *and* fetches misses from an upstream. |
| **fallback cached** / **fallback pass-through** | Where a miss goes, and whether what comes back is kept. |

A definition that is valid but risky - an upstream over plain HTTP, a fallback that skips screening - is listed
under **Definition warnings** at the top, so it is seen rather than discovered.

**New repository** creates one: a name - letters, digits, hyphens and underscores - and a type from those the
deployment offers. It answers at `/repository/<tenant>/<name>/`, or `/v2/<tenant>/<name>/` for container images,
from the moment it is created. A repository that holds files but no type - one kept from before repositories had
types - is listed with a **no format** badge and answers nothing until an editor gives it one with **Give
format**.

Beside it, below the list, are two tenant-wide limits:

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

**Browse & search** walks the paths the repository's format lays its artifacts out under - `maven/com/example/…`
in a Maven repository, `npm/…` in an npm one - rather than how they are stored underneath.

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
staging id of its choosing - to `/staging/<tenant>/<repository>/<id>/` followed by the path it would otherwise
publish to within the repository - instead of straight to the release path:

```bash
curl -H "Jenesis-Repository-Key: $KEY" -T app-1.0.jar \
  http://localhost:8080/staging/default/releases/rc1/maven/com/example/app/1.0/app-1.0.jar
```

Nothing staged is resolvable. **Staging** lists the open ids with how many files each holds, and each has two
buttons: **promote** publishes everything staged under the id as one release, and **drop** discards it. Both need
the editor role, and a dropped id is gone for good.

A script does the same through the repository's operations, which name the repository in `?repo=` and take a key
that may read it (to list) or write to it (to promote or drop):

```bash
curl -H "Jenesis-Repository-Key: $KEY" 'http://localhost:8080/api/repository/staging?repo=releases'
curl -X POST -H "Jenesis-Repository-Key: $KEY" \
  'http://localhost:8080/api/repository/staging/rc1/promote?repo=releases'
```

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
