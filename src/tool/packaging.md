---
order: 11
title: Packaging
description: Turn a project into something you can ship and run - application images, jlink runtimes, bundles, launcher jars, container build contexts, and native images.
---

A plain build stops at jars. **Packaging** turns those jars into something a user can run without a Java
project in front of them: a self-contained application image, a trimmed runtime, a zip to drop onto a JRE, a
single executable jar, a container image, or an ahead-of-time-compiled native binary. Each form answers the
same question differently - *how much of the runtime travels with the program* - and this chapter is the menu.

Every form is **opt-in** and driven by convention, not a build script: you name it in a
`packaging.properties` file in the [configuration location](/tool/configuration/), and it runs for every module
that declares a main class.

| Key in `packaging.properties` | Produces |
| --- | --- |
| `jpackage=app-image` \| `deb` \| `rpm` \| `dmg` \| `pkg` \| `exe` \| `msi` | a self-contained application image or a native installer |
| `jlink=true` | a custom runtime image (modular only) |
| `jmod=true` | a `.jmod` module file (modular only) |
| `bundle=true` | a `bundle.zip` to drop onto a stock JRE |
| `launcher=true` | a single executable jar |
| `docker=<base image>` | a container build context - a `Dockerfile` and the jars it copies |
| `native=true` | a GraalVM native binary |

<div class="note">
  As with every configuration file, the first location that carries one wins - so a module's own
  <code>build.jenesis/</code> packages that module alone, while a project-wide file packages them all. What
  each key switches on is a step in the <strong>package phase</strong>, which runs after every module has
  built, so packaging never blocks a sibling's compile.
</div>

## What makes a module packageable

Only one thing: a declared entry point. It is the same `@jenesis.main` tag - or `<mainClass>` property - that
[`Execute`](/tool/building-and-running/) already launches a module with:

```java
/**
 * @jenesis.main sample.Sample
 */
module demo.modular.executable {
    exports sample;
}
```

Every packaging step keys off that one declaration, and skips a module that has none. So a library needs no
packaging configuration to be left alone, and an application needs no packaging-specific entry point.

## The application image

`jpackage=app-image` produces a **self-contained application image**: a native launcher with its own bundled
Java runtime, so a user runs it without installing a JDK. It is the only jpackage type that needs no
platform-native tooling, which makes it the CI-friendly choice.

```properties
# build.jenesis/packaging.properties
jpackage=app-image
```

```bash
java build/jenesis/Project.java stage
```

The `--name`, `--main-jar`/`--main-class` (or `--module`) arguments are derived automatically from the
module's coordinate and main class. The `stage` target collects each produced image into `stage/packages/`,
the staging analogue of `stage/maven` and `stage/modular`, under a folder named for the module it came from -
so a project that packages several applications never mixes two of them:

```
target/stage/packages/output/demo.modular.executable/   the module's own folder
`-- demo.modular.executable/                            the image jpackage produced
    |-- bin/demo.modular.executable                     the launcher
    `-- lib/                                            app jars + bundled runtime
```

The image bundles the whole runtime *closure*, not just your own code - a dependency your app uses is bundled
next to the application jar. Because the image is self-contained, a deployable container needs no JDK, only a
minimal base:

```dockerfile
FROM debian:stable-slim
COPY target/stage/packages/output/demo.modular.executable/demo.modular.executable /opt/app
ENTRYPOINT ["/opt/app/bin/demo.modular.executable"]
```

<div class="tip">
  jpackage links the bundled runtime from <strong>the very JDK that compiled the code and ran the tests</strong>,
  so the app ships on exactly the same JVM it was built and verified against - not whatever patch version a
  base image happens to provide.
</div>

### Modular images are smaller

How big the image is depends on the layout. A **modular** project lets jpackage run `jlink` internally and
trim the bundled runtime to just the modules the graph resolves; a **classpath** (Maven-layout) project cannot
be trimmed, so it ships a full runtime.

<div class="note">
  Measured with Temurin 25.0.3, a modular app-image is about 57&nbsp;MB against about 138&nbsp;MB for the
  classpath sibling - a gap that is almost entirely the JVM, since <code>java.base</code> alone links to
  ~60&nbsp;MB and a full JDK is ~303&nbsp;MB.
</div>

## Native installers

The other `jpackage` values build a **native installer** - the single artifact you hand a user to install,
rather than a directory to launch in place. The value is passed straight to `jpackage --type`:

| Value | Platform |
| --- | --- |
| `deb`, `rpm` | Linux |
| `exe`, `msi` | Windows |
| `dmg`, `pkg` | macOS |

An installer carries the whole bundled runtime, so it is tens of megabytes. Producing one needs the platform's
own packaging tooling on the `PATH` (Linux: `dpkg-deb`/`fakeroot` for `deb`, `rpmbuild` for `rpm`; Windows: the
WiX Toolset; macOS: the bundled `productbuild`/`hdiutil`). For that reason an installer is usually built
locally, while the tooling-free `app-image` covers the packaging path in CI.

