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

`jenesis.make.root` belongs on the command line only, because the root is what locates the file in the first
place. Setting it in a file is reported as an error.

A project may name the repositories it resolves from, with `jenesis.maven.uri`, `jenesis.module.uri` and
`jenesis.openpgp.uri`. A token never follows it there: `jenesis.maven.token` and `jenesis.module.token` go
only to a repository named in the environment, on the command line or in your user-global file. A folder a
project's file names, such as `jenesis.project.target`, must lie inside the project, because the build writes
to it and may wipe it. On the command line it can name any folder.

The same goes for the few keys that describe your own environment rather than the project. They would make no
sense in a project's file anyway, and a rogue project could use them to reach beyond its own build. The
project's file and its profiles refuse them; the command line and your user-global file, described below,
accept them.

Keys fall into namespaces, each grouping one concern: `jenesis.test.*` for tests, `jenesis.maven.*` and
`jenesis.module.*` for the two kinds of repository, and so on. `jenesis.make.*` covers starting a build:
where the project is, which profiles to layer, where the user-global file lives, and how the engine itself is
compiled and reused. `jenesis.project.*` covers the project as a whole, such as its version and where its
output goes. The [reference](/tool/reference/) lists every namespace and its keys.

<div class="note">
  Every boolean setting reads the same way. Leaving the key out keeps the default; naming it with no value at
  all - <code>-Djenesis.test.skip</code>, or a bare <code>jenesis.test.skip=</code> in a file - is
  <code>true</code>; <code>=true</code> and <code>=false</code> mean what they say. Any other value is
  refused, naming the key and what would have been valid, so a typo stops the build instead of quietly
  reading as off.
</div>

## A whole run, in a file

A `jenesis.properties` file carries what every build of the project should do. A run that is not every build
- a release, a nightly, the one incantation nobody remembers - can be written down as well, as an **argument
file** the command line names with `@`:

```
# release.args
-Djenesis.project.version=1.0.0
-Djenesis.make.profiles=release
stage
```

```bash
java build/jenesis/Make.java @release.args
```

`@<file>` stands for the arguments the file holds, settings and selectors alike, one or more per line. A `#`
starts a comment that runs to the end of the line, quotes hold what would otherwise split on whitespace, and
`@@<text>` is an argument that begins with an `@` rather than a file. A file names no further file, so what
you read is what runs. This is the argument file the JDK's own tools read, and `jpx` and the `jenesis` and
`jenesis-exec` commands read it the same way.

Settings in such a file are command-line settings: they win over `jenesis.properties` and over a profile,
exactly as a typed `-D` does. That is possible because a setting may also *follow* the main class, ahead of
the selectors:

```bash
java build/jenesis/Make.java -Djenesis.project.version=1.0.0 build
```

Only `jenesis.*` settings may be written there; any other `-D` is refused, naming what would be valid,
because a JVM option has to reach the JVM and therefore belongs before the main class.

{% demos 45 %}

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

<div class="note">
  A <code>pin-&lt;name&gt;.properties</code> bill of materials is not searched for in a profile subfolder. It
  is looked up only in the locations <code>jenesis.project.boms</code> names, which default to the
  configuration folders themselves, so a project's pinned versions stay where the project put them.
</div>

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

{% demos 45 %}

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
