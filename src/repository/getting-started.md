---
order: 2
title: Getting started
description: Run Jenesis Repository from source against a folder on disk, configure it the Spring Boot way, publish and resolve a Maven artifact, open the console, and see the alternatives - a container image built from the clone, and the cloud stores.
---

This chapter takes you from nothing to a running repository. You start the server from its source against a
folder on disk, learn how every setting reaches it, publish a Maven artifact and resolve it back, and open the
web console. Everything later in this section assumes only what is here.

## Prerequisites

You need **a JDK, version 25 or newer**. The server is itself a Jenesis build, so it launches straight from
source with the JVM - no daemon, no build to install. To try publishing you also want `mvn` on your path.

```bash
java --version      # must report 25 or above
```

## Run it from source

Clone the project with its submodule - the build tool is pinned under `build/upstream` and `build/jenesis`
links into it - and start the server. It is the `source/bundle` module: one launchable
module that carries every format, every storage backend, the import connectors and the web console.

```bash
git clone --recurse-submodules https://github.com/jenesis/jenesis-repository.git
cd jenesis-repository
JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

The first run builds the modules it needs, then starts the server on **port 8080**, and serves the web console
on the same port. The **filesystem store is the default** backend, and its root is the one thing it needs:
without `JENREG_FILESYSTEM_ROOT` the server refuses to start and names the key, rather than inventing a folder
that vanishes with a container. That folder is the whole repository: artifacts, checksums, indexes and
settings all live there, and backing it up backs up the server.

<div class="note">
  <code>Execute.java</code> is the build tool's runner: it builds the named module's subtree and launches its
  declared main class. The <a href="/tool/building-and-running/">build tool section</a> covers it; here you only
  need the one command.
</div>

## How configuration reaches the server

The server is a Spring Boot application, and every setting is a `jenreg.*` property that Spring Boot binds
the usual ways. Pick whichever suits where the server runs - they are all the same property:

| Form | Example | Typical use |
| --- | --- | --- |
| Environment variable | `JENREG_STORE=s3` | Containers and systemd units; dots become underscores, upper-cased |
| System property | `-Djenreg.store=s3` before `build/jenesis/Execute.java` | A one-off run from the command line |
| Properties file | `jenreg.store=s3` in `bundle.properties` in the working directory, or its `config/` subfolder | A deployment that keeps its settings in a file |
| Spring profile | `SPRING_PROFILES_ACTIVE=dev` | Switching a named set of settings on, such as the local-login profile below |

Two conventions cover most of what you will set. `jenreg.<feature>=false` switches a discovered module off as
if it were not installed - `JENREG_MAVEN=false` drops the Maven layout, `JENREG_OCI=false` the registry.
`jenreg.<choice>=<name>` selects among alternatives - `JENREG_STORE=s3` picks the S3 backend instead of the
filesystem. Everything on the module path is on until you configure it off.

<div class="warning">
  The server reads <code>bundle.properties</code>, not <code>application.properties</code>, so
  that the server and the console can share one module path. Name a settings file accordingly.
</div>

## A first local run, open

The server **enforces key-based authentication by default**: every request must carry a valid repository key,
and a request without one is refused. For a local trial the quickest route is to switch enforcement off:

```bash
JENREG_AUTH=false JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

Running open is never silent. The server logs a warning at boot and reports the `jenreg.auth.open` advisory at
`GET /api/posture`, so an open deployment says so wherever an operator looks. It is the right setting for a
laptop or a trusted network. The rest of this chapter assumes it, so that `mvn` needs no credentials.

For anything reachable from outside, keep enforcement on and start from a **bootstrap key** instead: set
`JENREG_BOOTSTRAP_KEY` to a key of your choosing, and the server provisions it at boot with every right, so
you can issue the keys your clients will use through `/api/credentials`. *Authentication & access* walks
through it, including how to generate a well-formed key.

<div class="tip">
  An empty repository is hard to judge. Add <code>-Djenreg.demo=true</code> and the server seeds itself in the
  background with a few real, harmless releases pulled from the public registries - Maven Central for the
  Maven layout. It needs outbound network access, and it refuses a repository that already holds anything, so
  it can never touch a real one.
</div>

## Let it proxy Maven Central

Nothing is proxied until you name an upstream. One setting per format turns pull-through on; for the Maven
layout:

```bash
JENREG_AUTH=false JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
JENREG_PROXY_MAVEN=https://repo1.maven.org/maven2/ \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

With that set, a request for an artifact the server does not hold is fetched from Central, stored, and served
- and every later request is a local hit. One URL then serves both your own artifacts and everything on
Central, so a build needs only one repository entry. *Proxying* covers revalidation and the negative cache.

## Publish a Maven artifact

The Maven layout is served under **`/repository/maven/`**, a drop-in Maven repository URL for publishing and
resolving alike. Point a project's `distributionManagement` at it:

```xml
<distributionManagement>
  <repository>
    <id>jenesis</id>
    <url>http://localhost:8080/repository/maven/</url>
  </repository>
