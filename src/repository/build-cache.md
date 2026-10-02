---
order: 9
title: The build cache
description: The remote build cache the repository keeps for the Jenesis build tool, Gradle, Maven and Bazel - creating a project for one build tool with its settings, granting a key access to it, pointing each build tool at it, and keeping its size in check.
---

The server keeps a **remote build cache** beside its repositories, for the [Jenesis build tool](/tool/), Gradle,
Maven (through the Maven Build Cache Extension) and Bazel. A build that finds a step's result in the cache downloads
it instead of running the step, so work done once - on a colleague's machine, in an earlier CI job - is not done
again. It is on in every image; a deployment that does not need it switches it off with
`JENREPO_BUILD_CACHE=false`. The cache answers on the same port, authorises with the same keys, and is looked after
in the console under **Build cache**.

Each tenant has a cache of its own, at `/build/<tenant>/` - `/build/releases/` on a deployment that serves the
`releases` tenant. A key reaches its own tenant's cache and no other: a request naming another tenant's cache is
answered `403`.

## Projects

The cache is divided into **projects**. A project is one build tool's cache - `gradle`, `maven`, `bazel` or
`jenesis`, whichever the deployment serves - with its own size limits, and a key reaches only the projects it is
granted. So two teams, or a trusted main branch and untrusted pull requests, need not share results.

**Build cache → Current projects** lists the projects with the build tool and description of each, how many entries
it holds, how much space they take and when they were last counted; the filter above it matches a name, a build
tool or a description. **New project** opens a wizard: the project's name - letters, digits and underscores - its
build tool and an optional description, then its size cap and how long an unused entry is kept, then a review.
**Create project** creates it with those settings at once; a value left blank inherits the tenant's and the
deployment's.

A project answers its own build tool and no other: a request from another tool's endpoint is answered `404`, as if
the project did not exist. A project a build creates by pushing to a name nobody created takes the type of the
first tool that stores in it; reading types nothing. A project's page shows its build tool, and an editor changes
its description in place, with the pencil beside it.

A script creates one the same way, with its type, description and settings beside it, and changes the description
later:

```bash
curl -X POST -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"description":"Main branch builds","settings":{"project-size":"10737418240","project-ttl":"P30D"}}' \
  'https://repo.example.com/api/cache/projects?name=my_project&type=gradle'
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"description":"Release builds"}' https://repo.example.com/api/cache/projects/my_project/description
jenrepo projects create my_project gradle "Main branch builds" --set project-size=10737418240 --set project-ttl=P30D
jenrepo projects describe my_project "Release builds"
```

A type the deployment does not serve, or a name that is taken, is refused with `400` and nothing is created. An
empty description clears it.

## Granting a key access

A build presents a key, like any other client. Open the key under **Access → Credentials**, and under **Grants**
enter the project's name as the scope - or `*` for every project - with the role:

| Role | Lets a build |
| --- | --- |
| **read-only** | Download cached results, but never store any - the right role for untrusted builds. |
| **deploy** | Download and store. |

## Pointing a build at it

Each build tool speaks its own protocol, at its own address under the tenant's cache, and each names the project and
presents the key its own way. **Build cache → Build tools** lists every tool with its address for the tenant you are in,
`jenrepo capabilities` prints the same list, and `GET /api/capabilities` answers it as `cacheProtocols`.

| Build tool | Address | Project and key |
| --- | --- | --- |
| Jenesis | `/build/<tenant>` | headers, or the environment |
| Gradle | `/build/<tenant>/gradle/` | the user name and password of its credentials |
| Maven | `/build/<tenant>/maven/<project>` | the project in the address, the key as a server's password |
| Bazel | `/build/<tenant>/bazel` | the user name and password in the address |

### Jenesis

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

### Gradle

In `settings.gradle`, the project is the user name and the key the password:

```groovy
buildCache {
    remote(HttpBuildCache) {
        url = 'https://repo.example.com/build/releases/gradle/'
        push = true                                   // false for a build that should only read
        credentials { username = 'my_project'; password = System.getenv('JENESIS_KEY') }
    }
}
```

`gradle --build-cache build` then reports a step it took from the cache as `FROM-CACHE`.

### Maven

The [Maven Build Cache Extension](https://maven.apache.org/extensions/maven-build-cache-extension/) is switched on in
`.mvn/extensions.xml`, and pointed at the project's address in `.mvn/maven-build-cache-config.xml`:

```xml
<cache xmlns="http://maven.apache.org/BUILD-CACHE-CONFIG/1.0.0">
  <configuration>
    <enabled>true</enabled>
    <remote enabled="true" saveToRemote="true" id="jenesis">
      <url>https://repo.example.com/build/releases/maven/my_project</url>
    </remote>
  </configuration>
</cache>
```

The key is the password of the server entry with the same id in `~/.m2/settings.xml`; the user name is not checked.
A warm build reports `Skipping plugin execution (cached)` for each goal it restored.

### Bazel

Bazel takes the cache as one URL, so the project and the key ride in it as its user name and password:

```bash
bazel build --remote_cache=https://my_project:$KEY@repo.example.com/build/releases/bazel //...
```

The key is then in the command line and in Bazel's own logs, so a CI job reads it from a secret into the flag,
or puts the flag in a `.bazelrc` the job writes and discards. A warm build reports `remote cache hit`.

## Keeping its size in check

Each project's page carries its settings, the three a project has of its own:

| Setting | Effect |
| --- | --- |
| **Size cap** (`project-size`) | The most the project's entries may take together, in bytes; past it the least recently used are evicted. `0` is no cap. |
| **Unused-entry lifetime** (`project-ttl`) | Entries nobody has read or written for this long are removed, as a duration (`P30D`, `30d`); `none` keeps them for ever. |
| **Evict least recently used first** (`project-lru`) | Which entries go first when the cap is reached; switched off, the most recently used go first. |

Like any setting, each is inherited until the project sets its own: the deployment and a tenant can set a default
for every project, and **Reset to default** returns a project to it. The cache enforces them as it runs. A script changes them
with `jenrepo projects settings <project> set <key> <value>`, or under
`/api/cache/projects/<name>/settings/<key>`.

Under **Eviction**, three buttons act at once, in the background: **Enforce size cap now**, **Expire stale entries
now**, and **Clear all entries**, which empties the project; each asks first. **Count entries now** refreshes the
figures at the top of the page.

**Delete project**, at the bottom of a project's page, removes every cached entry and the project's settings,
in the background, after asking you to type the project's name; it is an admin's to press. A key's grant naming the
project stays, and reaches a project created again under that name - so revoke the grants first, or a build still
writing to it brings it back. A script does the same with `DELETE /api/cache/projects/<name>`.

**Build cache → Cache volume**, a super-administrator's page, shows the free space of the disk the cache lives on
against the target it keeps free, and a reclaim that sweeps the least recently used entries across every tenant's
projects until the target is met.

<div class="note">
  A cached result is only ever a shortcut: a build that finds nothing, or finds an entry evicted a moment ago,
  runs the step itself. Evicting, clearing or deleting a project never breaks a build - it only makes the next one
  slower.
</div>
