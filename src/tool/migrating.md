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

- Maven's `target/` is the folder Jenesis writes, so run a Maven build in a second checkout, made with
  `git worktree add`.
- `gradle clean` deletes `build/` with `build/jenesis` in it. Move Gradle's output aside with one line in the
  root `build.gradle.kts` or `build.gradle`, and list `gradle-build/` in `.gitignore` in place of `build/`:
  `allprojects { layout.buildDirectory = layout.projectDirectory.dir("gradle-build") }`.
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

Code compiled for Java 8 or older cannot be a module, since a `module-info.java` needs release 9, so it
migrates to `pom.xml` and stays there. A descriptor it ships for Java 9 and later lives in
`src/main/java/META-INF/versions/9/`, compiled as a
[multi-release overlay](/tool/building-and-running/#one-jar-several-java-versions), and a dependency without
a module name gets the name it requires from a `<!--jenesis.alias <module> <groupId>/<artifactId>-->` comment.
Where the descriptor moves there, the old build follows it: ModiTect's `moduleInfoFile`, and the
maven-javadoc-plugin's `sourcepath` and `excludePackageNames`.

Otherwise, a module cannot be declared while a package is split: held by the tests and the main code of one
project, as white-box tests are, or by two projects of the build. This program prints each split package and
where it is held. Save it outside the sources as `SplitPackages.java` and run `java SplitPackages.java` from the
root, which the JDK runs as it stands on any operating system:

```java
void main() throws IOException {
    var source = Pattern.compile("(.*)src/(main|test)/java/(.+)/[^/]+[.]java");
    var owners = new TreeMap<String, Set<String>>();
    try (var files = Files.walk(Path.of("."))) {
        files.map(file -> file.toString().replace(File.separatorChar, '/'))
                .map(source::matcher)
                .filter(Matcher::matches)
                .forEach(match -> owners.computeIfAbsent(match.group(3), _ -> new TreeSet<>())
                        .add(match.group(2) + " " + match.group(1)));
    }
    owners.forEach((folder, held) -> {
        if (held.stream().filter(owner -> owner.startsWith("main ")).count() > 1
                || held.stream().anyMatch(owner -> owner.startsWith("test ")
                        && held.contains("main " + owner.substring(5)))) {
            IO.println(folder.replace('/', '.') + " " + held);
        }
    });
}
```

A package it prints, or one that a dependency holds as well, is split.

### Two phases

Where a package is split, the move takes two phases. **Phase one** migrates to `pom.xml`, changing the build
and nothing of the code; its first passing build is the baseline later steps are compared against. **Phase two**
moves the result to `module-info.java` as a change of its own, once the `pom.xml` build compares equal with the
old one. Code without a split package may go to `module-info.java` directly; this chapter is the `pom.xml`
route.

## What a pom.xml keeps

A `pom.xml` is read for what it declares, not for how Maven builds it:

- **Read:** coordinates; parents, local or fetched, a parent that cannot be fetched failing the build;
  `<modules>`; properties; dependencies of every scope but `system`, with `<optional>`, `<exclusions>`,
  `<type>` and `<classifier>`, a type other than `jar`, `test-jar`, `ejb`, `ejb-client`, `maven-plugin` and
  `bundle` placed on no path, as Maven places it on none, and refused, `pom` aside, as a direct dependency of a
  module the build builds; `<dependencyManagement>` with imported BOMs; `maven.compiler.release`, or else
  `target` or `source`, with `testRelease` and `enablePreview`; the metadata of the module and its parents;
  source and resource directories, a local parent's where the module names none, and
  `src/{main,test}/<name>` where they exist for each name `jenesis.maven.sources` lists - a project that keeps
  Kotlin or Groovy in `src/main/kotlin` or `src/main/groovy` sets `jenesis.maven.sources=kotlin,groovy` in its
  `jenesis.properties`; the `<!--jenesis.plugin-->`
  and `<!--jenesis.alias-->` comments of the module and of a local parent, and its own `<!--jenesis.pin-->`;
  and a profile of any POM that Maven activates by `<jdk>` or by `<activeByDefault>`. An unclosed `<jdk>` range such as `[9,`
  or `[9` reads as `[9,)`; a range that is none leaves the profile of a fetched POM inactive and fails the
  build in the project's own.
- **Ignored:** `<build><plugins>` and `<pluginManagement>`, a profile activated by a property, the operating
  system, a file or `-P`, `<repositories>` and `settings.xml`, a resource's includes, excludes, `targetPath`
  and filtering, and every packaging but `jar` and `bundle`. A `bundle` builds a jar whose OSGi headers a
  `META-INF/MANIFEST.MF` among the resources or a plugin supplies. A `jar` module without sources or resources
  is built only where its configuration folder names a plugin, which may generate them; otherwise a
  `[SKIPPED]` line names it. A `pom` aggregator is followed for its modules,
  and a `pom` module with a `<dependencyManagement>` and no modules is published as a
  [bill of materials](/tool/publishing/#a-maven-bom-from-a-pom-xml). Any other packaging, a `war` among them,
  is not built, and a `[SKIPPED]` line names its module.

A version a Maven extension supplies, as nisse or jgitver do, names a property no `pom.xml` defines and is
refused. Set `jenesis.project.version` instead, which the dependencies between the project's own modules take
as well.

Nothing else ignored is reported, so list the old build's plugins, profiles and repositories before deleting
anything. A source directory gives the jar only what its compilers read, as Maven's does. A resource directory is copied whole; one that holds `target/` or
`.jenesis/`, as `./` does, fails the build and names the remedy, `-Djenesis.project.resources=<file>:<path in
the jar>`. Metadata is inherited as *[Publishing](/tool/publishing/)* describes.

A test `module-info.java` that names the main module itself, the `--patch-module` idiom for white-box tests,
is not supported: move it to a folder the old build alone compiles, and the tests run on the class path. One
that declares a module of its own is compiled as a module, but its tests run on the class path too, so tests of
Java Module System behaviour stay with the old build until phase two.

## Where plugin configuration goes

Most plugins become a file that switches a tool on, a line of `packaging.properties`, a tag or POM comment, or
a setting. A file sits in a [configuration folder](/tool/configuration/#where-tool-configuration-lives) of the
module, the first one found being the whole configuration. A tool the build downloads is switched on by its
`<name>.properties`, whose `configuration=<path>` names the tool's own file and whose other lines are its
values, or by that file alone where no properties are found; `jenesis.<part>.<name>=false` switches it off. What
lived inside a plugin's own configuration moves here:

| In Maven or Gradle | In Jenesis |
| --- | --- |
| `compilerArgs`, `options.compilerArgs` | `process-javac.properties` |
| `fork` with `meminitial`, `maxmem` or `-J` options | `-J<option>=` in `process-javac.properties`, which runs `javac` in a JVM of its own |
| A multi-release jar's sources in `src/main/java<N>`, a compiler execution with `multiReleaseOutput`, a Gradle `java<N>` source set | The same sources moved below `src/main/java/META-INF/versions/<N>/`, compiled as a [multi-release overlay](/tool/building-and-running/#one-jar-several-java-versions) |
| `annotationProcessorPaths` | A dependency of `<type>processor</type>`; one named without a version takes it from `<dependencyManagement>` |
| The kotlin-maven-plugin, scala-maven-plugin or GMavenPlus, Gradle's `kotlin("jvm")`, `scala` or `groovy` plugin | Nothing: a module's `.kt`, `.scala` or `.groovy` sources are compiled wherever the build finds them; a compiler plugin is `@jenesis.plugin kotlin:tool <coordinate>` or `@jenesis.plugin scala:tool <coordinate>` |
| The dokka-maven-plugin or Gradle's Dokka plugin | A `dokka.properties` |
| Gradle's `com.google.devtools.ksp` plugin and its `ksp(...)` dependencies | A [`ksp.properties`](/tool/generating-sources/#kotlin-symbol-processing) holding the processors' arguments, with each processor as `@jenesis.plugin ksp:processor <coordinate>` |
| Surefire includes and groups | `-Djenesis.test.filter`, `-Djenesis.test.tag` |
| Surefire excludes | `-Djenesis.test.exclude`, as `.*IntegrationTest` |
| `argLine`, `jvmArgs` of the tests | `process-test.properties` |
| Surefire's `rerunFailingTestsCount`, Gradle's `test-retry` plugin | A retry of the test framework, such as JUnit Pioneer's `@RetryingTest` |
| `forkCount` with `reuseForks=false`, `forkEvery` | A test module of its own, since each test module runs in a JVM of its own |
| The environment of the tests | `environment-test.properties` |
| The Checkstyle, PMD, detekt, ktlint, Scalastyle, scalafmt or CodeNarc plugin | Its file in the configuration folder - `checkstyle.xml`, `pmd.xml`, `detekt.yml`, `.editorconfig`, `scalastyle-config.xml`, `.scalafmt.conf` or `codenarc.xml` - or a `<name>.properties` naming it as `configuration=`; `jenesis.strict.<name>=true` fails the build on a finding |
| The jacoco-maven-plugin or pitest-maven | A `jacoco.properties` or a `pitest.properties` |
| The jaxb2, protobuf, avro, jaxws, openapi-generator or antlr4 Maven plugin | An `xjc.properties`, `protoc.properties`, `avro.properties`, `wsimport.properties`, `openapi.properties` or `antlr.properties` that binds the contracts |
| The spotbugs-maven-plugin, forbiddenapis, japicmp or revapi | A `spotbugs.properties`, `forbiddenapis.properties`, `japicmp.properties` or `revapi.properties` with its values |
| Spotless, the fmt-maven-plugin or the formatter-maven-plugin | A `googlejavaformat.properties`, `palantir.properties` or `eclipse.properties` for the Java formatter, a `ktfmt.properties`, or the `.editorconfig` of ktlint and the `.scalafmt.conf` of scalafmt; `-Djenesis.format.rewrite=true` rewrites the sources |
| Checkstyle's `propertyExpansion`, `configProperties` | The other lines of `checkstyle.properties` |
| PMD's `minimumPriority`, `rulesMinimumPriority` | `-Djenesis.pmd.priority` |
| The `mainClass` of the jar, shade or exec plugin | A `<mainClass>` property |
| `manifestEntries`, `jar.manifest.attributes` | A `META-INF/MANIFEST.MF` among the resources |
| `addDefaultImplementationEntries` | Written by default |
| A resource with a `targetPath` | `-Djenesis.project.resources=<file>:<path in the jar>` |
| A `<profile>` chosen with `-P`, Gradle properties | A `jenesis-<profile>.properties`, selected with `-Djenesis.make.profiles` |
| `<repositories>`, `settings.xml` | `-Djenesis.maven.uri` or `MAVEN_REPOSITORY_URI` |
| A toolchain | `-Djenesis.toolchain.version` |
| Tests on another JDK, Surefire's `jvm` or a `Test` task's `javaLauncher` | The whole build again with `-Djenesis.toolchain.version`, as a CI matrix leg |
| A `-tests` jar | `-Djenesis.stage.tests=true` |
| `maven-jar-plugin` executions with a `<classifier>`, `build-helper`'s `attach-artifact` | A [`classifiers.properties`](/tool/publishing/#publishing-variants-of-a-jar) naming each variant's folders |
| `os-maven-plugin`'s `${os.detected.classifier}` | One profile per platform, each holding that platform's `classifiers.properties` |
| A native build run by `exec-maven-plugin` or `maven-antrun-plugin`, Gradle's `cpp-library` | A plugin at `binary/compiled` that writes the library into a folder `classifiers.properties` names |
| `javac -h`, as `maven-compiler-plugin`'s `<headerOutputDirectory>` or Gradle's `options.headerOutputDirectory` | The same plugin's [header step](/tool/extending-the-build/#compiling-native-code), the build's `javac` step with `headers(true)` |
| `maven.deploy.skip`, `maven.install.skip` | `stage=false` in the module's `packaging.properties`, which keeps it out of `export` and `release` alike |
| The maven-plugin-plugin, `<packaging>maven-plugin</packaging>` | `<packaging>jar</packaging>` and a [`mavenplugin.properties`](/tool/publishing/#a-maven-plugin) in the module's configuration folder, its `goalPrefix` as `goalprefix=` |
| Gradle's `java-gradle-plugin` and its `gradlePlugin.plugins` | A `META-INF/gradle-plugins/<id>.properties` among the resources naming the `implementation-class`, and a [`gradleplugin.properties`](/tool/publishing/#a-gradle-plugin) in the project's configuration folder |
| The asciidoctor-maven-plugin, Gradle's `org.asciidoctor.jvm.convert` | An [`asciidoctor.properties`](/tool/publishing/#converting-the-project-s-asciidoc-documents) naming the documents as `documents=../src/docs/asciidoc`, its `attributes` as `attribute.<name>=` lines |
| The flatten-maven-plugin's `flattenDependencyMode=all` | None: a published POM names what the module declares, and a consumer's resolution decides the rest - see [what the published POM names](/tool/publishing/#what-the-published-pom-names) |

A tool resolves in a group named after its plugin, such as `checkstyle:tool` or `jacoco:tool`, once per module. A `pom.xml` pins
it with a `<!--jenesis.pin-->` comment, a child of `<project>` with one coordinate per line, which `pin`
completes with the tool's closure:

```xml
<!--jenesis.pin
checkstyle:tool/maven/<groupId>/<artifactId> <version>
-->
```

`pin` writes one into every module's POM, since a parent's is not inherited, unlike its
`<!--jenesis.plugin-->` comments.

In a process file, a flag given more than once, as `--add-opens` is, takes one argument per line of its value,
and a `--release` is refused, since `maven.compiler.release` declares it. A `source` and `target` without a
release compile as `--release`, which also checks the API, so code calling a newer API behind a version check
needs a `--source=<release>` line. `javac` runs with `-g`, as Maven and Gradle do, unless a line names a
`-g` option of its own, such as `-g\:none=`; a test that reads parameter names needs `-parameters=` there. A plugin may pass flags its configuration never shows, as a convention plugin
adds `-parameters`, so compare the old build's effective `javac` arguments: `mvn -X compile` prints them after
"Command line options:", and `gradle compileJava --debug` on its "Compiler arguments:" line.

Checkstyle reads a copy of the sources below `target/build/`, so a suppression keyed on a source folder, as
`src/test/java`, matches nothing. Key it on the package's folders instead, as `[/\\]example[/\\]test[/\\]`.

The tests run a little differently, too. `jenesis.test.filter` replaces the default naming and its JUnit 4 check
rather than narrowing them, and the root module's entry is written `/<classRegex>`. Unlike Surefire, they do not
run in the module's folder, and no `basedir` property is set: a test that opens `src/test/...` by a relative path
is changed to read that file as a test resource. They run against the module's jar, so one that turns `getResource`
into a `java.io.File` needs
`-Djenesis.test.jars=false`. A build prints no test totals; `-Djenesis.print.tests` streams the runner's summary.

### Shading

Shading is not supported: nothing is relocated, and no class file is rewritten. A shaded library sits in another
jar under another name, where neither licence checks nor the usage counts an open source project's funding
relies on find it. A layer or packaging keeps each library a jar of its own
under its own coordinate, pinned and reported like any other.

A dependency kept private, whose version must not meet the consumer's, goes into a
[module layer](/tool/dependencies/#keeping-a-dependency-private), declared in `module-info.java` alone, so a
`pom.xml` build keeps it plain until phase two. One runnable jar is `launcher=true` in `packaging.properties`,
a repackaged Spring Boot application included; `bundle=true` ships the jars whole, beside the argument file that
launches them.
Fewer dependencies for consumers means publishing the dependency as a dependency.

## Pinning and comparing the two builds

Until it is pinned, a tool the build resolves itself - the test runner, Error Prone, Checkstyle - takes its
newest release without a pre-release qualifier, so the first `pin` settles those as well. Commit before
running it: `pin` writes the versions and checksums it resolved, those of every POM read among them, into a
`<!--jenesis.pin-->` comment of each `pom.xml`, which changes nothing Maven resolves, and leaves
`<dependencyManagement>` as written. Then build with `-Djenesis.dependency.pin=strict`, as CI should.

Before retiring the old build, compare what both produce: the contents of each jar, the dependency tree
(`dependencies` against `mvn dependency:tree` or `gradle dependencies`), the number of tests run, and the POM a
consumer receives, which is generated rather than copied from yours. A `pom.xml` resolves a
conflict as Maven does, the nearest version winning, where Gradle takes the highest; manage each version Gradle
resolved higher in `<dependencyManagement>`.

## Retiring the old build

Remove what Jenesis replaces: the plugin configuration, the wrapper, and the CI steps that called them. A CI job
that built runs `java -Djenesis.dependency.pin=strict build/jenesis/Make.java`. One that published to Maven Central runs the
[`release`](/tool/publishing/#driving-the-release-tool-from-the-build) selector with a `jreleaser.properties`
naming the `jreleaser.yml` and `-Djenesis.release.publish=true`, and the version as `-Djenesis.project.version`, its credentials in
the `JRELEASER_*` variables; one that deployed to a
[repository of its own](/tool/publishing/#releasing-into-a-maven-repository-of-your-own) names it in
`MAVEN_RELEASE_URI` and its key in `MAVEN_RELEASE_TOKEN` instead. Then let the `ide` selector
write the IntelliJ IDEA, VS Code or Eclipse project. A project in the `maven` layout keeps its `pom.xml` files,
which are its build declaration from then on.

## Migrating with a coding agent

The same guidance ships with the engine, written for a coding agent. To hand one the move, enter this in its
prompt, or paste what the command prints:

```text
! java build/jenesis/Make.java prompt/migrate
```

The task follows `skill/migrate`, this chapter and phase two written for an agent, and `skill/registry` names
what replaces each common plugin. The agent closes with a summary: the build declaration it chose,
what replaced each plugin, the split packages that kept the build on `pom.xml`, each shaded dependency and what
replaced it, what still differs from the old build, and the command CI runs.

{% demos 1, 3, 13 %}
