---
order: 17
title: Migrating a Maven or Gradle build
description: Moving an existing Maven or Gradle build to Jenesis one concern at a time - choosing the build declaration, what a pom.xml keeps and ignores, where plugin configuration goes, pinning, and comparing both builds before the old one is retired.
---

A Maven or Gradle build moves to Jenesis one concern at a time. After each step you build, so a failure always
has a single cause, and the old build keeps working beside the new one until what both produce compares equal.

## Bringing the tool in

Vendor the engine as *[Getting started](/tool/getting-started/#installing)* describes and commit
`build/jenesis/`. The build runs on JDK 25 or newer; the release it compiles for is a setting of its own. While
both builds exist, keep them apart:

- Maven's `target/` is the folder Jenesis writes, and `gradle clean` deletes `build/` with `build/jenesis` in
  it. Run the old build in a second checkout, made with `git worktree add`.
- A `.gitignore` line `build` or `build/` also hides `build/jenesis`, and git cannot include a file again below
  an ignored folder. Write `/build/*` and `!/build/jenesis/` instead.
- A header or licence check of the old build, such as Apache RAT, flags the vendored sources: exclude
  `build/jenesis` from it.

## Choosing the build declaration

| Declaration | Layout | What it means for the move |
| --- | --- | --- |
| `pom.xml` | `maven` | The quicker move. A Maven build keeps its `pom.xml` files as they stand; a Gradle build writes one per project. |
| `module-info.java` | `modular_to_maven` | The Java Module System declares the build, and the published POM is generated from it. |

No `build.gradle` is read. The `pom.xml` a Gradle project needs holds only the coordinates, the dependencies
with their scopes, and `maven.compiler.release`.

### Whether the code can be modules yet

Code compiled for Java 8 or older, as `maven.compiler.release` or its `target`, a toolchain or a Gradle release
says, cannot be a module: a `module-info.java` needs release 9. Such a project migrates to `pom.xml` and stays
there. A descriptor it ships for Java 9 and later lives in `src/main/java/META-INF/versions/9/`, compiled as a
[multi-release overlay](/tool/building-and-running/#one-jar-several-java-versions), and a dependency without
a module name gets the name it requires from a `<!--jenesis.alias <module> <groupId>/<artifactId>-->` comment.
Where the descriptor moves there, the old build follows it: ModiTect's `moduleInfoFile`, and the
maven-javadoc-plugin's `sourcepath` and `excludePackageNames`.

Otherwise, a module cannot be declared while a package is split: held by the tests and the main code of one
project, as white-box tests are, or by two projects of the build. Run the first command in each project, and
the second at the root:

```bash
comm -12 <(cd src/main/java && find . -name '*.java' ! -name module-info.java | sed 's|/[^/]*$||' | sort -u) \
         <(cd src/test/java && find . -name '*.java' ! -name module-info.java | sed 's|/[^/]*$||' | sort -u)
find . -path '*/src/main/java/*.java' | sed 's|/src/main/java/| |; s|/[^/]*$||' \
    | sort -u | cut -d' ' -f2 | sort | uniq -d
```

A package either command prints, or one that a dependency holds as well, is split.

### Two phases

Where a package is split, the move takes two phases. **Phase one** migrates to `pom.xml` and changes the build
and nothing of the code; the first build that passes is the baseline every later step is compared against.
**Phase two** moves the result to `module-info.java` as a change of its own, once the `pom.xml` build compares
equal with the old one. Code without a split package may take the `module-info.java` route directly. This
chapter is the `pom.xml` route, from start to finish.

## What a pom.xml keeps

A `pom.xml` is read for what it declares, not for how Maven builds it:

- **Read:** coordinates; parents, local or fetched, a parent that cannot be fetched failing the build;
  `<modules>`; properties; dependencies of every scope but `system`, with `<optional>`, `<exclusions>`,
  `<type>` and `<classifier>`; `<dependencyManagement>` with imported BOMs; `maven.compiler.release`, or else
  `target` or `source`, with `testRelease` and `enablePreview`; the metadata of the module and its parents;
  source and resource directories, a local parent's where the module names none; the `<!--jenesis.plugin-->`,
  `<!--jenesis.pin-->` and `<!--jenesis.alias-->` comments of the module and of a local parent; and a profile
  of any POM that Maven activates by `<jdk>` or by `<activeByDefault>`. An unclosed `<jdk>` range such as `[9,`
  or `[9` reads as `[9,)`; a range that is none leaves the profile of a fetched POM inactive and fails the
  build in the project's own.
- **Ignored:** `<build><plugins>` and `<pluginManagement>`, a profile activated by a property, the operating
  system, a file or `-P`, `<repositories>` and `settings.xml`, a resource's includes, excludes, `targetPath`
  and filtering, and every packaging but `jar` and `bundle`. A `bundle` builds a jar whose OSGi headers a
  `META-INF/MANIFEST.MF` among the resources or a plugin supplies. A `jar` module with neither sources nor
  resources is built only where its `src/main/build.jenesis/` or `build.jenesis/` configures a plugin, which
  may generate them; otherwise a `[SKIPPED]` line names it. A `pom` aggregator is followed for its modules,
  and a `pom` module with a `<dependencyManagement>` and no modules is published as a
  [bill of materials](/tool/publishing/#a-maven-bom-from-a-pom-xml). Any other packaging, a `war` among them,
  is not built, and a `[SKIPPED]` line names its module.

A version that a Maven extension supplies, as nisse or jgitver do, is not read: a version naming a property no
`pom.xml` defines is refused. Set `jenesis.project.version` instead, which the dependencies between the
project's own modules take as well.

Nothing else ignored is reported, so list the old build's plugins, profiles and repositories before deleting
anything. A source directory gives the jar only what its compilers read, as Maven's does, so a file that must
ship moves to a resource directory. A resource directory is copied whole; one that holds `target/` or
`.jenesis/`, as `./` does, fails the build and names the remedy, `-Djenesis.project.resources=<file>:<path in
the jar>`. Metadata is inherited as *[Publishing](/tool/publishing/)* describes, and `project.properties`
fills in only what the POMs leave out.

A test `module-info.java` that names the main module itself, the `--patch-module` idiom for white-box tests,
is not supported. Move it out of the test sources to a folder the old build alone compiles, so the tests run on
the class path against the main jar. A test `module-info.java` that declares a module of its own is compiled as
a module, but its tests run on the class path too, so tests of Java Module System behaviour stay with the old
build until the project moves to `module-info.java`.

## Where plugin configuration goes

Most plugins become a file that switches a built-in tool on, a line of `packaging.properties`, a tag or POM
comment, or a setting. Such a file sits in a
[configuration folder](/tool/configuration/#where-tool-configuration-lives) of the module, and the first file
found is the whole configuration. What lived inside a plugin's own configuration moves here:

| In Maven or Gradle | In Jenesis |
| --- | --- |
| `compilerArgs`, `options.compilerArgs` | `process-javac.properties` |
| `fork` with `meminitial`, `maxmem` or `-J` options | `jenesis.process.factory=fork` in `jenesis.properties`, with `-J<option>=` in `process-javac.properties` |
| `annotationProcessorPaths` | A dependency of `<type>processor</type>` |
| Surefire includes and groups | `-Djenesis.test.filter`, `-Djenesis.test.tag` |
| Surefire excludes | `-Djenesis.test.exclude`, as `.*IntegrationTest` |
| `argLine`, `jvmArgs` of the tests | `process-test.properties` |
| The environment of the tests | `environment-test.properties` |
| Checkstyle's `propertyExpansion`, `configProperties` | A `checkstyle.properties` beside `checkstyle.xml` |
| PMD's `minimumPriority`, `rulesMinimumPriority` | `-Djenesis.source.pmd.priority` |
| `manifestEntries`, `jar.manifest.attributes` | A `META-INF/MANIFEST.MF` among the resources |
| A resource with a `targetPath` | `-Djenesis.project.resources=<file>:<path in the jar>` |
| A `<profile>` chosen with `-P`, Gradle properties | A `jenesis-<profile>.properties`, selected with `-Djenesis.make.profiles` |
| `<repositories>`, `settings.xml` | `-Djenesis.maven.uri` or `MAVEN_REPOSITORY_URI` |
| A toolchain | `-Djenesis.toolchain.version` |
| A `-tests` jar | `-Djenesis.stage.tests=true` |
| `maven.deploy.skip`, `maven.install.skip` | `stage=false` in the module's `packaging.properties`, which keeps it out of `export` and `release` alike |

A tool resolves in a group named after it, such as `checkstyle` or `jacoco`, once per module. A `pom.xml` pins
it with a `<!--jenesis.pin-->` comment, a child of `<project>` with one coordinate per line, which `pin`
completes with the tool's closure:

```xml
<!--jenesis.pin
checkstyle/maven/com.puppycrawl.tools/checkstyle 10.18.2
-->
```

A module inherits these comments from its local parent, never from a POM that only lists it under
`<modules>`.

In a process file, a flag given more than once, as `--add-opens` is, takes one argument per line of its value,
and a `--release` is refused, since `maven.compiler.release` declares it. A `source` and `target` without a
release compile as `--release`, which also checks the API, so code calling a newer API behind a version check
needs a `--source=<release>` line. `javac` runs without `-g`, so a test that reads parameter names needs
`-g=` or `-parameters=` there. A plugin may pass flags its configuration never shows, as Palantir Baseline adds
`-parameters`, so compare the old build's effective `javac` arguments: `mvn -X compile` prints them after
"Command line options:", and `gradle compileJava --debug` on its "Compiler arguments:" line.

Checkstyle reads a copy of the sources below `target/build/`, so a suppression keyed on a source folder, as
`src/test/java`, matches nothing. Key it on the package's folders instead, as `[/\\]example[/\\]test[/\\]`.

The tests run a little differently, too. `jenesis.test.filter` replaces the default naming rather than
narrowing it, and the root module's entry is written `/<classRegex>`. As with Surefire, they run in the
module's folder with the `basedir` system property set to it, so a relative `src/test/...` path finds the
module's file. They run against the module's jar, so one that turns `getResource` into a `java.io.File` needs
`-Djenesis.test.jars=false`. A build prints no test totals; `-Djenesis.print.tests` streams the runner's
summary.

### Shading

Shading is not supported: nothing is relocated, and no class file is rewritten. A dependency kept private, whose
version must not meet the consumer's, goes into a
[module layer](/tool/dependencies/#keeping-a-dependency-private), which is declared in `module-info.java`
alone, so a `pom.xml` build keeps such a dependency plain until phase two. One runnable jar is `launcher=true`
in `packaging.properties`, and fewer dependencies for consumers means publishing the dependency as a
dependency. A Spring Boot application that was repackaged is `bundle=true` instead: its jars and the argument
file that launches them.

## Pinning and comparing the two builds

Until it is pinned, a tool the build resolves itself - the test runner, Error Prone, Checkstyle - takes its
newest release without a pre-release qualifier, so the first `pin` settles those as well. Commit before
running it: `pin` writes the versions and checksums it resolved into each `<dependencyManagement>`, where an
imported BOM stays. A pinned entry outranks a BOM, so to move to a new BOM version, change it, delete the
entries `pin` wrote and pin again. Then build with `-Djenesis.dependency.pin=strict`, as CI should.

Before retiring the old build, compare what both produce: the contents of each jar, the dependency tree
(`dependencies` against `mvn dependency:tree` or `gradle dependencies`), the number of tests run, and the POM a
consumer receives, which is generated and flattened rather than copied from yours. A `pom.xml` resolves a
conflict as Maven does, the nearest version winning, where Gradle takes the highest; manage each version Gradle
resolved higher in `<dependencyManagement>`.

## Retiring the old build

Remove what Jenesis now replaces - the plugin configuration, the Maven or Gradle wrapper, and the CI steps that
called them. A CI job that built now builds under strict pinning. One that published to Maven Central runs the
[`release`](/tool/publishing/#driving-the-release-tool-from-the-build) selector with
`-Djenesis.jreleaser.dry=false` and the version as `-Djenesis.project.version`, on a runner with JReleaser
installed; its credentials become the `JRELEASER_*` variables JReleaser reads. One that deployed to a
[repository of its own](/tool/publishing/#releasing-into-a-maven-repository-of-your-own) names it in
`MAVEN_RELEASE_URI` and its key in `MAVEN_RELEASE_TOKEN` instead. Then let the `ide` selector
write the IntelliJ IDEA, VS Code or Eclipse project. A project in the `maven` layout keeps its `pom.xml` files,
which are now its build declaration.

## Migrating with a coding agent

The same guidance ships with the engine, written for a coding agent:

```bash
java build/jenesis/Make.java skill/migrate
```

It prints the steps of this chapter and of phase two, and `skill/registry` names the built-in that replaces
each common Maven or Gradle plugin. A plugin without one is either something done differently, which that page
names, or a plugin to write, as *[Extending the build](/tool/extending-the-build/)* describes.

{% demos 1, 3, 12 %}
