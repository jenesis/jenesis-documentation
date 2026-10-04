---
order: 4
title: Repositories
description: What a repository is, creating one with its settings, the Repositories page, and the pages inside one - its overview, browsing and searching what it holds, staging a release, importing from elsewhere, and its settings.
---

A repository is a named space of artifacts of one **type**: a format such as `maven`, `npm`, `pypi` or `oci`, or
a combined type that holds several formats together, such as `java` - Maven and the Jenesis module layout in one.
It is the thing the **Repositories** section of the console is about. This chapter covers the section and the
**Contents** pages inside a repository; the screening and lifecycle pages have chapters of their own.

## How a repository comes into being

A repository is **created**, with its type, before anything is published into it or resolved from it - in the
console, with a `PUT` of its URL naming the type, or from the command line:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"npm"}' https://repo.example.com/repository/releases/npm
jenrepo repos create npm npm
```

The answer is `201` when the repository is created and `200` when it already holds that type. A repository that
holds `maven` may be created again as `java`, which holds everything `maven` does, and becomes one - every URL it
answered still answers. Any other change of type is refused with `409`, since what is stored there would stop
answering, and a type the deployment does not offer is refused with `400` and the list of those it does. Creating a
repository is administration: the key needs `manage:write`, which the **admin** role grants, and in the console it
takes the editor role.

A repository may carry a **description** - one line of up to 280 characters, shown under its name in the list -
given at creation beside the type, `{"value":"npm","description":"Internal packages"}`, or later on its own,
`{"description":"…"}`, which changes the description of a repository that exists and leaves its type alone. An empty
description clears it.

## Creating one with its settings

A repository can be given its own settings as it is created - how long it keeps what it holds, and where it fetches
what it lacks - so it answers its first request as configured. The console asks them in a wizard: **New
repository** on **Repositories → Current repositories** opens it.

1. **Repository** - the name, the format, and optionally a description.
2. **Retention** - the four retention rules, each left blank to inherit the tenant's and the deployment's value.
3. **Routing** - whether it accepts uploads and where it fetches from, written as
   [Proxying upstreams](/repository/proxying/) describes. Routing is the deployment administrators' decision, so
   anyone else sees it fixed rather than asked.
4. **Search** - whether the repository keeps a full-text index.
5. **Review** - every choice, the defaults left alone included.

**Next** checks a step before moving on, **Back** loses nothing, and the list of steps above the wizard returns to
any of them. **Create repository** on the review creates the repository and its settings together. **Create now**,
from any later step, leaves the remaining settings to inherit and goes to the review to confirm. Nothing is written
before **Create repository**, so a closed tab leaves nothing half made.

The API and the command line take the same settings beside the type:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"maven","settings":{"keep-last":"20","max-age":"P365D"}}' \
  https://repo.example.com/repository/releases/libraries
jenrepo repos create libraries maven "Internal libraries" --set keep-last=20 --set max-age=P365D
```

