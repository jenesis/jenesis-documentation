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
  matching console runner for you, so you never add it as an explicit dependency. A module can also state its
  engine: a `test.properties` in its configuration folder holding `engine=junit-platform`, `junit4` or
  `testng` decides it, the same in every checkout and every CI run. In the modular layouts the tests live in
  their own test module, built after the module under test (next section).

<div class="note">
  Every phase is cached the way <em>Core concepts</em> described: a second <code>build</code> recompiles and
  re-tests nothing until an input actually changes. A test step in particular re-runs only when the classes it
  covers change - not on every build.
</div>

### Reading a build's outcome

Besides the progress lines, every build writes what happened to `target/.jenesis.events.jsonl`, one JSON
object per line, and the next build replaces it. The second progress line, `[EVENTS]`, names the file, so a
script or a coding agent reads it instead of parsing the console:

```
{"status":"started","target":"/.../demo-01-java-pom/target","directory":"/.../demo-01-java-pom","run":"20261005T180707.205894Z"}
{"status":"resolved","module":"build","seconds":0.067}
{"status":"skipped","step":"build/maven/identifier/prepare","folder":"/.../target/build/maven/identifier/prepare","run":"20261005T180659.583809Z"}
{"status":"completed","seconds":0.342,"executed":1,"skipped":18,"failed":0}
```

Every object leads with its `status`:

| `status` | Written for | Beside it |
| --- | --- | --- |
| `started` | the build, first line | `target`, the `directory` the build ran in, and the `run` |
| `executed` | a step that ran | `step`, `seconds` and `folder`, which holds the step's `output/` |
| `skipped` | a step none of whose inputs changed | `step`, `folder`, and the earlier `run` that produced the folder |
| `loaded`, `stored` | a step's output fetched from or stored in the build cache | `step` and `seconds` |
| `resolved` | a module | `module` and `seconds` |
| `failed` | a step or a module that failed | `step` or `module`, the `error` class and its `message`; a failed step also its `folder` |
| `completed`, `failed` | the build, last line | `seconds` and how many steps `executed`, `skipped` and `failed`; a failed build adds its `error` and `message` |

Every build is a run, named on the `started` line by the moment it began, in UTC. A step that executed is this
run's. A skipped step names the earlier run whose output it kept, so a test report in its folder is that run's
result, not this one's. The same name sits in a `local.properties` beside the step's `output/`, with
`cached=true` when the output came from the build cache:

```properties
run=20261005T180659.583809Z
cached=false
```

That file stays on the machine that wrote it: no checksum covers it and no build cache carries it.

A file without that last line belongs to a build that is still running or was killed.
`-Djenesis.executor.events=false` writes no file and leaves one that an earlier build wrote in place.

A failed step keeps what it wrote. Its `folder` ends in `~` and holds the step's `output/` and, for a tool the
build ran, the command, the tool's output and its reports under `supplement/`, beside an empty
`.jenesis.failed` marker. The folder stays until the step comes up again in a later build. A failure that says
to execute a command names paths relative to the `directory` of the `started` line. The command is quoted for a POSIX
shell, and the arguments of a JDK tool such as `javac` or `javadoc` are moved into an argument file under
`supplement/`, so the line is pasted into a shell as it stands.

The progress lines, the dependency tree and every other line the build prints are coloured with ANSI escape
sequences. To read them as plain text, from a file or a pipe, pass `-Djenesis.palette.colors=none`.

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
is wired for it, and a plain `stage` leaves it out. Under `jenesis.stage.tests`, which publishes the test
modules beside the modules they test, it is staged as well, as a module of its own, because the published test
modules require it. It can be tested like any other module: a module tagged `@jenesis.test demo.greeter.testing`
is run as the other test modules are, and staged as the test variant of `demo.greeter.testing`. Since `abstract`
is a Java keyword it can never be a module name, so the two forms of the tag never collide.

In every layout a test class is found by Maven's naming: a class named `Test*`, `*Test`, `*Tests`,
`*TestCase`, `IT*`, `*IT` or `*ITCase` runs, in a named package or in the default one. An abstract class, a
nested class, the module descriptor and a class of a multi-release overlay are never run.

### Tests that read their resources as files

