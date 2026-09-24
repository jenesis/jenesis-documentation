---
order: 9
title: The build cache
description: The remote build cache the repository keeps for the Jenesis build tool - creating a project, granting a key access to it, pointing a build at it, and keeping its size in check.
---

Beside its repositories, the server keeps a **remote build cache** for the [Jenesis build tool](/tool/). A build
that finds a step's result in the cache downloads it instead of running the step, so work done once - on a
colleague's machine, in an earlier CI job - is not done again. The cache answers at `/cache/` on the same port,
authorises with the same keys, and is looked after in the console under **Build cache**.

## Projects

The cache is divided into **projects**. A project is a separate space of cached results, with its own size limits,
and a key reaches only the projects it is granted - so two teams, or a trusted main branch and untrusted pull
requests, need not share results.

**Build cache → Projects** lists the projects with how many entries each holds, how much space they take and when
they were last counted. Under **New project**, give it a name and press **Create project**.

## Granting a key access

A build presents a key, like any other client. Open the key under **Access → Credentials**, and under **Project
grants** enter the project's name - or `*` for every project - with the role:

| Role | Lets a build |
| --- | --- |
| **read-only** | Download cached results, but never store any - the right role for untrusted builds. |
| **deploy** | Download and store. |

## Pointing a build at it

Give the Jenesis build tool the cache's address, the project and the key:

```bash
java -Djenesis.cache.uri=https://repo.example.com/cache \
     -Djenesis.cache.project=my_project \
     -Djenesis.cache.key="$KEY" \
     build/jenesis/Make.java
```

The project and the key travel as headers, never in the URL, and both can come from the environment instead -
`JENESIS_CACHE_PROJECT` and `JENESIS_CACHE_KEY` - which is the usual way in CI. The build tool's chapter on
[build performance](/tool/build-performance-and-isolation/) covers the rest of the client side: layering the
remote cache behind the local one, and timeouts.

## Keeping its size in check

Each project's page carries its **Cache settings**:

| Setting | Effect |
| --- | --- |
| **Size cap** | The most the project may hold, in bytes; blank is no cap. |
| **Eviction order** | Which entries go first when the cap is reached - least recently used, or most recently used. |
| **TTL** | Entries not used for this long are removed, as an ISO-8601 duration (`P30D`, `PT12H`); blank keeps them. |

The cache enforces them as it runs. Under **Eviction**, three buttons act at once, in the background: **Enforce
size cap now**, **Expire stale (ttl) now**, and **Clear all entries**, which empties the project. **Count entries
now** refreshes the figures at the top of the page.

<div class="note">
  A cached result is only ever a shortcut: a build that finds nothing, or finds an entry evicted a moment ago,
  runs the step itself. Evicting or clearing a project never breaks a build - it only makes the next one slower.
</div>