## Runtime images and `.jmod` files

Two modular-only keys expose the lower-level artifacts that jpackage builds internally. Both need *modules*, so
a classpath project has nothing to link or pack.

`jlink=true` links a **custom runtime image** holding only the modules your app needs, staged under
`stage/runtime`. It runs straight from its own `bin/java` with no JDK installed:

```bash
target/stage/runtime/output/demo.modular.executable/bin/java \
    -m demo.modular.executable/sample.Sample Ada Lovelace
```

`jmod=true` packs the module into a **`.jmod`**, staged beside the modular jar. Its one advantage over a jar is
that it can carry native libraries, commands, and config files, which `jlink` then lays into the runtime's
`lib/`, `bin/`, and `conf/`. The three steps chain - `jmod → jlink → jpackage` - so a config file packed this
way reaches the shipped app, where the program reads it from `<java.home>/conf/`; packed into a jar instead, it
would be stranded there.

<div class="warning">
  <code>jlink</code> links <strong>explicit modules only</strong>. Every jar it links must carry a
  <code>module-info</code>, or be a <code>.jmod</code>; a plain jar - and an automatic module, which declares
  no <code>requires</code> of its own - is rejected with "automatic modules cannot be used with jlink".
  <code>jpackage</code>, which calls <code>jlink</code> under the hood, inherits the same rule. The next
  section is how a closure of plain jars becomes one <code>jlink</code> accepts.
</div>

## Making a closure linkable

A dependency that ships as a plain jar - or that you gave a name with a
[module alias](/tool/dependencies/) - is an automatic module, and `jlink` will not take one. A
`modules.properties` file in the [configuration location](/tool/configuration/) closes that gap by turning the
module's whole resolved closure into **explicit named modules**:

```properties
# build.jenesis/modules.properties
mode=declared
```

An empty file means the same thing, since `declared` is the default. Every jar that already declares a
`module-info` passes through untouched; for the rest, `jdeps` works out what each one actually reads and a
generated `module-info` is injected into a copy of it.

The rewritten closure then *replaces* the resolved one for everything the module builds - `javac`, the tests,
and every packaging step. That is the point rather than a side effect: a module graph that does not hold
together - a split package, two jars claiming one name, a `requires` nothing provides - then fails at compile
or test time instead of first appearing in the shipped image.

The `mode` key decides what happens to a jar with no name of its own to carry: `declared` fails the build and
names the coordinate, `synthetic` invents a stable name derived from the jar's digest, and `none` skips the
rewrite - which is how a single module opts out of a project-wide file.

<div class="note">
  Nothing that describes what you <em>fetched</em> is affected. The bill of materials, the licence and
  vulnerability checks, and the closure <code>pin</code> records all keep reading the artifacts as they were
  downloaded - so a rewritten jar's bytes can never reach a <code>@jenesis.pin</code> checksum.
</div>

## Bundles for a JRE base

`jpackage` bundles a runtime into every image. The lighter alternative is to ship **only your jars** onto an
off-the-shelf JRE base. `bundle=true` wires a step that writes one `bundle.zip` per runnable module:

