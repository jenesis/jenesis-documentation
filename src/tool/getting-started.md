---
order: 2
title: Getting started
description: Install Jenesis, build a modular project end to end, and learn the settings and selectors every build is driven by.
---

This chapter takes you from nothing to a built project. You install Jenesis, run the canonical build
command against a project you write yourself, read what it printed, and meet the settings and selectors
every build is driven by. Everything later in this section assumes only what is here.

## Prerequisites

Jenesis needs **a JDK, version 25 or newer, and nothing else** - no wrapper, no plugin tree to download. A
build is an ordinary Java program that the JDK launches directly, so if `java --version` reports 25 or
above, you are ready. What a project carries is under two megabytes of readable Java, where a build tool
distributed as binaries is megabytes of compiled code downloaded from a server you do not control.

```bash
java --version
```

## Installing

A Jenesis build lives *with* your project: its engine ships as plain Java source under `build/jenesis/`, and
you launch it with the JVM's source file mode. Installing is really just populating that
`build/jenesis/` folder. Three ways do it, in order of how much they ask of you, and all land at the same
on-disk state - the canonical `java build/jenesis/Make.java` command works identically afterwards.

### curl bootstrap

Fastest, with no prerequisite beyond a JDK and `curl`. Run from your project root:

```bash
curl -fsSL https://get.jenesis.build | bash
java build/jenesis/Make.java
```

Set `JENESIS_VERSION=X.Y.Z` to pin a release, or pass a git ref to install an arbitrary tag, commit, or
branch: `curl -fsSL https://get.jenesis.build | bash -s -- main`.

### A package manager

Best when you would rather manage the tool version globally than vendor its sources by hand. Install once,
then initialise the project from the installed copy:

```bash
sdk install jenesis                # SDKMAN
brew install jenesis/tap/jenesis   # Homebrew
scoop bucket add jenesis https://github.com/jenesis/scoop-bucket && scoop install jenesis   # Scoop

jenesis-init                       # run from your project root
java build/jenesis/Make.java
```

`jenesis-init` writes `build/jenesis/` into the current directory - pass one or more paths to initialise
several projects at once - and records the version it wrote in `build/jenesis/jenesis.version`. From then
on the project builds with the canonical command above, and needs nothing but a JDK.

For repeated builds on your own machine, the installed **`jenesis`** command runs the same build without
compiling the engine first: it reads the version the project recorded, finds or installs that release, and
runs it. It is also the way to build a project you do not trust. Before running anything it digests the
sources under `build/jenesis/` and the sources that release published, and runs only when the two agree, so
an edited or unreviewed engine is refused rather than executed - and the refusal names the routes that do
build the project.

It refuses one more thing: a release that is no longer considered safe. Each `jenesis` carries the last such
version, runs anything newer, and refuses anything at or below it, so a project cannot pull an engine whose
release is no longer trusted. The fix it asks for is to move the project on - `jenesis-init` re-vendors
`build/jenesis/` from the installed release, and `jenesis-validate` reports what would change first.

<div class="note">
  <strong>Further information.</strong> <code>jenesis-make</code> runs the installed engine as it stands,
  ignoring anything under <code>build/jenesis/</code>, so it builds a project that vendors nothing at all -
  a standard Maven project is built with it without installing anything into the project.
  <code>jenesis-unsafe</code> is <code>jenesis</code> without the version floor: it verifies the vendored
  sources against the published ones exactly as <code>jenesis</code> does, and then runs the recorded
  version even where that release is no longer considered safe - for reproducing an old build, or a branch
  that is not moving.
  <code>jenesis-exec</code> runs a module's <code>main</code> the way <code>jenesis</code> runs the build,
  <code>jenesis-version</code> and <code>jenesis-validate</code> report how a project's
  <code>build/jenesis/</code> compares with the installed release - <code>jenesis-validate</code> naming the
  files that differ - and <code>. jenesis-switch</code> moves the whole shell to the version a project
  records, sourced rather than run, since it changes the calling shell.
</div>

### Git submodule

Most explicit, and the most reproducible: the pinned submodule commit is the anchor, so a fresh clone plus
`git submodule update --init --depth 1` is the entire setup, with no separate install step. Ask the installer
for it and it does the whole thing:

```bash
curl -fsSL https://get.jenesis.build | JENESIS_MODE=submodule bash
```