The tests run against the packaged test jar, so a resource a test loads with `getResource` is an entry
inside a jar. A test that turns its URL into a `java.io.File` fails there with
"URI is not hierarchical". `-Djenesis.test.jars=false` runs the tests against the module's classes and
resources folders instead, as Maven and Gradle do, while the modules they depend on stay jars:

```bash
java -Djenesis.test.jars=false build/jenesis/Make.java
```

A module whose tests run on the module path refuses the setting, because a folder of resources is no part of a
module there.

{% demos 3, 4, 35 %}

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
`<properties>` block, and `maven.compiler.testRelease`, where it names one, is the release its tests compile
for.

Without either, the module compiles for the release of the JDK running the build: `--release 25` on any JDK
25, and Kotlin and Scala sources target the same release. That keeps the output the same across updates and
vendors of one JDK. Which JDK runs the build can be named as well, as described under
[The JDK a build runs on](#the-jdk-a-build-runs-on).

### Preview features

A module that uses a preview feature of Java - a language feature or an API a JDK ships for trying out -
declares its release with a `-preview` suffix:

```java
/**
 * @jenesis.release 25-preview
 */
module demo.preview {
    exports sample;
}
```

A `pom.xml` project sets `maven.compiler.enablePreview` to `true` beside `maven.compiler.release`, the
property the Maven compiler reads as well; without a release, it enables the preview features of the JDK
running the build.

The module compiles with `javac --release 25 --enable-preview`, and its jar records the release in its
manifest as `Jenesis-Preview: 25`. Every run of it then enables the preview features without being asked:
its tests, `Execute`, a bundle, a `jpackage` image, and a program `jpx` runs from the jar alone. A runtime
image that `jlink` links is given the option for good, so its own `java` runs the module as it stands, and
`javadoc` documents the sources with the same features enabled. An executable jar is the exception: `java -jar`
opens the jar only after the JVM started, so it runs as `java --enable-preview -jar <jar>`.

Preview features belong to one Java version, so a module that uses them compiles only on that JDK. A build on
another fails and names the one to select, `-Djenesis.toolchain.version=25` (see
[The JDK a build runs on](#the-jdk-a-build-runs-on)). A module compiled against one that uses preview features
enables them itself, so its test module declares `25-preview` too; without it, the build stops before
compiling and names the release to declare. A class that uses a preview feature runs only on the Java version
it was compiled for, so a library built this way binds its users to that JDK until the feature is final.

{% demos 15 %}

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
`Multi-Release: true`, the flag that tells the JVM to look in the versioned directory at all. Each overlay
compiles for its own release alone, whatever release the module's declaration names.

An overlay may also carry the `module-info.java` itself. That is how a library whose main code targets Java 8,
which predates the Java Module System, declares a module: the descriptor sits in `META-INF/versions/9/`, is
compiled against the module path with the main classes as part of the module, and may `requires` library
modules. On Java 9 and later the jar is a named module, while Java 8 reads it from the class path as before.
In a `pom.xml` project with `maven.compiler.release` at `8`, the descriptor lives in
`src/main/java/META-INF/versions/9/`.

{% demos 11 %}

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

Both jars cover the sources a generator or a plugin added to the module as well as your own: `javadoc`
documents the generated classes, and the sources jar carries their source files beside the schema they follow
from, as Maven's does.

{% demos 66 %}

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

{% demos 70 %}

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
build's own `--release` and your two flags. A properties file splits a line at the first `:` or `=`, so a
flag that holds one escapes it, as `-Xlint\:all` does.

A flag the module's declaration already hands the tool cannot be set here. A `--release` or
`--enable-preview` line in `process-javac.properties` fails the build and names where the release is
declared instead: `@jenesis.release` in `module-info.java`, or `maven.compiler.release` and
`maven.compiler.testRelease` in a `pom.xml`. Declared there, it reaches every tool that reads it.

The same mechanism works for every tool the build forks: `javac`, `javadoc`, `kotlinc`, `scalac`, `jar`, `jmod`,
`jlink`, `jpackage`, and `native-image`. Two names address the forked JVMs specifically: **`process-java.properties`**
applies to *every* forked `java` process, the program `Execute` runs included, while
**`process-test.properties`** targets only the test JVM
(merged over the `java` file, with test keys winning).

`javadoc` runs with `-Xdoclint:none`, so a missing comment or tag is not reported. An `-Xdoclint` flag in
`process-javadoc.properties` replaces that default, and `-Werror=` makes a warning fail the build:

```properties
# process-javadoc.properties  →  report every doclint finding, and fail on it
-Xdoclint\:all=
-Werror=
```

An error fails the build either way. A module whose sources declare no public type has nothing to
document and is skipped, unless `process-javadoc.properties` asks for more with `-package` or `-private`.

<div class="tip">
  Because the file lives in a configuration folder, it is profile-aware and resolved by first match. A
  profile can add a flag for one build, and an empty <code>process-javac.properties</code> in a more specific
  folder switches an inherited flag back off. This is the profile-aware way to compile a single module with
  extra <code>javac</code> flags.
</div>

### Attributes of the jar's manifest

The build writes the jar's manifest itself, so `process-jar.properties` cannot name one: a `--manifest` line
there fails the build. A `META-INF/MANIFEST.MF` among the module's resources is the basis of the manifest
instead - beside the sources of a module, or under `src/main/resources/` in a Maven project:

```text
Manifest-Version: 1.0
Implementation-Title: Compiler arguments demo
Implementation-Vendor: Example Corp
```

The jar's manifest holds these lines and, merged over them, the ones the build writes, such as the location of
the bill of materials. This is where Maven's `<manifestEntries>` or Gradle's
`jar.manifest.attributes` go, an `Automatic-Module-Name` among them. Resources are not filtered, so a value
is written as it stands. An attribute the build writes with a different value fails the build rather than
being replaced.

{% demos 12 %}

## Handing a program environment variables

A test run, or any other program the build forks, sees only the platform's own environment variables:
`PATH`, `HOME`, `LANG`, `LC_*` and `TMPDIR`, and on Windows `SystemRoot`, `TEMP`, `USERPROFILE` and the like.
Nothing else of your shell reaches it. A variable is no input of the build, so a test result never depends on
one the build cannot see, and no tool reads a secret it was not handed.

To hand a program more, add an **`environment-<command>.properties`** file to a configuration folder, named
like a `process-<command>.properties`:

```properties
# environment-test.properties  →  the test run gets GREETING, and TOKEN from your shell
GREETING=Hello
TOKEN
```

`NAME=value` sets a variable to the value written. A name with no value passes on your shell's own value when
the program runs, and leaves the variable unset when your shell has none. The file is an input of the program,
so editing a value runs it again. A value taken from your shell is not part of that input, which suits a
credential or a proxy but not a value a result depends on.

Four names take such a file:

| File | Reaches |
| --- | --- |
| `environment-java.properties` | every JVM the build forks, the test run included |
| `environment-test.properties` | the test run only, merged over the `java` file |
| `environment-pitest.properties` | PIT's mutation run |
| `environment-native-image.properties` | `native-image` |

A JDK tool such as `javac` or `javadoc` takes none, as it may run inside the build's own JVM, and a file naming
one fails the build. `native-image` is handed the variables its C compiler reads without a file: `INCLUDE`,
`LIB` and `LIBPATH` from a Visual Studio developer prompt, `CPATH`, `C_INCLUDE_PATH`, `LIBRARY_PATH` and
`SDKROOT`. A release run by the build hands JReleaser every `JRELEASER_*` variable, where it reads its
credentials. The program `Execute.java` or `jpx` runs is the one you asked for rather than a step of the
build, so it is handed your whole environment, as from a shell.

### Values from the command line

In a `process-<command>.properties` or an `environment-<command>.properties`, a value `@<key>` stands for the
setting `jenesis.variable.<key>`, and `@<key>/<default>` falls back to what follows the slash when the setting
is absent. `@@` writes a literal `@`. A missing setting without a default fails the build and names the
setting:

```properties
# environment-test.properties
GREETING=@greeting/Hello
```

```bash
java -Djenesis.variable.greeting=Hi build/jenesis/Make.java
```

The setting comes from the command line, a `jenesis.properties` or a profile, like any other. The resolved
value is part of the input of every program it reaches, so another value runs the program again. It is also
written into the build's output under `target/`, so a credential stays a name without a value.

{% demos 4 %}

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

{% demos 13, 39 %}

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

### Options for the program's JVM

A leading `-J` hands an option to the JVM that runs your program, as the JDK's own tools read it, written as
`java` takes it:

```bash
java build/jenesis/Execute.java -J-Xmx512m -J-Xlog:gc ada lovelace
```

The program's JVM receives `-Xmx512m` and `-Xlog:gc`, and the program `ada lovelace`. The first argument not
starting with `-J` begins the program's own arguments, so a later `-J…` reaches the program unchanged. A `-J`
option follows what a `process-java.properties` gives the same JVM, so it wins where both set an option: the file
is where a project keeps what every run needs, the command line what one run needs. Options on the `java` command
before `build/jenesis/Execute.java` configure only the JVM that builds. `jpx` reads `-J` the same way, and
the `jenesis-exec` tool refuses it, as the JDK's own tools do (see
*[Running a build inside another program](/tool/extending-the-build/#running-a-build-inside-another-program)*).

### Implicit vs. explicit main

If exactly one module declares a main class, `Execute` selects it **implicitly** - you pass nothing. If several
do, it stops and lists the candidates; name the one you want **explicitly** with two properties, which also
narrows the build to that module's subtree:

```bash
java -Djenesis.execute.module=tools \
     -Djenesis.execute.main=org.example.tools.Cli \
     build/jenesis/Execute.java --help
```

`jenesis.execute.module` takes the same module path you would write after `+` in a build selector.

<div class="note">
  <code>Execute</code> can also run the launched program inside a container, independently of the build - see
  <em>Build performance &amp; isolation</em>. Running an <em>already-published</em> module instead of the
  current project is the job of <a href="/jpx/">jpx</a>.
</div>

{% demos 8, 9, 52 %}

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

{% demos 51 %}

## Granting native access

Code that calls native functions or reads native memory - through the foreign function and memory API, JNI,
or a library built on either - uses *restricted methods*, which the JDK allows only for a module the launch
names with `--enable-native-access`. Without it the JDK prints a warning today, and a future release refuses
the call. A `@jenesis.native` tag declares that grant, and the build adds it to every launch the module owns:
its test run, its `Execute` run, and what it packages - a bundle, a Docker image, a `jpackage` application and
an executable jar.

Whether native code runs is decided by what a program uses, not by the library that offers it: a library can
offer a native API that most of its users never call, so it declares nothing. The module that uses the API
names the module that needs access, and a module that calls restricted methods itself names itself:

```java
/**
 * @jenesis.native demo.natives.text
 */
module demo.natives.words {
    requires transitive demo.natives.text;
}
```

A declaration grants access only to the runs of the module that makes it, and is never inherited. Its names
are recorded in the module's jar as the manifest attribute `Jenesis-Native-Access: demo.natives.text`, so a
module that runs this one can learn what it has to grant, and grants it the same way:

```java
/**
 * @jenesis.main demo.natives.app.Application
 * @jenesis.native demo.natives.text
 */
module demo.natives.app {
    requires demo.natives.words;
}
```

A test module is a run of its own and grants what its tests need itself. A token is a module name or a
`<groupId>/<artifactId>`, and several may share one tag. A grant adds no dependency: what it names has to be
on the module's run-time path, or the build fails saying so. A jar on the
class path has no name, so a grant for one becomes `--enable-native-access=ALL-UNNAMED`. `jpx` grants what
the jar it runs names.

A library that keeps a module in a [layer](/tool/dependencies/#keeping-a-dependency-private) hides that module
from whoever uses the library, and its need for native access with it. The library passes its own native
access on to the module with a `native` line beside the layer's declaration. The launcher grants it when it
defines the layer, through the lookup of the library that asks for it, so the line also records that the
library needs native access itself. What a granted module passes on to its own layers is granted with it, so
the application grants the library alone - as it would a library that had shaded the module. A module in a
layer is out of the application's reach, so naming it in `@jenesis.native` fails the build like any name the
run does not resolve:

```java
/**
 * @jenesis.layer strings api demo.strings.spi
 * @jenesis.layer strings provider demo.strings.text
 * @jenesis.layer strings native demo.strings.text
 */
module demo.strings.library {
    requires build.jenesis.launcher;
    requires demo.strings.spi;
}
```

```java
/**
 * @jenesis.main demo.strings.app.Application
 * @jenesis.native demo.strings.library
 */
module demo.strings.app {
    requires demo.strings.library;
}
```

A `pom.xml` project declares the same in a project-level comment block, naming itself by its own
`<groupId>/<artifactId>`:

```xml
<!--jenesis.native
org.example/jni
-->
```

`jenesis.dependency.native` decides what the build does with the names a dependency's jar records: `ignore`,
the default, does nothing; `warn` reports each one the running module does not grant; `strict` fails the
build on it:

```bash
java -Djenesis.dependency.native=warn build/jenesis/Make.java
```

{% demos 52, 53 %}

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

## Opening the project in an IDE

The `ide` selector writes project files for IntelliJ IDEA, VS Code and Eclipse from what the build resolved, so an
editor sees exactly the modules, sources and jars the build uses:

```bash
java build/jenesis/Make.java ide
```

`ide/idea`, `ide/vscode` or `ide/eclipse` writes the files of one editor only:

| Editor | Files |
| --- | --- |
| IntelliJ IDEA | an `.iml` beside each module, plus `.idea/modules.xml` and `.idea/misc.xml` |
| Eclipse | a `.project` and a `.classpath` in each module |
| VS Code | `.vscode/settings.json` |

The files are generated, so keep them out of version control. Each editor compiles into a folder of its own -
`target/.idea`, `target/.vscode`, and a `.eclipse/` folder in each module - never into the build's output. A module
of the project is linked as a module rather than as its jar, so navigation crosses from one module into another.

The Java version comes from `@jenesis.release` (see *[Choosing the Java version](#choosing-the-java-version)*), not
from the JDK that ran the build, so the editor refuses what `javac` would refuse. Which JDK provides that version is
your editor's choice: the first run names IntelliJ IDEA's project JDK after the bare version, and a later run keeps
whatever name you picked there.

A module's classpath holds what the module declares. The tools the build resolves for itself - Checkstyle, PMD,
SpotBugs, a formatter - stay out of it. A test module is marked as test sources, and an `@jenesis.test abstract`
module as ordinary sources, since other modules compile against it.

Run `ide` again after changing a dependency or adding a module: the files name the resolved jars by their path, so
a stale file points at a jar the build no longer produces.

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

Jenesis installs no JDK by itself. It runs an installer you name when no JDK on the search path matches, in
`jenesis.toolchain.installer` or, where that is not set, in the `JENESIS_TOOLCHAIN_INSTALLER` environment
variable. The Jenesis command-line install ships one, `jenesis-jdk`.

Where SDKMAN, mise or Scoop installed Jenesis, there is nothing to turn on: the `jenesis` command names its
own `jenesis-jdk` in `JENESIS_TOOLCHAIN_INSTALLER` for the run it starts, unless the variable is set already,
and `jenesis-jdk` installs the JDK with that tool in turn. Nothing is written to your files to arrange it, and
the variable ends with the run. A build started from the sources names the installer on its own command line:

```bash
java -Djenesis.toolchain.version=25-zulu -Djenesis.toolchain.installer=jenesis-jdk build/jenesis/Make.java
```


The setting wins over the environment variable, and an empty one, `-Djenesis.toolchain.installer=`, runs no
installer at all. `jenesis-jdk` turns the version into a request for the tool that installed Jenesis:

| Tool | What it installs |
| --- | --- |
| SDKMAN | The newest Java identifier matching every number of the version, leaving out JavaFX and CRaC builds. `ea` selects an early-access build from jdk.java.net. |
| mise | The newest build of the vendor matching the numbers, as mise resolves it. mise names Zulu builds by Zulu's own version, so for Zulu it installs the newest build of the feature release. |
| Scoop, on Windows | The package of the vendor and feature release from Scoop's `java` bucket, in its newest build. |

`jenesis-jdk` calls back the tool Jenesis itself was installed with, and picks none of its own:
`--tool=sdkman` or `--tool=mise` names one when you run it yourself.
A word of the version names the vendor - `temurin`, `zulu`, `corretto`, `liberica`, `microsoft`,
`sapmachine`, `semeru`, `graalvm`, `oracle` or `jetbrains` - and Temurin is installed when none does. Scoop
offers Temurin, Zulu, Corretto, Liberica and GraalVM only.

Any other program works as well. Jenesis calls it with its own arguments followed by the version, in your
home folder rather than the project, and treats a non-zero exit as a failed build. The program has to install
into a folder on the search path: Jenesis searches once more afterwards, and checks what it finds like any
other JDK. A name is looked up in the folders of `PATH` that are absolute, and a path has to be absolute or
start with `~`; a value that names an existing file is that program as a whole, spaces included.

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

{% demos 7 %}
