---
order: 4
title: Configuration
description: Setting build properties in a project file, where per-module tool configuration lives, and how profiles and precedence let you switch a whole setup with one name.
---

Earlier chapters flipped knobs with `-Djenesis.*` flags on the command line. That is fine for a one-off, but
you do not want to type the same flags on every build, and different builds (development versus release)
need different sets. This chapter shows where configuration lives so a project carries its own defaults: the
`jenesis.properties` file, the folders that hold each tool's configuration, **profiles** that switch a named
set of both at once, and the precedence rule that decides who wins.

## System properties, in a file

Every knob you have met is a system property. `jenesis.project.layout`, `jenesis.test.skip`,
`jenesis.project.target` - anything you can pass with `-D`. The same properties can live in a
**`jenesis.properties`** file at the project root, so the project carries its own defaults without a wrapper
script:

```properties
# jenesis.properties  (project root)
jenesis.project.layout=modular_to_maven
jenesis.project.sources=true
```

The file is read *before* the build is configured, so it drives everything the command line does: layout,
target, pinning, every later decision. The file is optional. An explicit `-D` on the command line always
overrides a file entry, so you can still override the project's baseline for a single run:

```bash
java -Djenesis.project.sources=false build/jenesis/Make.java
```

A project's file is what a clone brings with it, so it does not set everything. These are reported as an
error there and in the project's profiles, and belong on the command line or in your user-global file:

| Refused in a project's files | Why |
| --- | --- |
| any key outside `jenesis.*` | it would configure the JVM that runs the whole build, such as a proxy or a trust store |
| `jenesis.make.root`, `jenesis.make.global` | the root locates the file, and the user-global folder decides which of your settings apply; both are command-line only |
| `jenesis.daemon.options`, `jenesis.openpgp.command`, `jenesis.jreleaser.executable`, `jenesis.toolchain.searchpath`, `jenesis.toolchain.installer`, every `jenesis.jarsigner.*` | they name a program the build runs, the options a JVM runs it with, or the signing key it reaches for |
| `jenesis.maven.*`, `jenesis.module.*`, `jenesis.cache.uri`, `jenesis.cache.key`, `jenesis.sigstore.*`, `jenesis.repository.insecure`, `jenesis.cache.insecure` | they decide where the build fetches from, what it trusts, and where this machine's credentials travel |
| the `jenesis.project.docker.*` and `jenesis.execute.docker.*` mounts, environment and image | they decide what a containerized build reaches on this machine, which is the point of containing it |

A project's file also names only folders inside the project for `jenesis.project.target`,
`jenesis.project.artifacts`, `jenesis.project.cache`, `jenesis.make.classes`, `jenesis.pin.file` and
`jenesis.openpgp.local`, because the build writes to them and wipes some of them. On the command line they
name any folder.

Keys fall into two namespaces, split by who reads them. `jenesis.make.*` is read by the entry point, before a
build exists: where the project is, which profiles to layer, where the user-global file lives, and how the
engine itself is compiled and reused. `jenesis.toolchain.*` is read there too, to choose the JDK the build
runs on. `jenesis.project.*` is read by the build. That is why the root sits
under `make` - finding the project is the entry point's job, and the build is handed the answer rather than
looking it up.

<div class="note">
  Every boolean setting reads the same way. Leaving the key out keeps the default; naming it with no value at
  all - <code>-Djenesis.test.skip</code>, or a bare <code>jenesis.test.skip=</code> in a file - is
  <code>true</code>; <code>=true</code> and <code>=false</code> mean what they say. Any other value is
  refused, naming the key and what would have been valid, so a typo stops the build instead of quietly
  reading as off.
</div>

## Where tool configuration lives

System properties are the small knobs. A tool like Checkstyle or jpackage needs its own configuration *file*,
and those live in dedicated folders. A tool **activates on the presence of its file**: drop a `checkstyle.xml`
in and static analysis turns on; leave it out and it stays off. The folder is both the switch and the
settings.

Every lookup walks one ordered list of folders and the **first folder that carries the file wins**. The list
runs from the most specific per-module location to the project-wide fallback:

| Location | Layout | Scope |
| --- | --- | --- |
| `META-INF/build.jenesis/` under a module's sources | `modular`, `modular_to_maven` | that one module |
| `src/main/build.jenesis/` or `src/test/build.jenesis/` under the pom root | `maven` | the pom's main or test module alone |
| `build.jenesis/` next to the `pom.xml` | `maven` | both of the pom's modules |
| the `jenesis.project.configuration` folders (default `build.jenesis/` at the project root) | all | project-wide |

What these folders can hold - presence activates, contents configure:

- **Code quality**: `checkstyle.xml`, `pmd.xml`, `spotbugs-exclude.xml`, `detekt.yml`, `codenarc.xml`,
  `scalastyle-config.xml`, `errorprone.properties`.
- **Generated sources**: `xjc.properties`, `protoc.properties`, `avro.properties`, `wsimport.properties`,
  `openapi.properties`, `antlr.properties`.
