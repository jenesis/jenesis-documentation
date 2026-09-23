---
order: 5
title: Building & running
description: What the compile, test, and jar phases do; feeding the compiler extra arguments and annotation processors; running a module's main with Execute.java; and rebuilding on every change with watch mode.
---

The default `build` target compiles, tests, and jars every module. You saw it run in
*[Getting started](/tool/getting-started/)*, and *[Core concepts](/tool/core-concepts/)* explained the step
graph underneath. This chapter is about the everyday loop that graph drives. It covers what each of those
phases does, where your tests go, how to hand the compiler an extra flag or an annotation
processor, how to run a module's `main`, and how to keep rebuilding as you edit.

## The build pipeline

For each module, the inferred build wires the same short chain of steps: **compile → jar → test**. Running
`build` (or just `java build/jenesis/Make.java` with no selector) walks that chain for every discovered
module in dependency order. Steps that do not depend on each other run at the same time; on a machine where
that is too much - a laptop on battery, a small CI runner - `-Djenesis.executor.concurrency=<n>` caps how
many run at once (`0`, the default, is no limit). `-Djenesis.executor.concurrency` counts every kind of step;
when it is the tools themselves that are heavy, `-Djenesis.process.concurrency=<n>` caps how many `javac`,
`jar`, `javadoc` and the like run at once, underneath whatever step limit is in force.

- **Compile** runs `javac` over the module's sources, resolving its dependencies onto the class or module
  path, and writes the `.class` files. Other-language compiles (Kotlin, Scala, Groovy) slot into the same
  chain - see *[Other JVM languages](/tool/other-jvm-languages/)*.
- **Jar** packages the compiled classes into the module's jar under `target/`. When the module declares a
  main class (below), the jar's manifest gets a `Main-Class` entry and its `module-info` a `ModuleMainClass`
  attribute, so the artifact is directly launchable.
- **Test** compiles and runs the module's tests. Jenesis **auto-detects the test framework** from the test
  dependencies you already declare - JUnit Platform (JUnit 5 and later), JUnit 4, or TestNG - and resolves the
  matching console runner for you, so you never add it as an explicit dependency. In the modular layouts the
  tests live in their own test module, built after the module under test (next section).

<div class="note">
  Every phase is cached the way <em>Core concepts</em> described: a second <code>build</code> recompiles and
  re-tests nothing until an input actually changes. A test step in particular re-runs only when the classes it
  covers change - not on every build.
</div>

### Writing tests

Where tests live depends on the layout, and in both cases it is what you would write anyway.

A **`pom.xml`** project keeps its tests under `src/test/java` (or the `<testSourceDirectory>` the POM
names), with the test framework as a normal test-scoped dependency:

```xml
<dependency>
    <groupId>org.junit.jupiter</groupId>
    <artifactId>junit-jupiter</artifactId>
    <version>5.11.3</version>
    <scope>test</scope>
</dependency>
```

A **modular** project puts its tests in a **separate module**, which reads the module under test as any
other module does. When a test needs more than the exported API, the Java Module System already has the
means: the module under test exports a package to the test module by name, with
`exports sample.greeter.internal to demo.greeter.test`. That grants access one package at a time, to one
named module. Placing tests in the same package instead would reach package-private members, which is the
kind of access modules were made to prevent.

The test module `requires` the module under test and the framework, and carries a `@jenesis.test` tag
naming the module it tests. It need not be `open`: when the tests run, each of its packages is opened to the
framework modules that reflect over them (to the unnamed module when the framework sits on the class path),
so the descriptor declares only what the tests use:

```java
/**
 * @jenesis.test demo.greeter
 */
module demo.greeter.test {
    requires demo.greeter;
    requires org.junit.jupiter;
}
```

The tag is what makes it a test module: it is compiled and run as part of `build` but never staged or
published. Its folder name is how you select it, so with the module under test in `greeter/` and its tests
in `greeter-test/`, `+greeter` builds the library alone and `+greeter-test` builds it *and* runs the tests.

A module that only supplies infrastructure to the tests - fixtures, fakes, shared assertions - carries the
same tag with the value `abstract` instead of a module name:

```java
/**
 * @jenesis.test abstract
 */
module demo.greeter.testing {
    requires demo.greeter;
    exports greetertesting;
}
```