That adds the submodule at `build/.upstream`, records it as shallow, checks it out at the version you asked
for, links `build/jenesis` into it, and stages all of it for you to commit. Jenesis is read at its pinned
commit and its history is never browsed from your project, so the shallow flag keeps every fresh checkout
cheap.

The pinned commit is a hash of the tree it names, and your git client checks it on every fetch and checkout,
so this route verifies what it brings in the same way the `jenesis` command verifies a vendored copy - a
substituted or edited engine does not survive the checkout. Moving to another version is a commit of the
submodule pointer, reviewed like any other change, and a clone of that commit reads the engine your history
recorded and no other. By hand, the same thing is:

```bash
git submodule add --depth 1 https://github.com/jenesis/jenesis.git build/.upstream
git config -f .gitmodules submodule.build/.upstream.shallow true
ln -s .upstream/sources/build/jenesis build/jenesis
java build/jenesis/Make.java
```

The submodule sits in `build/`, beside the `build/jenesis` link that points into it, because `build/` is
already tracked in every Jenesis project - the entry point lives there. That keeps `.jenesis/` free of
anything git has to keep. The leading dot is not decoration: `Make` compiles the sources under the folder its
own file sits in, and skips any directory whose name could not be a Java package, so `.upstream` is passed
over while the `build/jenesis` link into it is followed.

On a platform without symlinks, replace the `ln -s` with `cp -r build/.upstream/sources/build/jenesis
build/jenesis` and refresh the copy after each submodule update.

### What to ignore

Jenesis writes in exactly two places under your project root, so two rules cover it:

```gitignore
target/
.jenesis/
```

`target/` holds the **result** of a build - the jars, the reports, the staged release tree - and is named by
`jenesis.project.target`. `.jenesis/` holds the **mechanics** that make the next build faster: the
dependencies and keys it downloaded, so nothing foreign is fetched twice; the cache that lets an unchanged
step be skipped; the compiled engine; and a running daemon's port, token and log.

Neither is yours to keep. `rm -rf target .jenesis` costs a slower next build and nothing else, and both rules
hold whether the engine is vendored as source or tracked as a submodule - a submodule sits at
`build/.upstream`, outside both. The vendored engine needs no rule of its own: it carries its own
`.gitignore`, and its compiled classes land in `.jenesis/classes` rather than beside the sources.

### Why the engine lives in your repository

`build/jenesis/` plays the part of a wrapper script, except nothing is downloaded: the engine *is* source in
your repository, compiled by the JDK you already have. A clone builds offline, and CI needs no setup step.

The cost is the recompile on each run. `Make` handles it - the first call compiles the engine into
`.jenesis/classes` and later calls reuse those classes until a source changes - and the installed `jenesis`
skips it entirely by running a released engine. Keep `java build/jenesis/Make.java` in the README and in CI:
compiling the engine offline is normally faster than downloading a binary distribution over the network, and
it needs nothing fetched to obtain the build tool at all.

## Build a project from nothing

A module declaration, a class, and the engine you just installed:

```
greeter
├── build/jenesis          the engine
└── sources
    ├── module-info.java
    └── greeter
        └── Main.java
```

```java
/**
 * @jenesis.main greeter.Main
 */
module greeter {
    requires org.apache.commons.lang3;
}
```

```java
package greeter;

import org.apache.commons.lang3.StringUtils;

public class Main {

    public static void main(String... args) {
        System.out.println(StringUtils.capitalize("hello from a module"));
    }
}
```

Build it, then build and run it:

```bash
java build/jenesis/Make.java        # resolve, compile, test, package into target/
java build/jenesis/Execute.java     # the same, then run @jenesis.main
```

```
Hello from a module
```

`requires org.apache.commons.lang3` is the entire dependency declaration - no `pom.xml`, no coordinate, no
version. The module name resolves to a Maven artifact, and the version that arrives is the newest release
unless you [pin](/tool/pinning/) it. A project with a `pom.xml` instead of a `module-info.java` builds the
same way, from what the POM declares.

### Reading what it resolved

```bash
java build/jenesis/Make.java dependencies
```

```
main/compile (module-sources)
maven/org.apache.commons/commons-lang3 3.20.0 [compile] (module org.apache.commons.lang3) {Apache-2.0}
```

