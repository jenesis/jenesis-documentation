---
order: 9
title: The build cache
description: The optional remote build cache the repository can keep for the Jenesis build tool - creating a project with its settings, granting a key access to it, pointing a build at it, and keeping its size in check.
---

If you build with the [Jenesis build tool](/tool/), the server can keep a **remote build cache** for it beside its
repositories. A build that finds a step's result in the cache downloads it instead of running the step, so work
done once - on a colleague's machine, in an earlier CI job - is not done again. A deployment that does not need
it switches it off with `JENREPO_BUILD_CACHE=false`. The cache answers on the same port, authorises with
the same keys, and is looked after in the console under **Build cache**.

Each tenant has a cache of its own, at `/build/<tenant>/` - `/build/releases/` on a deployment that serves the
`releases` tenant. A key reaches its own tenant's cache and no other: a request naming another tenant's cache is
answered `403`.

## Projects

The cache is divided into **projects**. A project is a separate space of cached results, with its own size limits,
and a key reaches only the projects it is granted - so two teams, or a trusted main branch and untrusted pull
requests, need not share results.

**Build cache → Projects** lists the projects with how many entries each holds, how much space they take and when
they were last counted. **New project** opens a wizard: the project's name - letters, digits and underscores - then
its size cap and how long an unused entry is kept, then a review. **Create project** creates it with those settings
at once; a value left blank inherits the tenant's and the deployment's.

A script creates one the same way, with its settings beside it:

```bash
curl -X POST -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"settings":{"project-size":"10737418240","project-ttl":"P30D"}}' \
  'https://repo.example.com/api/cache/projects?name=my_project'
jenrepo projects create my_project --set project-size=10737418240 --set project-ttl=P30D
```

## Granting a key access

A build presents a key, like any other client. Open the key under **Access → Credentials**, and under **Grants**
enter the project's name as the scope - or `*` for every project - with the role:

| Role | Lets a build |
| --- | --- |
| **read-only** | Download cached results, but never store any - the right role for untrusted builds. |
| **deploy** | Download and store. |

## Pointing a build at it

Give the Jenesis build tool the tenant's cache as its address, with the project and the key:

```bash
java -Djenesis.cache.uri=https://repo.example.com/build/releases \
     -Djenesis.cache.project=my_project \
     -Djenesis.cache.key="$KEY" \
     build/jenesis/Make.java
```

The build tool appends each result's address - the step and the digest of its inputs, `/<step>/<inputs>` - to
that URL. The project and the key travel as headers (`Jenesis-Cache-Project` and `Jenesis-Cache-Key`), never in
the URL, and both can come from the environment instead -
`JENESIS_CACHE_PROJECT` and `JENESIS_CACHE_KEY` - which is the usual way in CI. The build tool's chapter on
[build performance](/tool/build-performance-and-isolation/) covers the rest of the client side: layering the
remote cache behind the local one, and timeouts.

## Keeping its size in check

Each project's page carries its settings, the three a project has of its own:

| Setting | Effect |
| --- | --- |
| **Size cap** (`project-size`) | The most the project's entries may take together, in bytes; past it the least recently used are evicted. `0` is no cap. |
| **Unused-entry lifetime** (`project-ttl`) | Entries nobody has read or written for this long are removed, as a duration (`P30D`, `30d`); `none` keeps them for ever. |
| **Evict least recently used first** (`project-lru`) | Which entries go first when the cap is reached; switched off, the most recently used go first. Folded under **Advanced**. |

Like any setting, each is inherited until the project sets its own: the deployment and a tenant can set a default
for every project, and **Revert** returns a project to it. The cache enforces them as it runs. A script changes them
with `jenrepo projects settings <project> set <key> <value>`, or under
`/api/cache/projects/<name>/settings/<key>`.

Under **Eviction**, three buttons act at once, in the background: **Enforce size cap now**, **Expire stale entries
now**, and **Clear all entries**, which empties the project; each asks first. **Count entries now** refreshes the
figures at the top of the page.

**Delete project**, at the bottom of a project's page, removes every cached entry and the project's settings,
in the background, after asking you to type the project's name; it is an admin's to press. A key's grant naming the
project stays, and reaches a project created again under that name - so revoke the grants first, or a build still
writing to it brings it back. A script does the same with `DELETE /api/cache/projects/<name>`.

Below the projects, a super-administrator sees the **Cache volume**: the free space of the disk the cache lives on
against the target it keeps free, and a reclaim that sweeps the least recently used entries across every tenant's
projects until the target is met.

<div class="note">
  A cached result is only ever a shortcut: a build that finds nothing, or finds an entry evicted a moment ago,
  runs the step itself. Evicting, clearing or deleting a project never breaks a build - it only makes the next one
  slower.
</div>
