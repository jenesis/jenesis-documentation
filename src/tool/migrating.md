---
order: 17
title: Migrating from Maven or Gradle
description: Moving an existing Maven or Gradle build to Jenesis one concern at a time - choosing between a pom.xml and module-info.java, what a pom.xml keeps, where plugin configuration goes, and comparing both builds before the old one is retired.
---

A Maven or Gradle build moves to Jenesis one concern at a time. After each step you build, so a failure always
has a single cause, and the old build keeps working beside the new one until what both produce compares equal.
This chapter walks through that move: the build declaration to choose, what a `pom.xml` brings along, where the
configuration of each plugin goes, and how to tell that the two builds agree.

## Bringing the tool in

Vendor the engine as *[Getting started](/tool/getting-started/#installing)* describes and commit
`build/jenesis/`. The build runs on JDK 25 or newer and needs nothing else. The release it compiles for is a
setting of its own, so a project that targets an older Java is no obstacle.

Both builds write into the project for a while, and three things keep them apart:

- Maven's `target/` is the same folder Jenesis writes, so `mvn` and a Jenesis build overwrite each other's
  output. Run the old build in a second checkout, made with `git worktree add`, while both exist.
- Gradle writes into `build/`, so `gradle clean` deletes `build/jenesis` along with it.
- A `.gitignore` line `build` or `build/`, common where Gradle ran, also hides `build/jenesis`, and git cannot
  include a file again below an ignored folder. Write `/build/*` and `!/build/jenesis/` instead.

A header or licence check that the old build runs, such as Apache RAT or the license-maven-plugin, flags the
vendored sources, so exclude `build/jenesis` from it.

## Choosing the build declaration

A build is declared in one of two ways:

| Declaration | Layout | What it means for the move |
| --- | --- | --- |
| `pom.xml` | `maven` | The quicker move. A Maven build keeps its `pom.xml` files as they stand; a Gradle build writes one per project. |
| `module-info.java` | `modular_to_maven` | The Java Module System declares the build, and the published POM is generated from it. |

A Gradle build has no counterpart, as no `build.gradle` is read. The `pom.xml` it needs holds only the
coordinates, the dependencies with their scopes, and `maven.compiler.release`.

### Whether the code can be modules yet

Check first whether the code can be modules as it stands. Code compiled for Java 8 or older, as
`maven.compiler.release` or its `target`, a toolchain or a Gradle release of 8 or below says, cannot: a
`module-info.java` needs release 9. Such a project migrates to `pom.xml` and stays there. Where it ships a
descriptor for Java 9 and later, that `module-info.java` lives in `src/main/java/META-INF/versions/9/`, and the
`pom.xml` build compiles it as a [multi-release overlay](/tool/building-and-running/#one-jar-several-java-versions),
against the dependencies that carry a module name. A jar that declares none, as jline 2 or groovy-all 2, is
given the name the descriptor requires by a `<!--jenesis.alias <module> <groupId>/<artifactId>-->` comment in
the `pom.xml`.

Otherwise, a module cannot be declared while a package is split: held by the tests and the main code of one
project, as white-box tests are, or by two projects of the build. Run the first command in each project, and
the second at the root over the main sources of all of them:

```bash
comm -12 <(cd src/main/java && find . -name '*.java' | sed 's|/[^/]*$||' | sort -u) \
         <(cd src/test/java && find . -name '*.java' | sed 's|/[^/]*$||' | sort -u)
find . -path '*/src/main/java/*.java' | sed 's|/src/main/java/| |; s|/[^/]*$||' \
    | sort -u | cut -d' ' -f2 | sort | uniq -d
```

A package either command prints, or one that a dependency holds as well, is split.

### Two phases

Where a package is split, the move takes two phases. **Phase one** migrates to `pom.xml` and changes the build
and nothing of the code. The first build that passes is the baseline every later step is compared against.

**Phase two** moves the result to `module-info.java` as a change of its own, once the `pom.xml` build compares
equal with the old one. It takes the splits apart first, one package at a time, building after each:

| Split | Taken apart by |
| --- | --- |
| White-box tests | Moving them into packages of the test module's own, such as `<package>.test`, testing the public API where they can. What a test still needs becomes public in a package exported to the tests alone, `exports <package> to <test module>`, with `opens <package> to <test module>` where it reflects. |
| Two projects | Moving the classes so each package lives in one module, or merging the projects, with a qualified export for a package only a sibling uses. |
| A dependency | Excluding the jar that holds the package, or moving the project's classes out of it. |

When `javac` compiles the main module, it warns that the test module named by a qualified export is not found.
Under `-Werror`, `-Xlint:-module` beside it silences that warning.

Code without a split package declares `module-info.java` directly, in one phase.

## Declaring the build in module-info.java

Each module is the folder whose `module-info.java` sits at the root of its sources. In a Maven tree that is
`src/main/java`, so the file stays where it is. Every `module-info.java` below the root becomes a module, so one
the old build keeps for itself, as `src/moditect/module-info.java`, needs an empty `.jenesis.skip` file in its
folder. A root `pom.xml` makes the build pick the `maven` layout, so pass
`-Djenesis.project.layout=modular_to_maven` while the old build still needs its POM. What the POM said moves
into the module declaration and the files beside it:

| In the POM | In a module-info.java build |
| --- | --- |
| A dependency | `requires <module>`, or `requires static` where it is only compiled against. A jar without a module name resolves by the name the Jenesis Module Index gives it, or by `@jenesis.alias`. |
| A version | `@jenesis.pin`, which `pin` writes; `@jenesis.bom` for a BOM. |
| The release | `@jenesis.release <N>`. |
| An annotation processor | `@jenesis.plugin maven/<groupId>/<artifactId>`. |
| The main class | `@jenesis.main <class>`. |
| `src/main/resources` | Moves into `src/main/java`: a file beside the sources is packaged. |
| The tests | A test module of their own, carrying `@jenesis.test <module>` and requiring the module and the test framework, with packages that differ from the tested module's. |
| Name and description | The first sentence and the second paragraph of the module's Javadoc. |
| The coordinate | Derived from the module name; `project` and `artifact` in `project.properties` keep a published one. |
| URL, licences, developers, SCM | `project.properties`. |
| The version | `-Djenesis.project.version`. |

*[Publishing](/tool/publishing/)* describes `project.properties`, including the one a single module keeps for
a coordinate of its own.

The pins `pin` wrote into a `pom.xml` do not carry over: until `pin` runs again, the module build resolves the
newest versions. Write a bare `@jenesis.pin <module> <version>` for each version to keep, then run `pin`, which
adds the checksums and the closure.

The old build's `javadoc` fails on the `@jenesis` tags of a `module-info.java` as unknown, so register each tag
the module uses as disabled there. `javadoc` takes no wildcard: `-tag jenesis.pin:X` on its command line,
`tags("jenesis.pin:X")` among Gradle's javadoc options, or a
`<tag><name>jenesis.pin</name><placement>X</placement></tag>` in the `<tags>` of the maven-javadoc-plugin.

## What a pom.xml keeps

Kept as the build declaration, a `pom.xml` is read for what it declares and not for how Maven builds it:

- **Read:** the coordinates; a parent, from the project where its `relativePath` points at one with the same
  coordinates and fetched otherwise; `<modules>`; `<properties>` and `${...}`; dependencies of `compile`,
  `provided`, `runtime` and `test` scope, with `<optional>`, `<exclusions>`, `<type>` and `<classifier>`;
  `<dependencyManagement>` with imported BOMs, where a module's own entry wins over a parent's that names the
  same artifact by a property; `maven.compiler.release`, or else `maven.compiler.target` or `source`, with
  `maven.compiler.testRelease` and `maven.compiler.enablePreview`; the metadata of the module's POM and, where
  it declares none, of its parents; the source and test source directories and the `<directory>` of each
  resource, a local parent's where the module names none; the `<!--jenesis.plugin-->`, `<!--jenesis.pin-->`
  and `<!--jenesis.alias-->` comments of the module and of a local parent; and a profile of any POM - the
  module's, a parent's, a BOM's or a dependency's - that Maven activates by `<jdk>`, matched against the JDK
  the build runs on, or by `<activeByDefault>` when no other profile of that POM is active, with its
  properties, dependencies, dependency management and resource directories.
- **Ignored:** `<build><plugins>` and `<pluginManagement>`, a profile activated by a property, the operating
  system, a file or `-P`, a profile's `<modules>`, `<repositories>` and `settings.xml`, a resource's includes,
  excludes, `targetPath` and filtering, `system` scope, and every packaging but `jar`. A `pom` aggregator is
  followed for its modules, and a `war` is not built at all.

Nothing ignored is reported, so list the old build's plugins, profiles and repositories before deleting
anything: each needs an answer in the next section. A source directory gives the jar only what its compilers
read - `.java`, `.kt`, `.scala`, `.groovy` - as Maven's does, so a file that must ship moves to a resource
directory. A resource directory is copied whole. One that holds `target/` or `.jenesis/`, as `./` does, fails
the build, naming the remedy: place the file it was meant for with
`-Djenesis.project.resources=<file>:<path in the jar>`, as `LICENSE:META-INF/LICENSE`, and keep that resource
for Maven in a profile activated by a property, such as `<property><name>!jenesis</name></property>`, which
Maven still activates and this build does not. A module inherits its parents' metadata as *[Publishing](/tool/publishing/)*
describes, and `project.properties` at the root fills in only what the POMs leave out.

A test `module-info.java` that names the main module itself, the `--patch-module` idiom Maven and Gradle use
for white-box tests, is not supported: compiled as a module of its own, it shadows the main one. With
`pom.xml`, move it out of the test sources to a folder the old build alone compiles, so the tests run on the
class path against the main jar. With `module-info.java`, give the tests a module of their own, as phase two
does.

## Where plugin configuration goes

Most plugins become a file that switches a built-in tool on, a line of `packaging.properties`, a tag or POM
comment, or a setting. Such a file sits in a configuration folder of the module, as
*[Configuration](/tool/configuration/#where-tool-configuration-lives)* lists them, and the first file found is
the whole configuration, as nothing merges.

A tool resolves in a group named after it, such as `checkstyle`, `pmd` or `jacoco`, once per module. A
`pom.xml` pins it with a comment that is a child of `<project>`, one coordinate per line, which `pin` completes
with the tool's closure:

```xml
<!--jenesis.pin
checkstyle/maven/com.puppycrawl.tools/checkstyle 10.18.2
-->
```

A module inherits the comments of its local parent, never those of a POM that only lists it under
`<modules>`, so a module outside the parent chain pins its tools itself. A `module-info.java` pins a tool with
the same line as a `@jenesis.pin` tag. What lived inside a plugin's own configuration moves here:

| In Maven or Gradle | In Jenesis |
| --- | --- |
| `compilerArgs`, `options.compilerArgs` | `process-javac.properties` |
| `annotationProcessorPaths` | `@jenesis.plugin`, or in a POM a dependency of `<type>processor</type>` |
| Surefire includes and groups | `-Djenesis.test.filter`, `-Djenesis.test.tag` |
| Surefire excludes | `-Djenesis.test.exclude`, as `.*IntegrationTest` |
| `argLine`, `jvmArgs` of the tests | `process-test.properties` |
| The environment of the tests | `environment-test.properties` |
| `manifestEntries`, `jar.manifest.attributes` | A `META-INF/MANIFEST.MF` among the resources |
| A resource outside the resource folders, or with a `targetPath` | `-Djenesis.project.resources=<file>:<path in the jar>` |
| A `<profile>` chosen with `-P` or a property, Gradle properties | `jenesis.properties` and a `jenesis-<profile>.properties` each, selected with `-Djenesis.make.profiles` |
| `<repositories>`, `settings.xml` | `-Djenesis.maven.uri` or `MAVEN_REPOSITORY_URI`, with its token never in a file the project provides |
| A toolchain | `-Djenesis.toolchain.version` |
| A `-tests` jar, the `test-jar` goal | `-Djenesis.stage.tests=true` |
| `maven.deploy.skip`, `maven.install.skip` | Read from the POM's properties as Maven's plugins read them |

A flag given more than once, as `--add-opens` is, takes one argument per line of its value. A `--release` in
`process-javac.properties` is refused, because `maven.compiler.release` or
`@jenesis.release` already declares it for every tool. `javac` runs without `-g`, where Maven and Gradle pass
it, so a test that reads parameter or local variable names needs `-g=` or `-parameters=` there.

A few differences in how tests run are worth knowing. `jenesis.test.filter` replaces the default naming rather
than narrowing it, and the root module's entry is written `/<classRegex>`. Under JUnit 4 a class named like a
test runs only where it can hold one, as Surefire decides. The tests run against the module's jar, so one that turns `getResource` into a
`java.io.File` fails with "URI is not hierarchical" until `-Djenesis.test.jars=false` runs them against
folders, as Maven does. And a build prints no test totals: `-Djenesis.print.tests` streams the runner's
summary.

### Shading

Shading is not supported: nothing is relocated, and no class file is rewritten. Each use of it has another
answer:

- **A dependency kept private**, whose version must not meet the consumer's, goes into a
  [module layer](/tool/dependencies/#keeping-a-dependency-private) with `@jenesis.layer`, so two versions share
  one JVM under the same package names. Layers are declared in `module-info.java` alone, so a `pom.xml` build
  that shaded keeps the dependency plain until phase two.
- **One runnable jar** is `launcher=true` in `packaging.properties`.
- **Fewer dependencies for consumers** is answered by publishing the dependency as a dependency, with a
  `requires static` on it made a `requires`.

## Pinning and comparing the two builds

Until it is pinned, a tool the build resolves itself - the test runner, Error Prone, Checkstyle, a code
generator - takes its newest release without a pre-release qualifier, so the first `pin` settles those as
well. Commit before running it. In a
`pom.xml` project, `pin` writes the versions and checksums it resolved into each `<dependencyManagement>`,
where an imported BOM stays, so review that diff. A pinned entry outranks a BOM, as any managed version does:
to move to a new version of the BOM, change it, delete the entries `pin` wrote and pin again. Then build with
`-Djenesis.dependency.pin=strict`, as CI should.

Before retiring the old build, compare what both produce:

- the contents of each jar;
- the dependency tree, `dependencies` against `mvn dependency:tree` or `gradle dependencies`;
- the number of tests run;
- the POM a consumer receives, which is generated and flattened rather than copied from yours.

A `pom.xml` resolves a conflict as Maven does, the version nearest the root winning, where Gradle takes the
highest version requested, and no resolver setting does the latter. Manage each version Gradle resolved higher
in `<dependencyManagement>`; comparing the dependency trees lists them.

## Retiring the old build

Remove what Jenesis now replaces - the plugin configuration, the Maven or Gradle wrapper, and the CI steps
that called them - and let the `ide` selector write the IntelliJ IDEA, VS Code or Eclipse project, so no IDE
depends on the old build. A project in the `maven` layout keeps its `pom.xml` files, which are now its build
declaration.

## Migrating with a coding agent

The same guidance ships with the engine, written for a coding agent:

```bash
java build/jenesis/Make.java skill/migrate
```

It prints the steps of this chapter, and `skill/registry` names the built-in that replaces each common Maven
or Gradle plugin. A plugin without one is either something done differently, which that page names, or a
plugin to write, as *[Extending the build](/tool/extending-the-build/)* describes. Both pages print in a
project that has no `pom.xml` or `module-info.java` yet, so an agent can read them before the first build
declaration exists.

{% demos 1, 2, 3, 4, 12 %}
