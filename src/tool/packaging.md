---
order: 13
title: Packaging
description: Turn a project into something you can ship and run - application images, jlink runtimes, bundles, launcher jars, container build contexts, and native images.
---

A plain build stops at jars. **Packaging** turns those jars into something a user can run without a Java
project in front of them: a self-contained application image, a trimmed runtime, a zip to drop onto a JRE, a
single executable jar, a container image, or an ahead-of-time-compiled native binary. Each form answers the
same question differently - *how much of the runtime travels with the program* - and this chapter walks
through the options.

Every form is **opt-in** and driven by convention, not a build script. You name it in a
`packaging.properties` file in the [configuration folder](/tool/configuration/), and it runs for every module
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
  As with every configuration file, the first folder that carries one wins. A module's own
  <code>build.jenesis/</code> packages that module alone, while a project-wide file packages them all. The
  <code>jmod</code> step joins the module's own build; every other key adds a step to the
  <strong>package phase</strong>, which runs after every module has built, so packaging never blocks a
  sibling's compile.
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

Every packaging step keys off that one declaration and skips a module that has none. A library needs no
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
java build/jenesis/Make.java stage
```

The `--name`, `--main-jar`/`--main-class` (or `--module`) arguments are derived from the module's coordinate
and main class. The `stage` target collects each produced image under `stage/packages/`, the staging analogue
of `stage/maven` and `stage/modular`, in a folder named for the module it came from:

```
target/stage/packages/output/demo.modular.executable/   the image jpackage produced
|-- bin/demo.modular.executable   # the launcher
`-- lib/   # app jars + bundled runtime
```

The image bundles the whole runtime *closure*, not just your own code: a dependency your app uses sits next
to the application jar. Because the image is self-contained, a deployable container needs no JDK, only a
minimal base:

```dockerfile
FROM debian:stable-slim
COPY target/stage/packages/output/demo.modular.executable /opt/app
ENTRYPOINT ["/opt/app/bin/demo.modular.executable"]
```

<div class="tip">
  jpackage links the bundled runtime from <strong>the very JDK that compiled the code and ran the tests</strong>.
  The app ships on exactly the JVM it was built and verified against, not whatever patch version a base image
  happens to provide.
</div>

### Modular images are smaller

How big the image is depends on the layout. A **modular** project lets jpackage run `jlink` internally and
trim the bundled runtime to just the modules the graph resolves. A **class-path** (Maven-layout) project
cannot be trimmed, so it ships a full runtime.

<div class="note">
  Measured with Temurin 25.0.3, a modular app-image is about 57&nbsp;MB against about 138&nbsp;MB for the
  class-path sibling. The gap is almost entirely the JVM: <code>java.base</code> alone links to ~60&nbsp;MB
  and a full JDK is ~303&nbsp;MB.
</div>

### Passing jpackage its own flags

jpackage has flags of its own - an icon, a vendor, a description, a licence file. They go in a
`process-jpackage.properties` file in the configuration folder, one flag per line, exactly as
*[Building & running](/tool/building-and-running/)* described for `javac`:

```properties
# build.jenesis/process-jpackage.properties
--vendor=Example Ltd
--icon=branding/app.png
```

`process-jlink.properties`, `process-jmod.properties` and `process-native-image.properties` do the same for
the tools below. One flag is derived for you: `--app-version` comes from `jenesis.project.version` with any
non-numeric suffix stripped, because jpackage accepts only dotted numbers - `1.4.0-SNAPSHOT` becomes `1.4.0`.

{% demos 7, 8 %}

## Native installers

The other `jpackage` values build a **native installer** - the single artifact you hand a user to install,
rather than a directory to launch in place. The value is passed straight to `jpackage --type`:

| Value | Platform |
| --- | --- |
| `deb`, `rpm` | Linux |
| `exe`, `msi` | Windows |
| `dmg`, `pkg` | macOS |

An installer carries the whole bundled runtime, so it is tens of megabytes. Producing one needs the platform's
own packaging tooling on the `PATH`: `dpkg-deb`/`fakeroot` for `deb` and `rpmbuild` for `rpm` on Linux, the
WiX Toolset on Windows, the bundled `productbuild`/`hdiutil` on macOS. For that reason an installer is usually
built locally, while the tooling-free `app-image` covers the packaging path in CI.