Such a module is compiled and put on the module path of the test modules that `requires` it, but no test run
is wired for it, and it is never staged - not even under `jenesis.stage.tests`, which does publish the test
modules beside the modules they test. Since `abstract` is a Java keyword it can never be a module name, so
the two forms of the tag never collide.

{% demos 3, 4, 32 %}

### Skipping the tests

To compile and package without running the test suite - a fast inner loop, or a machine that only builds
artifacts - set `jenesis.test.skip`:

```bash
java -Djenesis.test.skip=true build/jenesis/Make.java
```

The bare flag (`-Djenesis.test.skip`) works too. Tests still *compile*; they just do not run.

### Choosing the Java version

An `@jenesis.release <N>` tag on the module declaration pins the compile to a specific Java release - Jenesis
turns it into `javac --release <N>`, so the module compiles against exactly that platform API regardless of
the JDK running the build:

```java
/**
 * @jenesis.release 21
 */
module demo.app {
    exports sample;
}
```

A `pom.xml` project sets the same thing through the `maven.compiler.release` property in its
`<properties>` block.

Without either, the module compiles for the release of the JDK running the build: `--release 25` on any JDK
25, and Kotlin and Scala sources target the same release. That keeps the output the same across updates and
vendors of one JDK. Which JDK runs the build can be named as well, as described under
[The JDK a build runs on](#the-jdk-a-build-runs-on).

### One jar, several Java versions

A jar can also carry different bytecode for different Java versions, and the JVM loads the copy that matches
its own version at launch. You get one from a source convention: anything under
`sources/META-INF/versions/<N>/` is compiled in its own pass with `--release <N>`.

```
sources/
├── module-info.java   # @jenesis.release 21
├── sample/Platform.java   # the Java 21 baseline
└── META-INF/versions/25/sample/Platform.java   # the Java 25 override
```

The jar that comes out runs the baseline on a Java 21 runtime and the override on Java 25 - one artifact, two
implementations, selected by the JVM. Nothing else is needed: producing an overlay is what marks the jar
`Multi-Release: true`, the flag that tells the JVM to look in the versioned directory at all.

{% demos 9 %}

### Source and API-documentation jars

A normal `build` produces just the binary jar. Two flags add the companion artifacts a repository like Maven
Central expects:

```bash
java -Djenesis.project.sources=true \
     -Djenesis.project.documentation=true \
     build/jenesis/Make.java
```

`jenesis.project.sources` adds a per-module `-sources.jar`, and `jenesis.project.documentation` runs the
documentation tool (`javadoc` for Java) and adds a `-javadoc.jar`. Both are off by default because they cost
build time you do not want on every inner-loop run. Turn them on for a release, or record them in a profile
(see *[Configuration](/tool/configuration/)*).

{% demos 58 %}

### Reproducible archives

Every jar, jmod and zip comes out the same from the same inputs: a fixed entry order, no Unix permissions,
and one date on every entry - 1980-02-01 00:00 UTC, a month past the earliest a zip can record so no time
zone reads it as 1979. `jenesis.archive.timestamp` names another, as an ISO-8601 date-time with an offset:

```bash
java -Djenesis.archive.timestamp=$(git log -1 --format=%cI) build/jenesis/Make.java
```

It must lie between `1980-01-01T00:00:02Z` and `2099-12-31T23:59:59Z`, the range an entry records
independently of the building machine's time zone. An empty value turns the fixed time off, and then every
build produces different archives and no release can be checked against its sources - it exists for a tool
that reads entry times and cannot be told otherwise.

What the build writes is fixed; what it copies stays yours. A resource goes into the jar byte for byte, and
so does a source file into the sources jar, so a file checked out with Windows line endings makes a
different archive than the same file checked out on Linux. Git on Windows commonly converts text files to
Windows line endings on checkout (`core.autocrlf`). A `.gitattributes` file at the root of the repository
fixes the line endings of every file Git treats as text, whatever machine checks it out:

```
* text=auto eol=lf
```

{% demos 60 %}

## Passing extra arguments to a tool

Jenesis picks sensible flags for `javac` and the other tools it forks, but sometimes you need one more. You
add it with a **`process-<command>.properties`** file in a configuration folder (`build.jenesis/`, as covered
in *Configuration*), with no build script required. The file is named after the tool, and each entry is a
flag with its argument:

```properties
# process-javac.properties  →  compile with -parameters, and report up to 500 warnings
-parameters
-Xmaxwarns=500
```

Each key is a flag and its value the flag's argument, so the second line passes `-Xmaxwarns 500`. A key with
**no value emits a bare flag**, as the first line does; a value with embedded newlines repeats the flag once
per line. The file merges over the arguments Jenesis already generates - so `javac` here receives both the
build's own `--release` and your two flags.

The same mechanism works for every tool the build forks: `javac`, `kotlinc`, `scalac`, `jar`, `jmod`, `jlink`,
`jpackage`, and `native-image`. Two names address the forked JVMs specifically: **`process-java.properties`**
applies to *every* forked `java` process, while **`process-test.properties`** targets only the test JVM
(merged over the `java` file, with test keys winning).

<div class="tip">
  Because the file lives in a configuration folder, it is profile-aware and resolved by first match. A
  profile can add a flag for one build, and an empty <code>process-javac.properties</code> in a more specific
  folder switches an inherited flag back off. This is the profile-aware way to compile a single module with
  extra <code>javac</code> flags.
</div>

{% demos 10 %}

## Annotation processing

A Java annotation processor (JSR-269) is turned on with a single `@jenesis.plugin` tag on the module
declaration, naming the processor **by module name** (or `<repository>/<coordinate>`):

```java
/**
 * @jenesis.plugin org.immutables.value
 */
module demo.annotations {
    requires static org.immutables.value;
}
```

Jenesis resolves the processor, places it on `javac`'s **processor path** (`--processor-module-path`), and the
compiler runs it.

<div class="warning">
  Processors are run <strong>only from what you declare</strong>. A dependency that happens to bundle a
  processor - even one that is also a <code>requires</code> of your module, and so already on the module path -
  never runs unless a <code>@jenesis.plugin</code> tag places it on the processor path. Delete the tag and the
  processor silently stops running; the class it generates is never produced and the build fails to compile.
</div>

The same tag, with a compiler name in front (`@jenesis.plugin kotlinc <coordinate>`), declares a compiler
plugin for another language - covered in *Other JVM languages*.

{% demos 11, 36 %}

## Running a module's main

To *run* a module rather than just build it, declare its entry point and launch it with **`Execute.java`**, the
companion of `Make.java` in the same folder. Declaring the main class differs by layout but converges on
the same result:

- a **modular** project uses a `@jenesis.main` tag on `module-info.java`:

  ```java
  /**
   * @jenesis.main sample.Sample
   */
  module demo.app {
      exports sample;
  }
  ```

- a **`pom.xml`** project sets a `<mainClass>` property instead:

  ```xml
  <properties>
      <mainClass>sample.Sample</mainClass>
  </properties>
  ```

`Execute.java` **builds the project first**, then launches the main class in a fresh `java` process, forwarding
any trailing arguments to your program:

```bash
java build/jenesis/Execute.java ada lovelace
```

### Implicit vs. explicit main

If exactly one module declares a main class, `Execute` selects it **implicitly** - you pass nothing. If several
do, it stops and lists the candidates; name the one you want **explicitly** with two properties, which also
narrows the build to that module's subtree:

```bash
java -Djenesis.execute.module=tools \
     -Djenesis.execute.mainClass=org.example.tools.Cli \
     build/jenesis/Execute.java --help
```

`jenesis.execute.module` takes the same module path you would write after `+` in a build selector.

<div class="note">
  <code>Execute</code> can also run the launched program inside a container, independently of the build - see
  <em>Build performance &amp; isolation</em>. Running an <em>already-published</em> module instead of the
  current project is the job of <a href="/jpx/">jpx</a>.
</div>

{% demos 6, 7 %}

## Attaching a Java agent

Some libraries have to run as a `-javaagent` rather than be called through an API - a tracer that instruments
classes as they load, a mocking library that redefines them. A `@jenesis.attach` tag on the module declaration
adds one to the `java` commands that module owns: its test run, and the `Execute` run of its `@jenesis.main`.

```java
/**
 * @jenesis.main demo.agents.Application
 * @jenesis.attach io.opentelemetry.javaagent/opentelemetry-javaagent
 */
module demo.agents {
    exports demo.agents;
}
```

The token is a module name or a `<groupId>/<artifactId>`, and everything after it is passed to the agent as
its option string. There is no version slot: the version comes from a dependency you declare, from a pin, or
floats to the latest. A `pom.xml` project declares the same lines in a project-level
`<!--jenesis.attach ... -->` block.

One tag covers both shapes. The OpenTelemetry agent above is **agent-only** - required by nothing, on no
compile or runtime path. Mockito is the other shape, a **dependency that also attaches**, named by a
`requires` *and* an attach declaration; both resolve to the same file.

An attachment belongs to the module that declares it and never propagates to a dependent, so a test module
attaches to its own test run:

```java
/**
 * @jenesis.test demo.agents
 * @jenesis.attach org.mockito
 */
module demo.agents.test {
    requires demo.agents;
    requires org.mockito;
}
```

<div class="note">
  The resolved jar has to carry a <code>Premain-Class</code> manifest attribute - that is what makes it an
  agent - and the build says so with a clear error before the launch rather than letting the JVM fail. Agents
  are ordinary dependencies otherwise: they resolve, pin, and appear in the bill of materials like any other.
</div>

{% demos 48 %}

## Watch mode

While you are editing, keep the build process alive and let it rebuild on every save. Set
`jenesis.project.watch`:

```bash
java -Djenesis.project.watch=true build/jenesis/Make.java
```

The first build runs as usual; Jenesis then watches the project root and re-runs the target whenever a file
changes, reusing the content-hash cache so only the steps whose inputs moved run again - a no-op change
settles in well under a second. The output folders and dot-directories are excluded, so the build's own
writes never trigger a rebuild. Press Ctrl+C to stop.

Module selectors still apply, so you can watch just one module's subgraph:

```bash
java -Djenesis.project.watch=true build/jenesis/Make.java +mymodule
```

Setting `jenesis.project.watch=true` in a `jenesis.properties` file makes watch a project's default. Watch mode
already skips a module's tests when none of its inputs changed; it can go finer and re-run only the tests a
change can reach - a development-loop optimisation covered in *[Code quality & testing](/tool/code-quality-and-testing/)*.

## The JDK a build runs on

A build runs on the JDK that started it, unless the project names one. `jenesis.toolchain.version` does, in
`jenesis.properties` or with `-D`:

```properties
jenesis.toolchain.version=25-temurin
```

`Make.java` and `Execute.java` check the JVM they were started on first. When it matches, the build runs as
always. When it does not, they look for a matching JDK among those already installed and start again on it,
with the same selectors and the `-Djenesis.*` properties of the command line, and print a line naming the
JDK they chose. Nothing is downloaded or installed: when no JDK matches, the build fails and lists what it
found. Other JVM options, such as `-Xmx`, reach the new JVM through the `JDK_JAVA_OPTIONS` environment
variable, which every `java` launcher reads. A build started from an entry point of your own runs on the JVM
that started it, unless that entry point asks (see *[Extending the build](/tool/extending-the-build/)*).

Moving to another JDK compiles again only what depends on it: a module that declares no release now
compiles for the new JDK's release, while a module that declares one keeps its classes.

### Naming a version

A version is `<feature>[.<interim>[.<update>...]][-<word>...]`:

- **The numbers match as a prefix**, a missing number counting as zero: `25` matches every JDK 25, and
  `25.0.3` that update and its patches. Jenesis runs on Java 25 or newer, so a lower version is refused; to
  compile for an older Java, declare the release as described under
  [Choosing the Java version](#choosing-the-java-version).
- **Every word must be one the JDK answers to**: a word of the vendor or the vendor version its `release`
  file records, or of the pre-release and optional parts of its version. Temurin answers to `eclipse`,
  `adoptium` and `temurin`, Azul Zulu to `azul` and `zulu`, GraalVM Community Edition to `graalvm` and
  `community`, and a long-term-support build to `lts`. There is no list of vendors, so a JDK built in-house
  answers to its own name.
- **A pre-release matches only when the version names its word**: `26-ea` selects an early-access build of
  26, and `26` never does.

Among several matching JDKs the newest wins. A JDK is identified by reading its `release` file, so none is
run before one is chosen, and the error for a version nothing matches lists every JDK found with the words
it answers to.

### Where Jenesis looks

`jenesis.toolchain.searchpath` is a comma-separated list of folders. An entry is absolute or starts with `~`,
and `*` stands for any one folder name. The default, `@`, stands for the usual locations of the operating
system, and combines with entries of your own, as in `@,/opt/jdks/*`:

| Operating system | Searched for `@` |
| --- | --- |
| Linux | `/usr/lib/jvm/*`, `~/.sdkman/candidates/java/*`, `~/.jdks/*`, `~/.local/share/mise/installs/java/*` |
| macOS | `/Library/Java/JavaVirtualMachines/*/Contents/Home`, `~/Library/Java/JavaVirtualMachines/*/Contents/Home`, `/opt/homebrew/opt/*/libexec/openjdk.jdk/Contents/Home`, `~/.sdkman/candidates/java/*`, `~/.local/share/mise/installs/java/*` |
| Windows | `C:\Program Files\<vendor>\*` for Eclipse Adoptium, Java, Microsoft, Zulu, Amazon Corretto and BellSoft, `~\.jdks\*`, `~\scoop\apps\*\current` |

An empty search path searches nothing, so the build only checks the JDK it was started on - the setting for
a CI job that sets up its own JDK:

```bash
java -Djenesis.toolchain.searchpath= build/jenesis/Make.java
```

### Installing a missing JDK

Jenesis installs no JDK by itself. It runs an installer you name in `jenesis.toolchain.installer` when no JDK
on the search path matches, and the Jenesis command-line install ships one, `jenesis-jdk`. Turn it on once,
for every project:

```bash
jenesis-jdk --enable
```

That adds `jenesis.toolchain.installer=jenesis-jdk` to your `~/.jenesis/jenesis.properties`. `jenesis-jdk`
turns the version into a request for the tool that installs JDKs on your machine:

| Tool | What it installs |
| --- | --- |
| SDKMAN | The newest Java identifier matching every number of the version, leaving out JavaFX and CRaC builds. `ea` selects an early-access build from jdk.java.net. |
| mise | The newest build of the vendor matching the numbers, as mise resolves it. mise names Zulu builds by Zulu's own version, so for Zulu it installs the newest build of the feature release. |
| Scoop, on Windows | The package of the vendor and feature release from Scoop's `java` bucket, in its newest build. |

`jenesis-jdk` prefers the tool Jenesis itself was installed with; `--tool=sdkman` or `--tool=mise` picks one.
A word of the version names the vendor - `temurin`, `zulu`, `corretto`, `liberica`, `microsoft`,
`sapmachine`, `semeru`, `graalvm`, `oracle` or `jetbrains` - and Temurin is installed when none does. Scoop
offers Temurin, Zulu, Corretto, Liberica and GraalVM only.

Any other program works as well. Jenesis calls it with its own arguments followed by the version, in your
home folder rather than the project, and treats a non-zero exit as a failed build. The program has to install
into a folder on the search path: Jenesis searches once more afterwards, and checks what it finds like any
other JDK. A name is looked up in the folders of `PATH` that are absolute, and a path has to be absolute or
start with `~`.

### What a project cannot set

The search path and the installer decide which programs the build runs, so they are yours to set, not the
project's. Both are accepted on the command line and in your own `~/.jenesis/jenesis.properties` and its
profiles, and refused in the project's `jenesis.properties` and in the project's profiles. A project names
the version it needs, and so chooses among the JDKs you installed or your installer provides, but it cannot
point the build at a program of its own.

Before a JDK it found runs, Jenesis checks on Linux and macOS that every file in it belongs to you or to root
and that no other user can write to it; a group named after the file's owner, the private group many Linux
systems give each user, may. A JDK that fails the check is refused with the file named, not exchanged for
another match. GitHub's hosted Linux runners install the JDKs of `actions/setup-java` writable by every user,
so a job that searches for one restricts it first, with `chmod -R go-w` on its folder. Windows has no such
check, so there the search relies on the protection of `C:\Program Files` and of your user profile.

{% demos 61 %}
