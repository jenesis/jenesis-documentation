---
order: 13
title: Build performance & isolation
description: Confine the build and the program it launches inside a throwaway Docker container, and share step outputs across builds, machines, and CI through the build cache.
---

Two engine capabilities that need no change to your project: **isolation** puts the whole build - or just the
program it launches - inside a throwaway container, so untrusted code cannot reach your host; and the **build
cache** hands a step the output of an earlier build instead of re-running it. Both switch on from the command
line, so any project gains them for free.

## Why isolate a build

A build runs untrusted code even when you customise nothing. The stock pipeline compiles and runs your
**tests** - and everything the test dependencies drag in - and the artifact it produces has a **`main`** that
runs later, all with the full rights of whoever started the build. A single compromised dependency (a malicious
release, a hijacked account, a typo-squatted coordinate) executes with those same rights.

[Pinning](/tool/pinning/) guarantees you get the exact bytes you vetted rather than a silently swapped
artifact - but it guarantees *what* runs, not that what runs is safe. Docker addresses the other half: it
confines what that code can reach when it executes, so even a malicious dependency cannot read your host secrets
or write outside the sandbox.

<div class="note">
  The engine itself is trusted separately: a standard Jenesis project carries no build logic to execute - it is
  described declaratively - so an untrusted project can be built by the trusted, SDK-installed <code>jenesis</code>
  (see <a href="/tool/getting-started/">Getting started</a>). The Docker flags below confine the remaining
  untrusted code: the dependencies, the tests, and the artifact's <code>main</code>.
</div>

## Running the build in a container

Set `-Djenesis.project.docker=true` to run the entire build inside a throwaway container instead of directly on
the host JVM:

```bash
java -Djenesis.project.docker=true build/jenesis/Project.java
```

A minimal image is built on demand the first time and cached for later runs. Inside the container neither
your home directory nor the host environment is present, so a test or dependency that reaches for
`~/.aws/credentials` or a CI secret finds nothing.

To target a different image, add `-Djenesis.project.docker.image=<reference>`. The implicit image runs with
`--cap-drop ALL` and `--security-opt no-new-privileges`; a named image is run as you named it, without those
two flags, so harden it in the image itself if you swap it.

### What is mounted automatically

Every location the project is configured with is represented inside the container, almost all of them **at
their host path** so that paths resolve identically:

- the **project root** - writable;
- the **JDK** - read-only, at `/opt/java-home`, so the same Java runs inside;
- the local **Maven and module repositories** (`~/.m2`, `~/.jenesis`) - read-only, with
  `MAVEN_REPOSITORY_LOCAL` / `JENESIS_REPOSITORY_LOCAL` forwarded so the in-container JVM finds them despite
  its different home;