The resolution key, the version that resolved, the Maven scope, the **Java module name** it carries and its
declared **licence** - a real module graph, not a flat class path. The selector also reports the licences and
the module shape of the whole closure.

### Staging it for release

`stage` builds and then lays out everything a release consists of:

```bash
java -Djenesis.project.version=1.0.0 build/jenesis/Make.java stage
```

```
target/stage
├── maven/output/greeter/greeter/1.0.0
│   ├── greeter-1.0.0.jar               the modular jar, under a Maven coordinate
│   ├── greeter-1.0.0.pom               generated, so Maven consumers resolve it
│   └── greeter-1.0.0-cyclonedx.json    the bill of materials
├── modular/output/greeter/1.0.0
│   ├── greeter.jar                     the same jar, under its module name
│   └── greeter.pom
└── reports/output                      the dependency graph, and what else ran
```

Nothing was configured to get that: the version came from the command line and the coordinate from the
module name. `export` then copies the tree into your local Maven repository, your local module repository,
or both.

<div class="demo">
  The four project shapes are runnable:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-01-java-pom">demo-01</a> (Maven layout),
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-02-java-modular">demo-02</a> (this one, with
  a pinned dependency), and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-03-java-pom-multi">demo-03</a> and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-04-java-modular-multi">demo-04</a> for the
  multi-module versions of each. See <a href="/tool/demos/">Demos</a>.
</div>

## What drives a build

Two things decide what a build does: **settings**, the `jenesis.*` properties, and **selectors**, the
positional arguments that choose what runs. Four settings carry the knobs you reach for first:

| Setting | Default | What it is |
| --- | --- | --- |
| `jenesis.make.root` | `.` | The directory scanned for `module-info.java` / `pom.xml`. Command line only, because finding the project comes before the build. |
| `jenesis.project.target` | `target` | Where every build output is written. Safe to delete for a clean build. |
| `jenesis.project.layout` | `auto` | How the project is shaped and how dependencies resolve. |
| *(the default target)* | `build` | What runs when you pass no selector. |

A setting may lead the arguments after the source file, or come before it as a JVM property - anything else
after the file is read as a selector:

```bash
java -Djenesis.test.skip=true \
     -Djenesis.project.layout=maven \
     build/jenesis/Make.java
```

### Layout: what a build publishes

`jenesis.project.layout` is `auto` by default, which reads the project and picks. The choice decides what
`stage` lays out:

| Layout | The project declares | `stage` produces |
| --- | --- | --- |
| `maven` | a `pom.xml`; a `module-info.java` is ignored | the Maven tree only |
| `modular_to_maven` | a `module-info.java`, no root `pom.xml` | both trees, as above: a modular jar that a Maven consumer can still resolve, through a generated POM |
| `modular` | a `module-info.java` | the modular tree only - a modular jar, resolved by module name, with nothing for Maven |

`auto` resolves to `maven` or `modular_to_maven`; the strict `modular` layout is opt-in with
`-Djenesis.project.layout=modular`, for artifacts consumed only as Java modules.

### Selectors: choosing what to run

Positional arguments after the source file are **selectors** - they choose what part of the build to run.
With none, the default target runs, which out of the box is `build`: compile, test and package every
discovered module. The other targets the shipped layouts register:

| Selector | What it does |
| --- | --- |
| `build` | Compile, test, and jar every module *(the default)*. |
| `stage` | The full release recipe - build, then lay out a publishable tree under `target/stage/`. |
| `export` | Publish the staged tree into your local Maven repository (`~/.m2`), your local module repository (`~/.jenesis`), or both, as the layout dictates. |
| `pin` | Rewrite every `pom.xml` / `module-info.java` to pin the full resolved dependency closure. |
| `dependencies` | Print each module's resolved dependency graph with licences (shown above). |
| `ide` | Generate IntelliJ IDEA, VS Code, and Eclipse project metadata. |
| `help` | Print the usage screen. |

A `+<module>` selector builds just one module's subtree - `+greeter` builds the `greeter` module and
whatever it depends on, without touching unrelated siblings. Selectors and the build graph they walk are the
subject of the next chapter.

<div class="note">
  Under the hood a build is a graph of <strong>steps</strong> - each takes input folders and produces a
  fresh output folder - and a selector names a point in that graph. You do not need the full mechanics yet;
  <strong>Core concepts</strong> introduces build steps, the build graph, and layouts in depth.
</div>
