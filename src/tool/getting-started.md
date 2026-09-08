---
order: 2
title: Getting started
description: Install Jenesis, build an example project end to end, and take a first tour of the Project.java model.
---

This chapter takes you from nothing to a built project. You install Jenesis, run the canonical build
command against a bundled example, read what it printed, and then meet the `Project.java` file that every
build runs through. Everything later in this section assumes only what is here.

## Prerequisites

Jenesis needs **a JDK, version 25 or newer, and nothing else** - no daemon, no wrapper, no plugin tree to
download. A build is an ordinary Java program that the JDK launches directly, so if `java --version` reports
25 or above, you are ready.

```bash
java --version
```

## Installing

A Jenesis build lives *with* your project: its engine ships as plain Java source under `build/jenesis/`, and
you launch it with the JVM's single-file source mode. Installing is really just populating that
`build/jenesis/` folder. There are three equivalent ways to do it. All land at the same on-disk state, so
the canonical `java build/jenesis/Make.java` command works identically afterwards. Pick by how you prefer
to manage versions.

### A package manager (recommended)

Best when you would rather manage the tool version globally than vendor its sources into every project.
Install once with SDKMAN, Homebrew, or Scoop, then initialise each project from the installed copy:

```bash
sdk install jenesis                # SDKMAN
brew install jenesis/tap/jenesis   # Homebrew
scoop bucket add jenesis https://github.com/jenesis/scoop-bucket && scoop install jenesis   # Scoop

jenesis-init                       # run from your project root
java build/jenesis/Make.java
```

`jenesis-init` writes `build/jenesis/` into the current directory (pass one or more paths to initialise
several projects at once). From then on the project builds with the canonical command, and needs nothing but
a JDK.

The install also puts a `jenesis` command on your path. It reads the version recorded in
`build/jenesis/jenesis.version` and runs **that** version, installing it first where the package manager can,
so the project decides which Jenesis builds it rather than whichever one your shell happens to have.

The recorded version is a claim, so `jenesis` checks it. Before running a compiled engine it digests the
sources under `build/jenesis/` and the sources that version ships, and runs the engine only when the two
agree. When they do not - a stale version file, a version it cannot install, or a `build/jenesis/` somebody
has edited - `jenesis` refuses to run rather than execute code nobody has reviewed, and names the routes
that do build it, in two groups. `. jenesis-switch` and `jenesis-make` stay on the released engine: the
project builds as a standard build, no vendored code runs, and for most projects that is enough. Running
the vendored sources yourself is the other group, in source mode or off classes you compiled once with
`javac`, and that one does run the modified engine - read the project's build instructions first, since
`Project.java` is only the usual entry point and the project may drive its build from another, and since a
modified engine runs with the rights of your build and can break the encapsulation the released engine
gives you. Only run builds from sources you trust. A project
that records nothing falls through to the installed version, and `jenesis-make` skips the whole lookup and
runs the installed version as it stands.

<div class="tip">
  You can skip embedding entirely and run <code>jenesis</code> from a project root with no
  <code>build/jenesis/</code> at all. That is handy for a quick trial, or for building an untrusted project
  while keeping Jenesis itself the trusted, installed copy. In that mode you can only tune the build through
  system properties, not custom build code.
</div>

The install ships a few companion commands. `jenesis-exec` runs a module's `main` the way `jenesis` runs the
build. `jenesis-version` and `jenesis-validate` check that a project's embedded `build/jenesis/` matches the
installed version, and `jenesis-validate` names the files that differ where `jenesis` only decides whether
to trust them. `jenesis-switch` moves the whole shell to the version a project records,
for when you want every command aligned rather than one invocation; source it, as `. jenesis-switch`, since
it changes the calling shell.

### curl bootstrap

Fastest, with no prerequisite beyond a JDK and `curl`. Run from your project root:

```bash
curl -fsSL https://get.jenesis.build | bash
java build/jenesis/Make.java
```