</distributionManagement>
```

With authentication off no credentials are needed, so deploy as usual:

```bash
mvn deploy
```

The server stores the jar, the POM and the checksums exactly as Maven uploaded them. A `maven-metadata.xml`
is stored and served back verbatim. If the jar is a Java module - it carries a `module-info` or an
`Automatic-Module-Name` - the server also **publishes it into the module layout** under its module name, so a
Jenesis build can resolve it by `requires` with no extra step.

## Resolve it

Resolving uses the same URL as a `<repository>`. Any Maven or Gradle build can now pull your artifact, and
whatever it proxies:

```xml
<repository>
  <id>jenesis</id>
  <url>http://localhost:8080/repository/maven/</url>
</repository>
```

A Jenesis build needs no new client. It points both of its repositories at the server, the Maven one for
`pom.xml` projects and the module one for `requires` resolution:

```bash
java -Djenesis.maven.uri=http://localhost:8080/repository/maven/ \
     -Djenesis.module.uri=http://localhost:8080/repository/ \
     -Djenesis.repository.insecure=true \
     build/jenesis/Make.java
```

On an enforcing server add `-Djenesis.maven.token=jenk_…` (and `-Djenesis.module.token=jenk_…`): the build
sends the key in the `Authorization` header, which the server accepts like its own.
`jenesis.repository.insecure` is needed only because this is plain `http://` on localhost; a build refuses a
plaintext repository otherwise. The *[Dependencies](/tool/dependencies/)* chapter of the build tool explains
both settings and their environment-variable forms.

## Open the console

The web console is served by the same process: open `http://localhost:8080/console`. With an identity
provider configured it signs you in through that provider; for a first look without one, restart the server
with the `dev` profile, which adds a form login with two built-in accounts:

```bash
SPRING_PROFILES_ACTIVE=dev JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

Open `http://localhost:8080/login/dev` and sign in as `admin` / `admin` (an admin) or `viewer` / `viewer`
(a user). The `dev` profile also lets the session cookie travel over plain HTTP, which it has to do to survive
a sign-in without TLS - that is the profile's business and there is no switch for it, because a deployment has
no reason to want session hardening off.

<div class="warning">
  The <code>dev</code> profile is for a laptop: the server refuses to start under it on anything but the
  loopback address, so the built-in accounts never reach a network. A real deployment signs in over GitHub
  or an OpenID Connect provider, configured in <em>The console</em>.
</div>

## The alternatives

**A container image, built from the clone.** If you would rather run a container than a JDK, the build writes
a complete Docker context for the bundle module - a `Dockerfile` on the `eclipse-temurin:25-jdk` base
beside the `modulepath/` and `classpath/` folders it copies in, starting the same main class the source run
does. Stage it, then build and run the image:

```bash
java -Djenesis.test.skip=true build/jenesis/Make.java stage
docker build -t jenesis-repository:free 'target/stage/docker/output/module-source%2Fbundle'
docker run -p 8080:8080 -e JENREG_AUTH=false -e JENREG_FILESYSTEM_ROOT=/data \
  -v jenesis-data:/data jenesis-repository:free
```

Every setting above applies unchanged, because the image is shaped with `-e` rather than rebuilt. It declares
no volume and no store root of its own, so you name the root and mount a volume there, as you did from source.
`-Djenesis.test.skip=true` leaves the test suite out of the staging run; [Packaging](/tool/packaging/) in the
build tool section describes the context the build writes.

**A cloud store instead of a folder.** The filesystem is the default, but the server runs the same on an
object store, which is how you run it stateless and behind a load balancer. You select the backend and give
it a bucket:

| Store | Select with | Then set |
| --- | --- | --- |
| A directory | `JENREG_STORE=filesystem` *(default)* | `JENREG_FILESYSTEM_ROOT` *(required)* |
| S3, or an S3-compatible service such as MinIO | `JENREG_STORE=s3` | `JENREG_S3_BUCKET`, credentials, an endpoint for a compatible service |
| Google Cloud Storage | `JENREG_STORE=gcs` | `JENREG_GCS_BUCKET` |
| Azure Blob Storage | `JENREG_STORE=azure-blob` | the connection string and container |

*Storage* covers each backend, its credentials, and the storage quota, and *What it costs to run* says what
each request costs a store that charges per operation.

## Where to go next

You now have a running repository that proxies Central, holds an artifact of your own, and shows it in the
console. *Architecture* explains the plugin model behind it in a few pages; after that, each chapter covers
one capability - storage, formats, proxying, access, import, observability and the console - with its
settings at the end, and the *Configuration reference* lists every setting in one place.