- **Formatting**: `javaformat.properties`, `.editorconfig`, `.scalafmt.conf`.
- **Packaging and output**: `packaging.properties`, `modules.properties`, `sbom.properties`, `bom.properties`.
- **Compliance**: `licensing.properties`, `vulnerability.properties`, `spdx.properties`.
- **Test observability**: `jacoco.properties`, `graal.properties`, `pitest.properties`.
- **API compatibility**: `japicmp.properties`.
- **Forked-tool arguments**: `process-<command>.properties` - extra flags for `javac`, `kotlinc`, `jar`, and
  the like (see *[Building & running](/tool/building-and-running/)*).

<div class="note">
  One kind of file is looked up in its own list of locations rather than these: a
  <code>pin-&lt;name&gt;.properties</code> bill of materials, whose locations are named by
  <code>jenesis.project.boms</code> and default to the configuration folders above. They are deliberately
  <em>not</em> profile-resolved, so no profile can swap a project's pinned versions out from under it.
</div>

Each of these is the subject of a later chapter; here the point is only *where* they go and that a file's mere
presence switches its feature on.

<div class="warning">
  The bare project root is deliberately <strong>not</strong> a configuration folder. A conventionally named
  file an editor or a teammate drops at the root - an <code>.editorconfig</code>, a <code>checkstyle.xml</code>
  for the IDE - must not silently change the build. Configuration activates only from an explicit
  <code>build.jenesis/</code> folder (or a folder you opt into via <code>jenesis.project.configuration</code>).
</div>

## Profiles

A **profile** is a named set of configuration you switch on in one move - the development-versus-release split,
without repeating long `-D` lists. There is no registry and no plugin: a profile is just a name.

Select profiles with the `jenesis.make.profiles` property - a comma-separated list of names. Each name
`<name>` designates two things, both optional:

- a **`jenesis-<name>.properties`** file at the project root, whose entries feed the same `jenesis.*` system
  properties, and
- a **`<name>/` subfolder** inside each configuration folder, searched *ahead of* the folder itself - so a
  profile can carry its own `checkstyle.xml`, `packaging.properties`, and so on.

Profiles **chain**: any loaded file may itself set `jenesis.make.profiles` to pull in more, transitively.
The [`profiles`](https://github.com/jenesis/jenesis/tree/main/demo/demo-45-profiles) demo ships a `release`
profile that turns on source jars and chains to a `supply-chain` profile that enforces strict pinning:

```properties
# jenesis-release.properties
jenesis.project.sources=true
jenesis.make.profiles=supply-chain

# jenesis-supply-chain.properties
jenesis.dependency.pin=strict
```

Selecting `release` therefore also applies `supply-chain` - one name switches on both:

```bash
java -Djenesis.make.profiles=release build/jenesis/Make.java stage
```

A missing `jenesis-<name>.properties` is skipped, not an error, so a profile may contribute only a
configuration folder, only a properties file, or both.

## Precedence

With several layers in play, the rule is fixed. Configuration resolves in five tiers, **highest first**:

| Tier | Source |
| --- | --- |
| 1 | an explicit `-D` on the command line |
| 2 | the profiles selected by your user-global file (below) |
| 3 | your user-global `jenesis.properties` |
| 4 | the **profiles** selected for the project |
| 5 | the project `jenesis.properties` |

So `-Djenesis.project.sources=false` on a release build switches the source jar back off (the command line
always wins), selecting the `release` profile overrides whatever the project's base `jenesis.properties` set,
and a line in your own file overrides both, because what your machine settles applies to every project it
builds. The folder search follows the same spirit: a profile's `<name>/` folder beats a plain folder, and a
module-local folder beats a project-wide one.

When you are unsure what the layers add up to, ask the build. The `properties` selector prints every
effective `jenesis.*` property, sorted by key:

```bash
java -Djenesis.make.profiles=release build/jenesis/Make.java properties
```

## User-global defaults

A **user-global `jenesis.properties`**, read from `~/.jenesis/` and applied to *every* project, settles how
this machine builds. It outranks what a project sets, so a `jenesis.dependency.signature=strict` there holds
for every project you build, and only a `-D` overrides it. It is optional and ignored when absent, and it may
declare its own profiles, resolved relative to its `.jenesis` folder.

The `jenesis.make.global` property names the base folder (default `$HOME`) whose `.jenesis/` subfolder
holds that file. Set to an empty string, it switches the user-global layer off entirely. It is set on the
command line only: a project's `jenesis.properties`, a profile or the user-global file that sets it is refused,
so a project can never put a file of its own in the place of your personal defaults.

<div class="tip">
  The <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-45-profiles">demo-45</a> project is a
  complete, runnable example of everything here - a base build with no extras, and a <code>release</code>
  profile that chains to <code>supply-chain</code> to add source jars and strict pinning without changing a
  single command-line flag. See <a href="/tool/demos/">Demos</a>.
</div>