Set `JENESIS_VERSION=X.Y.Z` to pin a release, or pass a git ref to install an arbitrary tag, commit, or
branch: `curl -fsSL https://get.jenesis.build | bash -s -- main`.

### Git submodule

Most explicit, and the most reproducible: the pinned submodule commit is the anchor, so a fresh clone plus
`git submodule update --init --depth 1` is the entire setup, with no separate install step. Ask the installer
for it and it does the whole thing:

```bash
curl -fsSL https://get.jenesis.build | JENESIS_MODE=submodule bash
```

That adds the submodule at `.jenesis/upstream`, records it as shallow, checks it out at the version you asked
for, links `build/jenesis` into it, and stages all of it for you to commit. Jenesis is read at its pinned
commit and its history is never browsed from your project, so the shallow flag keeps every fresh checkout
cheap. By hand, the same thing is:

```bash
git submodule add --depth 1 https://github.com/jenesis/jenesis.git .jenesis/upstream
git config -f .gitmodules submodule..jenesis/upstream.shallow true
ln -s ../.jenesis/upstream/sources/build/jenesis build/jenesis
java build/jenesis/Make.java
```

The submodule sits *under* `.jenesis/` rather than at it because the build writes its own state there - the
resolved artifacts, the compiled engine, the build cache. A submodule at `.jenesis` would have all of that
land inside its working tree, permanently dirty and in the way of the next `git submodule update`.

On a platform without symlinks, replace the `ln -s` with `cp -r .jenesis/upstream/sources/build/jenesis
build/jenesis` and refresh the copy after each submodule update.

### The vendored source, and when to install the command

`build/jenesis/` plays the part that a wrapper script plays in other build tools. It travels with the
repository, so a fresh clone builds with the version the project chose, a contributor needs nothing installed
beyond a JDK, and CI needs no setup step. What it does not do is fetch anything. A wrapper downloads a tool
distribution on first use and every machine has to trust that download; here the engine *is* the source in
your repository, compiled by the JDK you already have. Nothing is fetched to obtain the build tool, so the
step cannot fail offline and there is no distribution to verify. A build still resolves your project's own
dependencies as usual - it is the tool itself that arrives with the clone.

The cost is that source mode recompiles that engine on every invocation. For a one-off build, or in CI where
each job is a fresh machine anyway, that is the right trade. For the edit-build-edit loop it is pure
overhead, and it dominates a build that has little else to do.

So locally, install the command and use it:

```bash
jenesis                     # runs the version recorded in build/jenesis/
java build/jenesis/Make.java    # the same build, recompiling the engine first
```

`jenesis` reads `build/jenesis/jenesis.version`, verifies `build/jenesis/` against the published sources of
that version and runs its compiled engine, so you keep the project's choice of Jenesis and skip the
recompile. The same command builds a project that vendors nothing at all, falling back to the installed
version. **This is the recommended way to work day to day**; keep `java build/jenesis/Make.java` as the
canonical command in your README and CI, where reproducibility matters more than startup.

`Make` does that compiling for you and it is on by default, so there is nothing to arrange: the first call
compiles the build sources once and every later one runs from those classes, until a source changes. One
batch compile beats the launcher compiling class by class as it loads them, so it is faster even for a build
that runs a single time. The classes land beside the sources they came from; `jenesis.make.classes` names a
folder instead, which is what a project whose `build/jenesis` is packaged - a symlink into its own sources,
say - will want.

To drive those classes yourself, on a locked-down machine or in a container image you would rather not
extend:

```bash
javac -d .jenesis/tool build/jenesis/Project.java
java -cp .jenesis/tool build.jenesis.Make
```

## Building an example end to end

The `jenesis/jenesis` repository ships a runnable example for every feature under `demo/`. Clone it and build
the simplest one - a single-module Java project described by a `pom.xml`:

```bash
git clone https://github.com/jenesis/jenesis.git
cd jenesis/demo/demo-01-java-pom
java build/jenesis/Make.java
```

There is no build script to write. The project is just a `pom.xml` and a source file that uses Apache
Commons Lang. Pointed at that directory, Jenesis:

1. **auto-detects the layout** - a `pom.xml` at the root selects the `maven` layout;
2. **resolves and downloads** the declared `commons-lang3` dependency from Maven Central (or your local
   `~/.m2`);
3. **compiles** the sources against it with the JDK's `javac`; and
4. **packages** a jar under `target/`.

Because every step is content-hashed, the first run does the work and a second run reuses it. Nothing
recompiles until an input actually changes.

### Reading what it resolved

To see exactly what the build pulled in, ask for the dependency graph instead of a build. Run the
`dependencies` selector:

```bash
java build/jenesis/Make.java dependencies
```

```
main/compile (module)
maven/org.apache.commons/commons-lang3 3.14.0 [compile] (module org.apache.commons.lang3) {Apache-2.0}
```

Each line shows the resolution key, the resolved version, the Maven scope, the resolved **Java module name**,
and the declared **licence** - Jenesis reads a real module graph, not a flat class path. The `commons-lang3`
version here is fixed to an exact release and content checksum, because this demo ships *pinned*.
Dependencies and pinning each have their own chapter later.

<div class="tip">
  Want the same project in a modular shape, or spread across several modules? The four foundational
  layouts - Java with a <code>pom.xml</code>, Java as a real <code>module-info.java</code> module, and the
  multi-module version of each - are <a href="/tool/demos/">demo-01 through demo-04</a>. Start there and
  read each demo's own README alongside these chapters.
</div>

## The Project model

Everything you ran above went through one file: `build/jenesis/Make.java`. It is the entry point, and it
carries no build logic of its own - that is the point, because the Java launcher compiles the file you name
before any of its code runs, and a file naming no engine class compiles in a fraction of the time. The build itself
is configured by `Project`, a small Java **record** - so a build is configured as code, not markup. You
almost never edit either. Instead you flip system properties on the command line or, for code-level control,
write a tiny entry point of your own next to it (covered in *[Extending the build](/tool/extending-the-build/)*).

Four fields carry the knobs you reach for first. Two have a `jenesis.project.*` system property that sets them
before the build starts, and the root has a `jenesis.make.*` one, because finding the project is the entry
point's job rather than the build's. All four are settable in code as well: the root is the argument
`Project` requires, the rest are withers.

| Field | Property | Default | What it is |
| --- | --- | --- | --- |
| `root` | `jenesis.make.root` | `.` | The directory Jenesis scans for `module-info.java` / `pom.xml`. Command line only; `Make` reads it and hands it to `Project`, whose constructor requires it. |
| `target` | `jenesis.project.target` | `target` | Where every build output is written. Safe to delete for a clean build. |
| `layout` | `jenesis.project.layout` | `auto` | How the project is shaped and how dependencies resolve. |
| `defaultTarget` | *(none)* | `build` | What runs when you pass no selector. |

A property always comes **before** the source file on the command line - anything after it is read as a
selector:

```bash
java -Djenesis.test.skip=true \
     -Djenesis.project.layout=maven \
     build/jenesis/Make.java
```

### Layout: how your project is shaped

`layout` is `auto` by default, which inspects the root and picks:

- **`maven`** - a `pom.xml` at the root. Jenesis reads the declarative parts of the POM (coordinates,
  dependencies, source folders) and builds one module per POM.
- **`modular_to_maven`** - a `module-info.java` and no root `pom.xml`. Jenesis builds real Java modules but
  also emits a generated `pom.xml`, so each artifact stays Maven-publishable. This is what `auto` resolves
  to for a modular project.
- **`modular`** - the same, but resolving dependencies purely by Java module name and emitting no `pom.xml`
  at all. It is opt-in (`-Djenesis.project.layout=modular`), for artifacts consumed only as Java modules.

### Selectors: choosing what to run

Positional arguments after the source file are **selectors** - they choose what part of the build to run.
With none, `Project` runs its `defaultTarget`, which out of the box is `build`: compile, test, and package
every discovered module. The other targets the shipped layouts register:

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