- out-of-root `target` / `artifacts` locations - writable;
- out-of-root configuration, BOM, and `jenesis.project.metadata` folders - read-only;
- an out-of-root [`jenesis.project.cache`](#the-build-cache) or `file://` `jenesis.cache.uri` cache - writable,
  created on the host first so it is not left root-owned.

Anything else the build needs from outside the root is **invisible** inside the container.

### Adding mounts and environment

A `build/jenesis` symlinked to a shared engine checkout, a sibling source tree, or a generated-sources directory
lives outside the root and so is not present. Add such paths with
`-Djenesis.project.docker.mount=<host>[:<container>],...`:

- a bare `host` is mounted at the **same** path inside the container (`host:host`) - what a symlink or absolute
  reference needs to resolve; `host:container` remaps it instead;
- these mounts are **read-only** - the build should not write outside its own tree;
- relative host paths resolve against the project root, and several mounts are comma-separated.

For the rare case that the build must write to a host path outside the project root, use
`-Djenesis.project.docker.mountWritable=<host>[:<container>],...`. Reach for it sparingly: every writable mount
is a hole in the confinement.

By default **no host environment is forwarded** into the container. Pass selected variables with
`-Djenesis.project.docker.env=<name>[=<value>],...`: a bare `name` forwards the host's current value, while
`name=value` sets it explicitly. This is the channel for a build input that legitimately lives in the
environment - a private-repository token, a proxy setting - and is opt-in so ambient host secrets do not leak in
by default.

<div class="warning">
  The local Maven and module repositories (<code>~/.m2</code>, <code>~/.jenesis</code>) are mounted
  <strong>read-only</strong>. So dependencies must already be cached - warm the cache with a host build first -
  and <code>export</code> fails with an <code>AccessDeniedException</code>, since publishing writes into those
  repositories. Staging works inside the container (<code>stage</code> only writes under <code>target/</code>);
  run <code>export</code> on the host.
</div>

## Running the launched program in a container

Isolating the build does not isolate the program it produces, whose `main` runs later with the same host rights.
`Execute.java` (see *[Building & running](/tool/building-and-running/)*) can launch that program inside a
container too, **independently** of whether the build itself was dockerised:

```bash
java -Djenesis.execute.docker=true build/jenesis/Execute.java
```

The container does not receive the host environment and its home is not the host's, so the artifact runs but the
secrets are out of reach. `-Djenesis.execute.docker.image=<reference>` overrides the image, and
`-Djenesis.execute.docker.mount` (read-only), `-Djenesis.execute.docker.mountWritable` (read-write), and
`-Djenesis.execute.docker.env=<name>[=<value>],...` behave exactly like their `jenesis.project.docker.*`
counterparts. Because the build runs as usual and only the launch crosses the container boundary, the **build
image and the runtime image can differ**.

<div class="note">
  Running a build or program in a container needs a Docker daemon on the machine that runs the build.
  <code>jenesis.print.docker</code> is on by default and prints the image the JVM is wrapped in; set it
  <code>false</code> to suppress.
</div>

## <span id="the-build-cache">The build cache</span>

Every build already has an *incremental* cache: Jenesis content-hashes each step's inputs and outputs under
`target/`, so a warm rebuild only re-runs the steps whose inputs changed (see
*[Core concepts](/tool/core-concepts/)*). The **build cache** adds a second tier *outside* `target/` that can
hand a step the output of an earlier build - a different checkout, machine, or CI job - instead of re-running it
at all. It lives in two places that compose: a project-local folder and a shared location you name.

### A project-local cache

The simplest form needs only a flag. Jenesis keeps a content-addressed cache under `.jenesis/cache`, rooted at
the project root:

```bash
java -Djenesis.project.cache build/jenesis/Project.java
```

The value is a **filesystem path** (never a URI): an empty value, as above, resolves to `.jenesis/cache` under
the project root, and a value relocates it. Each entry lives at `.jenesis/cache/<step-hash>/<inputs-hash>/`,
where the step hash identifies the step by its **serialised form** and the inputs hash folds every input
file's content hash. On a miss the build runs the step and stores the result. On a hit it materialises the
cached output - hard-linked, so near free - and the step body never runs. Because it sits outside `target/`,
it survives a `target/` wipe.

That survival is the point. `-Djenesis.executor.rebuild=true` deletes `target/` first, so the incremental
cache is gone and *every* step is a forced miss that would normally re-run from scratch. The build cache
serves them anyway:

```bash
java -Djenesis.project.cache \
     -Djenesis.executor.rebuild=true \
     build/jenesis/Project.java
```

The steps still print `[EXECUTED]` - their output *was* produced - but it came from the cache, not from `javac`,
so each returns almost instantly. On a real module a compile that took seconds returns at once. Add
`-Djenesis.print.cache` to make it explicit: each step served from the cache prints a `[LOADED]` line and each
written to it a `[STORED]` line. Delete `.jenesis/cache` to start over.

### A shared cache

`.jenesis/cache` is private to one checkout. To share results across checkouts, machines, or CI, name an
explicit location with `-Djenesis.cache.uri=`. The value is a URI:

```bash
-Djenesis.cache.uri=https://cache.example.com       # a cache server
-Djenesis.cache.uri=file:///mnt/team/jenesis-cache  # a shared (or local) folder
```

A `file://` URI resolves the same on-disk format as the local cache. An `http(s)://` URL selects an HTTP
backend that GETs and PUTs the same entries to a cache server, naming the project with
`-Djenesis.cache.project=<project>` and authenticating with `-Djenesis.cache.key=<key>`. Both are sent as
**headers, never in the URL**, and both fall back to the `JENESIS_CACHE_PROJECT` / `JENESIS_CACHE_KEY`
environment variables. `-Djenesis.cache.connect` and `-Djenesis.cache.read` set the HTTP timeouts as ISO-8601
durations (`PT1S` and `PT10S` by default). A non-URI value is rejected; use `file://` for an on-disk
location.

The shared cache can be used two ways:

- **As a replacement** - the shared cache only, no local tier. Fitting for an ephemeral CI runner whose disk is
  thrown away anyway: pass `jenesis.cache.uri` alone.
- **Layered behind the local cache** - set both `-Djenesis.project.cache` *and* `-Djenesis.cache.uri=...`. Every
  read tries `.jenesis/cache` first and falls through to the shared cache only on a miss. A shared hit is
  copied into the local cache on the way past, so the next read is local, and a store writes through to both.

```bash
java -Djenesis.project.cache \
     -Djenesis.cache.uri=https://cache.example.com \
     -Djenesis.cache.project=acme -Djenesis.cache.key=alice \
     build/jenesis/Project.java
```

<div class="note">
  Serving a step from the local tier means no <code>GET</code> reaches the server, which would let that shared
  entry age toward eviction even while in active use. So a local hit also sends the server a best-effort
  <code>HEAD</code>, never the body, and the server treats it as a read and bumps the entry's recency. Each
  tier keeps its own LRU and both stay warm.
</div>

### Tuning with `cache.properties`

Drop an optional `cache.properties` at the cache root - `.jenesis/cache/cache.properties` for the project-local
cache, or `<folder>/cache.properties` for a file-system shared one - to tune the writes. Every key has a default,
so the file may be omitted entirely:

| key | default | effect |
| --- | --- | --- |
| `digest` | `SHA-256` | algorithm folding the inputs into the entry-folder name |
| `steps` | `250` | maximum number of step folders kept |
| `versions` | `10` | maximum input-variants kept per step |
| `size` | unset | maximum total bytes; over it, whole entries are evicted by `lru` until under (unset = no cap) |
| `lru` | `true` | evict the least-recently-updated entry when over a limit (`false` = most-recently) |
| `touch` | `true` | bump an entry's timestamp on read, so reads keep hot entries alive |
| `ttl` | unset | ISO-8601 duration (e.g. `P30D`); entries not touched within it are evicted on a background sweep |
| `compressed` | `false` | store each entry as a single zip file rather than a folder of files |
| `read` | `true` | serve cache reads; `read=false` makes every lookup a miss |
| `write` | `true` | populate the cache; `write=false` serves reads but never writes, evicts, or touches |

Eviction runs on write and goes by file timestamp, which `touch` keeps fresh on every read - so the three caps
(`steps`, `versions`, `size`) approximate an LRU, and `ttl` adds an age dimension on top of them.

<div class="tip">
  <code>read</code> and <code>write</code> are the typical CI split: a privileged job builds with the defaults
  (both <code>true</code>) to <strong>populate</strong> the cache, while everyone else sets
  <code>write=false</code> to <strong>consume</strong> it read-only without mutating it. Setting both
  <code>false</code> turns the cache off entirely.
</div>

<div class="tip">
  Two runnable projects cover this chapter:
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-42-docker-isolation">demo-42</a> leaks a
  credentials file and an environment secret on the host, then confines both the build and the launched program
  with Docker, and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-46-build-cache">demo-46</a> serves a forced full
  rebuild entirely from the build cache. See <a href="/tool/demos/">Demos</a>.
</div>