{% demos 7, 8 %}

## Runtime images and `.jmod` files

Two modular-only keys expose the lower-level artifacts that jpackage builds internally. Both need *modules*, so
a class-path project has nothing to link or pack.

`jlink=true` links a **custom runtime image** holding only the modules your app needs, staged under
`stage/runtime`. It runs straight from its own `bin/java` with no JDK installed:

```bash
target/stage/runtime/output/module-sources/bin/java \
    -m demo.modular.executable/sample.Sample Ada Lovelace
```

The folder under `output/` is the module's build identity rather than its name: `module` for a module whose
descriptor sits at the project root, `module-<folder>` otherwise - `module-sources` for a module under
`sources/`. The `docker` context below uses the same naming.

`jmod=true` packs the module into a **`.jmod`**, staged beside the modular jar. It holds everything the jar holds -
the classes, the resources and the embedded [SBOM](/tool/supply-chain/) - so a runtime linked from it serves the
same resources. Its one advantage over a jar is
that it can carry native libraries, commands, config files and legal notices, which `jlink` then lays into the
runtime's `lib/`, `bin/`, `conf/` and `legal/`. The three steps chain - `jmod → jlink → jpackage` - so a config file packed this
way reaches the shipped app, where the program reads it from `<java.home>/conf/`. Packed into a jar instead,
it would be stranded there.

<div class="warning">
  <code>jlink</code> links <strong>explicit modules only</strong>. Every jar it links must carry a
  <code>module-info</code>, or be a <code>.jmod</code>. A plain jar - and an automatic module, which declares
  no <code>requires</code> of its own - is rejected with "automatic module cannot be used with jlink". With
  <code>jlink=true</code> beside it, <code>jpackage</code> is handed that linked runtime and inherits the rule.
  On its own, <code>jpackage</code> stages the jars as its module path and roots the whole path instead, as
  the bundle section below describes. The next section is how a closure of plain jars becomes one
  <code>jlink</code> accepts.
</div>

{% demos 8, 53 %}

## Making a closure linkable

A dependency that ships as a plain jar - or that you gave a name with a
[module alias](/tool/dependencies/) - is an automatic module, and `jlink` will not take one. A
`modules.properties` file in the configuration folder closes that gap by turning the module's whole resolved
closure into **explicit named modules**:

```properties
# build.jenesis/modules.properties
mode=declared
```

An empty file means the same thing, since `declared` is the default. Every jar that already declares a
`module-info` passes through untouched. For the rest, `jdeps` works out what each one actually reads and a
generated `module-info` is injected into a copy of it.

The rewritten closure then *replaces* the resolved one for everything the module builds: `javac`, the tests,
and every packaging step. A module graph that does not hold together - a split package, two jars claiming
one name, a `requires` nothing provides - fails at compile or test time instead of first appearing in the
shipped image.

The `mode` key decides what happens to a jar with no name of its own to carry: `declared` fails the build and
names the coordinate, `synthetic` invents a stable name derived from the jar's digest, and `none` skips the
rewrite - which is how a single module opts out of a project-wide file.

<div class="note">
  Nothing that describes what you <em>fetched</em> is affected. The bill of materials, the licence and
  vulnerability checks, and the closure <code>pin</code> records all keep reading the artifacts as they were
  downloaded, so a rewritten jar's bytes can never reach a <code>@jenesis.pin</code> checksum.
</div>

{% demos 19 %}

## Bundles for a JRE base

`jpackage` bundles a runtime into every image. The lighter alternative is to ship **only your jars** onto an
off-the-shelf JRE base. `bundle=true` wires a step that writes one `bundle.zip` per runnable module:

```
bundle.zip
|-- application.unix.args   # the launch, as a Java argument file
|-- application.windows.args   # the same launch, with Windows path separators
`-- jars/   # every jar of the closure, stored once
```

The zip carries exactly the runtime closure the `Execute` launcher would run, and the descriptor is not a
description of that launch but the launch itself - a Java argument file, which every JVM already
understands:

```
"--module-path"
"jars/classes.jar:jars/org.slf4j-2.0.16.jar"
"--module"
"demo.bundle/sample.Sample"
```

So a deployment runs it without a reader or a parser of its own:

```bash
cd <unpacked> && java @application.unix.args
```

Every path is spelled out rather than handed over as a folder, so a jar is read because the argument file
names it, not because of where it sits - and since the whole command lives in a file, no closure is too large
to launch. The [module layers](/tool/dependencies/#keeping-a-dependency-private) a project declares are in
there too, each as a `-Djlayer.modulepath.<layer>`. There are two files because the path separator is the one
part of a launch a bundle cannot know in advance. Dropped onto a `-jre` base it needs no JDK and no jpackage.

The trade against an app-image is the classic one. An app-image is self-contained but duplicates the JVM per
service. A bundle is tiny and shares one JVM layer across every image built on the same base - leaner in
aggregate for many services, at the cost of coupling to that base's JVM version.

<div class="note">
  <strong>Why <code>--add-modules</code> sometimes appears.</strong> A module graph is self-contained when
  every jar on the module path is an explicit named module, so the launcher reaches all of them through the
  main module's <code>requires</code>. An automatic module, a plain jar, or a module layer holding either
  breaks that, because a module used only internally is never pulled in. The build detects this and writes
  <code>--add-modules ALL-MODULE-PATH,ALL-DEFAULT</code> into the launch, rooting the whole module path and
  the default platform modules. jpackage, the container context and the native image apply the same
  correction; you never splice it in yourself.
</div>

{% demos 9 %}

## A container build context

Writing that `Dockerfile` around a bundle by hand is the one step the build can do for you. The `docker` key
takes the base image - the one thing no build can infer - and stages a complete build context:

```properties
# build.jenesis/packaging.properties
docker=eclipse-temurin:25-jre
```

```bash
java build/jenesis/Make.java stage
docker build -t sample target/stage/docker/output/module-sources
```

The staged folder holds a generated `Dockerfile` beside the `jars/` folder it copies in and the argument
file its `ENTRYPOINT` names:

```dockerfile
FROM eclipse-temurin:25-jre
WORKDIR /app
COPY jars/ /app/jars/
COPY application.args /app/
ENTRYPOINT ["java", "@/app/application.args"]
```

The entry point is the same one every other packaging form reads, so a container can never drift from what
the app image or the launcher jar starts, and it stays this size however many jars the application resolves.
When the module graph is not self-contained, the argument file carries the same
`--add-modules=ALL-MODULE-PATH,ALL-DEFAULT` correction.

The base image is the only knob, and deliberately so: `ENV`, `USER`, `EXPOSE` and the rest are inherited from
the base, so image environment belongs in a base image rather than in build configuration.

<div class="note">
  The build never invokes a container tool - it writes files - so producing the context needs no Docker
  installation at all. Nothing in the generated file is Docker-specific: <code>podman build</code> and
  <code>buildah bud</code> consume the same folder.
</div>

{% demos 7, 8 %}

## A single executable jar

`launcher=true` produces a **single executable jar** you run with `java -jar app.jar`, without flattening
dependencies into a fat jar. The build shades the published Jenesis Launcher into the jar as its `Main-Class`
and explodes each dependency into its own `jars/<jar>/` subfolder, with an `application.properties` naming
which of them each path holds. At run time the launcher rebuilds the module graph from those subfolders in
process, so `module-info`s and `META-INF/services` never collide.

Unlike jpackage and bundle, this carries no JVM and no `jlink` runtime. It is a plain jar that runs on any
JDK 25 or newer, and unlike a bundle it needs no launch script. The shaded launcher is
[pinned](/tool/pinning/) like any other dependency, in its own `launcher` group, so the exact bytes are
verified and the build stays reproducible.

<div class="tip">
  The launcher jar has its own section - see
  <a href="/launcher/">Jenesis Launcher</a> for how it reconstructs the module layer, the jar layout, and
  troubleshooting.
</div>

{% demos 7, 8 %}

## Native images

`native=true` compiles the application ahead of time into a **single standalone native executable** with
GraalVM `native-image`: a binary that starts in milliseconds and carries no Java runtime, because the runtime
it needs is linked into the binary itself. The `stage` target collects it under `stage/native`, and you run it
directly, with no `java` in the command:

```bash
target/stage/native/output/demo.graal.image Ada
```

Native compilation needs GraalVM. The tool is located through `GRAALVM_HOME`, then the running JDK's own
`bin/`, then `PATH`, so either run the build on a GraalVM JDK or point `GRAALVM_HOME` at one:

```bash
GRAALVM_HOME=~/.sdkman/candidates/java/25.0.3-graal java build/jenesis/Make.java stage
```

### Reachability metadata, captured from tests

`native-image`'s closed-world analysis cannot see reflection, JNI, resources, or proxies, so it needs
**reachability metadata** for anything dynamic. Jenesis captures that automatically: drop a `graal.properties`
marker file in the configuration folder and its presence attaches GraalVM's tracing agent to the test run.
The agent records every dynamic access the tests trigger, and the native build picks it up directly. A
single build both captures the metadata and compiles the image, with no committed `META-INF/native-image/`
directory to maintain.

<div class="warning">
  The capture is only as complete as your tests. If a reflective path is never exercised, its metadata is
  never recorded and the binary fails at run time with <code>ClassNotFoundException</code>. You can still commit
  metadata by hand under <code>sources/META-INF/native-image/</code>, which <code>native-image</code> discovers
  inside every jar - the way to vet exactly what reflection is baked into a published artifact.
</div>

{% demos 66 %}

### native-image or jpackage?

Both turn a modular app into something a user runs without a JDK, but they differ in kind. **jpackage** ships
your bytecode plus a trimmed JVM: normal startup, tens of megabytes, no extra tooling. **native-image**
compiles the program *and* its runtime into machine code: near-instant startup and a small binary, at the cost
of GraalVM, a slow compile, and complete reachability metadata. They are alternatives, not a progression.
Choose jpackage for a faithful bundle of the JVM you tested against, and native-image when startup and
footprint matter more.

## Licences in each form

A shipped program carries the code of its dependencies, and with it their licences and notices. How each form
passes them on follows from how it holds the jars:

| Form | Where the licences travel |
| --- | --- |
| Module jar | It holds your own code only. Its licence text is placed with `jenesis.project.resources` (see *[Supply-chain features](/tool/supply-chain/#the-licence-text-in-the-jar)*), and the embedded SBOM names the licence of every dependency. |
| Bundle | Every jar of the closure is stored intact under `jars/`, so each dependency's licence files travel inside its own jar. |
| Launcher jar | Each jar is unpacked under a prefix of its own, `jars/<jar>/`, and nothing is merged, so every jar keeps its files. The launcher's own `META-INF/LICENSE` and `META-INF/NOTICE` sit at the root beside its classes. |
| Container build context | The jars are copied intact into `jars/` beside the `Dockerfile`. |
| Class-path application image | The jars stay intact in the image's application folder (`lib/app/` on Linux), and the runtime jpackage links carries the JDK's own notices in its `legal/` folder. |
| Runtime image, modular application image | Linking takes the code out of the jars, so the notices are collected into the module's `.jmod` and laid into the runtime under `legal/<module>/`: the module's own at its root, and each runtime dependency's in a folder named after its jar. |
| Native image | The jars are compiled away, so the same notices go into a `licenses/` folder beside the binary, staged in `stage/native/output/`. The binary also contains the GraalVM that compiled it, so that GraalVM's licence and notice files join them in `licenses/graalvm-<version>/`. |

Linking always goes through the module's `.jmod`, so a runtime keeps the notices however it is configured:
without `jmod=true`, `jlink` and a modular `jpackage` build the `.jmod` for linking alone and do not stage it.
The runtime of the `java-modular-executable` demo, which redistributes `org.slf4j`, carries that library's
licence:

```
target/stage/runtime/output/module-sources/legal/demo.modular.executable/
`-- org.slf4j-2.0.16/LICENSE.txt
```

`jenesis.legal.notices` names the jar entries taken as notices, comma-separated. The default is
`META-INF/NOTICE,META-INF/LICENSE,META-INF/license/,META-INF/licenses/,LICENSE,about.html`. A name matches
regardless of case and also with an extension, so `META-INF/LICENSE.txt` counts, and an entry ending in `/`
takes the whole folder below it.

<div class="warning">
  A dependency whose jar carries no licence file cannot contribute one, and many jars carry none: such a jar
  adds nothing to <code>legal/</code>, so check its licence before shipping it.
</div>

{% demos 8, 19, 66 %}