```
bundle.zip
|-- application.properties     mainClass=sample.Sample, mainModule=demo.bundle, selfContainedModuleGraph=true
|-- modulepath/                jars that are modules (the app jar and its module dependencies)
`-- classpath/                 any non-modular (plain) jars
```

The zip carries exactly the runtime closure the `Execute` launcher would run, split the same way: real and
automatic modules under `modulepath/`, plain jars under `classpath/`. The `application.properties` describes
the launch - `mainClass` (always), `mainModule` (only for a modular launcher), and `selfContainedModuleGraph`.
Dropped onto a `-jre` base it needs no JDK and no jpackage - it is the input a container image, an
init-script, or any other deployment builds around.

The trade against an app-image is the classic one: an app-image is self-contained but duplicates the JVM per
service, while a bundle is tiny and shares one JVM layer across every image built on the same base - leaner in
aggregate for many services, at the cost of coupling to that base's JVM version.

<div class="note">
  <strong>What <code>selfContainedModuleGraph</code> means.</strong> A module graph is self-contained when
  every jar on the module path is an explicit named module, so the launcher reaches all of them through the
  main module's <code>requires</code>. An automatic module or a plain jar breaks that, because a module it
  uses only internally is never pulled in - so the launcher is given
  <code>--add-modules ALL-MODULE-PATH</code> to root the whole path instead. The build detects this and
  applies it for you, here and in jpackage and native images alike; the flag only tells a bundle's consumer
  which case they are in.
</div>

## A container build context

Writing that `Dockerfile` around a bundle by hand is the one step the build can do for you. The `docker` key
takes the base image - the one thing no build can infer - and stages a complete build context:

```properties
# build.jenesis/packaging.properties
docker=eclipse-temurin:25-jre
```

```bash
java build/jenesis/Project.java stage
docker build -t sample target/stage/docker/output/demo.modular.executable
```

The staged folder holds a generated `Dockerfile` beside the `modulepath/` and `classpath/` folders it copies
in, split exactly the way a bundle splits them. Its `ENTRYPOINT` is the same entry point every other packaging
form reads, so a container can never drift from what the app image or the launcher jar starts - and when the
module graph is not self-contained, it carries the same `--add-modules ALL-MODULE-PATH` correction.

The base image is the only knob, and deliberately so: `ENV`, `USER`, `EXPOSE` and the rest are inherited from
the base, so image environment belongs in a base image rather than in build configuration.

<div class="note">
  The build never invokes a container tool - it writes files - so producing the context needs no Docker
  installation at all, and nothing in the generated file is Docker-specific: <code>podman build</code> and
  <code>buildah bud</code> consume the same folder.
</div>

## A single executable jar

`launcher=true` produces a **single executable jar** you run with `java -jar app.jar`, without flattening
dependencies into a fat jar. The build shades the published Jenesis Launcher into the jar as its `Main-Class`
and explodes each dependency into its own `classpath/<jar>/` or `modulepath/<jar>/` subfolder. At run time the
launcher rebuilds the module graph from those subfolders in process, so `module-info`s and `META-INF/services`
never collide.

Unlike jpackage and bundle, this carries no JVM and no `jlink` runtime - it is a plain jar that runs on any
JDK 25, and unlike a bundle it needs no launch script. The shaded launcher is [pinned](/tool/pinning/)
like any other dependency, in its own `launcher` group, so the exact bytes are verified and the build stays
reproducible.

<div class="tip">
  The launcher jar has its own section - see
  <a href="/launcher/">Jenesis Launcher</a> for how it reconstructs the module layer, the jar layout, and
  troubleshooting.
</div>

## Native images

`native=true` compiles the application ahead of time into a **single standalone native executable** with
GraalVM `native-image` - a binary that starts in milliseconds and carries no Java runtime, because the runtime
it needs is linked into the binary itself. The `stage` target collects it into `stage/native`, and you run it
directly, with no `java` in the command:

```bash
target/stage/native/output/demo.graal.image/demo.graal.image Ada
```

Native compilation needs GraalVM. The tool is located through `GRAALVM_HOME`, then the running JDK's own
`bin/`, then `PATH`, so either run the build on a GraalVM JDK or point `GRAALVM_HOME` at one:

```bash
GRAALVM_HOME=~/.sdkman/candidates/java/25.0.3-graal java build/jenesis/Project.java stage
```

### Reachability metadata, captured from tests

`native-image`'s closed-world analysis cannot see reflection, JNI, resources, or proxies, so it needs
**reachability metadata** for anything dynamic. Jenesis captures that automatically: drop a `graal.properties`
marker file in the configuration location and its presence attaches GraalVM's tracing agent to the test run.
The agent records every dynamic access the tests trigger, and the native build picks it up directly - so a
single build both captures the metadata and compiles the image, with no committed `META-INF/native-image/`
directory to maintain.

<div class="warning">
  The capture is only as complete as your tests. If a reflective path is never exercised, its metadata is
  never recorded and the binary fails at run time with <code>ClassNotFoundException</code>. You can still commit
  metadata by hand under <code>sources/META-INF/native-image/</code>, which <code>native-image</code> discovers
  inside every jar - the way to vet exactly what reflection is baked into a published artifact.
</div>

### native-image or jpackage?

Both turn a modular app into something a user runs without a JDK, but they differ in kind. **jpackage** ships
your bytecode plus a trimmed JVM: normal startup, tens of megabytes, no extra tooling. **native-image**
compiles the program *and* its runtime into machine code: near-instant startup and a small binary, at the cost
of GraalVM, a slow compile, and complete reachability metadata. They are alternatives, not a progression -
jpackage for a faithful bundle of the JVM you tested against, native-image when startup and footprint matter
more.

<div class="tip">
  Five runnable projects cover this chapter:
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-05-java-pom-executable">demo-05</a> and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-06-java-modular-executable">demo-06</a> ship
  the whole menu from one project each - an app image, a native installer, a bundle, a launcher jar, and a
  container context (and, for the modular one, a <code>.jmod</code> and a jlink runtime);
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-07-bundle">demo-07</a> unpacks a bundle and
  runs it on a stock JRE;
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-35-custom-jmod">demo-35</a> packs extra
  content into a <code>.jmod</code> and carries it through jlink into a jpackage image;
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-31-module-alias">demo-31</a> makes an
  unlinkable closure linkable with a <code>modules.properties</code>; and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-44-native-image">demo-44</a> builds a GraalVM
  native image end to end. See <a href="/tool/demos/">Demos</a>.
</div>