Every value is checked before anything is written: one the setting refuses answers `400`, naming each refused
value, and nothing is created. A creation that carries settings only creates - for a repository that exists already
it answers `409` and changes nothing - and a repository's settings are changed afterwards on its **Settings** page,
as [Settings](/repository/settings/#a-repository-s-settings) describes.

Nothing else creates a repository. A request to one that was never created is answered `404`, and a publish into
one is refused with `404` and a sentence saying so - so a misspelled name in a build's configuration fails rather
than becoming a repository. A repository whose format has been switched off answers `404` the same way until the
format is back.

## Deleting a repository

Deleting a repository removes it **and everything it holds** - every artifact, index, staged upload and pin, and
its definition - and cannot be undone. In the console it is the **Delete** button on its row, or **Delete
repository** at the foot of its own page, and it asks you to type `delete <name>` before it does anything. Every
other deletion in the console asks the same way.

```bash
curl -X DELETE -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/releases/npm
```

The repository stops answering at once; what it held is removed in the background, so the answer is `202` however
large it is, and the list shows it as **being deleted** until it is gone - after which the name can be created
again. A deletion that a restart interrupted is finished by deleting again. Like creating one, deleting a
repository takes `manage:write`; a key that may only publish into it is refused. From the command line,
`jenrepo repos delete <name>` asks for the same typed confirmation, or takes `--yes` in a script.

## The URL a client reaches

Every URL names the tenant first and the repository second: `/repository/<tenant>/<repository>/…`, or
`/v2/<tenant>/<repository>/<image>` for container images. A deployment serves one tenant - `releases`, unless
`JENREPO_DEFAULT_TENANT` names another - and answers `404` for a URL that names any other.

A repository of one format leaves that format's name out of its URLs: an `npm` repository named `npm` is the
registry `/repository/releases/npm/`, and a `pypi` one named `python` is installed from
`/repository/releases/python/simple/`. Maven and the Jenesis module layout keep theirs - a Maven repository named
`libraries` answers at `/repository/releases/libraries/maven/`, and a `java` repository at both `…/maven/` and
`…/module/` - which is what lets the two share one repository. [Connecting your build
tools](/repository/formats/) gives the URL for every client.

A repository can also be **routed** to fetch what it does not hold from an upstream registry, or to group several
others behind one name - which is how a single client URL serves both your own packages and Maven Central. Routing
describes a repository; it does not create one. [Proxying upstreams](/repository/proxying/) shows how.

## The Repositories page

**Repositories → Current repositories** lists the tenant's repositories, with **New repository** below them. Each is shown
with the mark of the type it holds, its description, the type's name, when it was created, and badges that describe
its shape:

| Badge | Meaning |
| --- | --- |
| **writable** | It accepts uploads into its own store. |
| **read-only** | It serves only what it fetches or groups; a publish to it is refused. |
| **host+proxy** | It accepts uploads *and* fetches misses from an upstream; what it published answers first, as [Proxying upstreams](/repository/proxying/#a-repository-that-hosts-and-proxies) describes. |
| **fallback cached** / **fallback pass-through** | Where a miss goes, and whether what comes back is kept. |

A definition that is valid but risky - an upstream over plain HTTP, a fallback that skips screening - is listed
under **Definition warnings** at the top, so it is seen rather than discovered.

A repository's name is letters, digits, hyphens and underscores. It answers at `/repository/<tenant>/<name>/`, or
`/v2/<tenant>/<name>/` for container images, from the moment it is created. A repository that holds files but no type - one kept from before repositories had
types - is listed with a **no format** badge and answers nothing until an editor gives it one with **Give
format**.

## Limits

**Repositories → Limits** holds the two limits that apply to all of a tenant's repositories together. Both are
tenant settings: the deployment's value applies until the tenant sets its own, and **Reset to default** returns to it. Every
member reads them; an admin changes them.

- **Storage quota** (`tenant-quota`) - the most the tenant may store, across every repository, in bytes; a
  publish that would exceed it is refused with `507`. `0` means no limit, and nothing is metered while there is
  none: setting one counts what is already stored on the next cleanup pass, and the page then shows how much is
  stored against it.
- **Rate limit** (`rate-limit`) - how many requests a minute the tenant is served before answering `429`; none by
  default, since a per-address limit already stops a runaway client. [Operations](/repository/operations/) explains
  how requests are counted.

`jenrepo limits` shows both, and `jenrepo limits set quota <bytes>` or `jenrepo limits set rate <per-minute>` sets
the tenant's own; `0` there returns to the deployment's value.

## Overview

Opening a repository lands on its **Overview**: what it is and how it is routed.

- **Routing** - how the repository is routed, as badges with any warnings, and where that comes from: its own
  routing, the deployment's definition of its name, or none. A repository with no routing accepts uploads, and
  fetches what it lacks through its format's upstream where one is named - the page says which. A deployment
  administrator changes the routing on the repository's **Settings** page, where unsetting it hands the repository
  back to the deployment's definition.
- **Hardened proxy screening** - shown when the repository screens every upstream body in full before serving
  a byte of it.
- **Absent formats** - an ecosystem the repository holds data for that no installed format can serve any more.
  Nothing is deleted because a format is missing; the data waits for the format to return, or for you to press
  **Forget ecosystem**, which retires those records so the space can be reclaimed.
- **Published index** - the state of the repository's content index, an incremental catalogue an external tool
  can sync against.

A copy cached from an upstream is a holding of its own, apart from the releases: the scheduled advisory and
maintainer-health scans check it as they check a release, and it is listed wherever the repository's contents are,
while retention keeps to what was published.

## Browse & search

**Browse & search** walks the paths the repository's format lays its artifacts out under - `maven/com/example/…`
in a Maven repository, `npm/…` in an npm one - rather than how they are stored underneath.

- A folder opens in place with the arrow beside it, one level at a time, so a large repository browses as
  quickly as a small one. A folder with a very large number of children is cut short with a notice that says so.
- A format that keeps its packages outside a folder tree - npm, PyPI, NuGet and their kind - has no folders to
  show, so its releases are listed by coordinate instead, each opening its package's page.
- A package's page lists its versions with when each was published, whether it is pinned and its download count
  where downloads are counted. A version opens its own page: where it came from and whether it is served, the
  licences it declares, what its manifest says about it - description, keywords and authors - its signature and
  provenance, what it depends on, and the files it is served as.
- A version is the sum of its files. Its download count counts each download of one of its files, while a checksum or
  a signature fetched beside a file counts nothing. Its signature is the weakest among its files' - a signed jar
  beside an unsigned POM makes an unsigned version - while each file keeps its own, which the file's page shows. A
  RubyGems gem built for a platform, such as `1.16.0-x86_64-linux`, is a version of its own.
- The columns sort by name, type and size.
- **Search** answers in one of two ways, and the search bar says which:
  - **By name**, unless the repository keeps a full-text index: a package is looked up by the start of its
    coordinate - `org.acme` finds `org.acme:widget`, `left` finds `left-pad` - as typed or in lower case, a page at a
    time. A file no coordinate names, such as a raw upload, is looked up the same way by the start of the path the
    repository serves it at: `installers/setup` finds `installers/setup-1.0.bin`. An RPM is named by its yum repository
    first, as its address reads, so `el9/nginx` finds it. Nothing is built or stored for it.
  - **Full text**, where the repository's **Full-text search** setting is on: its names, descriptions, keywords and
    authors, from an index a background pass keeps current. Something published moments ago is found by name
    before the next pass reaches it.

  Full-text search is off unless a repository asks for it, in the new-repository wizard or its settings. It can feel
  like an essential feature, but many repositories rarely use it - people look up the artifacts they know by name,
  or follow up what the gate held - so weigh it against what the index costs to build and keep. `GET /api/search`
  says which way it answered (`mode`, and `indexed` for whether the index served the page), takes a `limit`, and
  carries a `nextCursor` exactly when more remain; `jenrepo search` prints the mode beside the hits.
- An artifact's page shows its size, checksum, the coordinate and version its format read from it, the gate's
  verdict, its signature and provenance where it has them, and - for an artifact fetched from upstream - where
  it came from.

An artifact the gate is holding for review is not listed; it is on the **Quarantine** page instead, described
in [Screening what comes in](/repository/screening/).

A script walks the same tree one folder at a time. `GET /api/browse/children?repo=<name>&prefix=<path>` answers a
folder's children - each with its path, whether it is a folder, and its size - up to 200 at once (`limit`, at most
1 000), and a `next` value to pass back as `after` while the folder holds more; the command line pages it with
`jenrepo browse children <repo> [prefix]`.

## Staging

A staging upload holds a set of files back from the repository until you decide. A client publishes under a
staging id of its choosing - to `/staging/<tenant>/<repository>/<id>/` followed by the path it would otherwise
publish to within the repository - instead of straight to the release path:

```bash
curl -H "Jenesis-Repository-Key: $KEY" -T app-1.0.jar \
  http://localhost:8080/staging/releases/libraries/rc1/maven/com/example/app/1.0/app-1.0.jar
```

Nothing staged is resolvable. **Staging** lists the open ids with how many files each holds, and each has two
buttons: **promote** publishes everything staged under the id as one release, and **drop** discards it. Both need
the editor role, and a dropped id is gone for good.

A script does the same through the repository's operations, which name the repository in `?repo=` and take a key
that may read it (to list) or write to it (to promote or drop):

```bash
curl -H "Jenesis-Repository-Key: $KEY" 'http://localhost:8080/api/repository/staging?repo=libraries'
curl -X POST -H "Jenesis-Repository-Key: $KEY" \
  'http://localhost:8080/api/repository/staging/rc1/promote?repo=libraries'
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
