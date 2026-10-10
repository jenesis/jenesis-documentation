---
order: 18
title: Moving a build to modules
description: Declaring a migrated build in module-info.java - taking split packages apart, what a test module reaches of the module it tests, what each part of a pom.xml becomes, keeping published coordinates, pinning again, and what the old build needs while it remains.
---

A build that *[Migrating a Maven or Gradle build](/tool/migrating/)* moved to `pom.xml` can go one step
further and declare itself in `module-info.java`, so the Java Module System describes what each module
requires and exports, and the published POM is generated from it. This is phase two of that chapter's
[two phases](/tool/migrating/#two-phases): a change of its own, started once the `pom.xml` build compares equal
with the old one. Code without a split package, as that chapter's checks found, takes the same route directly.

## Taking split packages apart

A module cannot be declared while a package is split. Phase two therefore takes the splits apart first, one
package at a time, building after each:

| Split | Taken apart by |
| --- | --- |
| White-box tests | Moving them into packages of the test module's own, such as `<package>.test`, testing the public API where they can, and reaching the rest as the next section shows. |
| Two projects | Moving the classes so each package lives in one module, or merging the projects, with a qualified export for a package only a sibling uses. |
| A dependency | Excluding the jar that holds the package, or moving the project's classes out of it. |
| Two dependencies | Excluding one of the jars, or dropping the test that needs both. |

No module path holds a package two jars share. After a build of the `pom.xml`, this prints each package two
jars of a test closure hold:

```bash
for jar in $(find target/build -path '*/test-module-*/resolved/*.jar'); do
    unzip -Z1 "$jar" '*.class' 2>/dev/null | grep / | grep -v '^META-INF/' \
        | sed "s|/[^/]*$| ${jar##*/}|"
done | sort -u | cut -d' ' -f1 | uniq -d
```

### What the test module reaches

White-box tests reach what they need through the module system's own means rather than through a shared
package. A package the module does not export is made readable to the tests by one line, in both the
`process-javac.properties` and the `process-test.properties` of the test module:

```properties
--add-exports=demo.greeter/demo.greeter.internal=demo.greeter.test
```

A test module reads only what the tested module exports, when it compiles and when its tests run, so with the
line in the first file alone `javac` passes and the tests fail with an `IllegalAccessError`. The published
`module-info.java` stays as it is. An `exports <package> to <test module>` there would publish the export, and
`javac` would warn that the test module is not found when it compiles the main module.

A package-private member of a package the module exports already is called by reflection rather than made
public, which would widen the published API. JUnit's `ReflectionSupport` finds and invokes it, once
`--add-opens=demo.greeter/demo.greeter=org.junit.platform.commons` in `process-test.properties` opens the
package to the module that makes the member accessible.

A test `module-info.java` that names the main module itself, the `--patch-module` idiom Maven and Gradle use
for white-box tests, is not supported. The tests become a module of their own, as the table above takes them
apart.

### What tests on the module path break

The tests then run on the module path, which breaks what read the class path:

| What breaks | What to do |
| --- | --- |
| A class in the unnamed package | A module holds none, so a test class there fails to load. Move it into a package; a test that needs such a class compiles it at run time. |
| `javac` called by a test | compile-testing and `javax.tools` compile against `java.class.path`, which is empty now. Hand the compiler `-classpath` with `System.getProperty("jdk.module.path")`, or append that property to `java.class.path` before the tests run, from a `LauncherSessionListener` the test module provides. |
| Mockito and a JDK interface | Mocking an interface of a JDK module, as `java.compiler`'s `Element`, needs `org.mockito` to read that module: `--add-reads=org.mockito=java.compiler` in `process-test.properties`. |
| A jar that cannot be a module | A dependency with a class in the unnamed package, as JavaCC 8 has, fails the tests' module path with a `FindException`, and no dependency of a module stays on the class path alone. Move the tests that need it to a test source folder only the old build compiles. |

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
| A version | `@jenesis.pin <module> <version>` for a required module, `<groupId>/<artifactId>` for one a POM brings in, which `pin` writes; `@jenesis.bom` for a BOM. |
| The release | `@jenesis.release <N>`. |
| An annotation processor | `@jenesis.plugin maven/<groupId>/<artifactId>`. |
| The main class | `@jenesis.main <class>`. |
| `src/main/resources` | Moves into `src/main/java`: a file beside the sources is packaged. |
| The tests | A test module of their own, carrying `@jenesis.test <module>` and requiring the module and the test framework, with packages that differ from the tested module's. |
| Name and description | The first sentence and the second paragraph of the module's Javadoc. |
| The coordinate | Derived from the module name; `project` and `artifact` in `project.properties` keep a published one. |
| URL, licences, developers, SCM | `project.properties`. |
| The version | `version=<version>` in `project.properties` at the root, which `-Djenesis.project.version` overrides. |

### Keeping published coordinates

A module's coordinate follows from its name: the first two segments form the group ID and the whole name is
the artifact ID. A project whose artifacts were published under other coordinates keeps them. `project` and
`artifact` in `project.properties` at the root apply to every module, and a module that keeps a coordinate of
its own declares them in a `project.properties` of its own, in the `META-INF/build.jenesis/` folder beside its
sources, which wins over the root file for every key it names. *[Publishing](/tool/publishing/)* lists the
other keys the file holds.

Once the `pom.xml` files are gone, so is the version they held. Without a `version` in `project.properties` or
the setting, what is staged is unversioned and its POM carries `0-SNAPSHOT`.

## Pinning again

The pins `pin` wrote into a `pom.xml` do not carry over: until `pin` runs again, the module build resolves the
newest versions. Write a bare `@jenesis.pin <module> <version>` for each required module whose version to
keep, and `@jenesis.pin <groupId>/<artifactId> <version>` for one only a dependency's POM brings in, since a
module name reaches only a module that is required by it. A module name that would move such a module to
another version fails the build, naming the coordinate pin. Then run `pin`, which adds the checksums and the
closure. The module build resolves a conflict as a `pom.xml` does, so a version Gradle resolved higher is
pinned here as well.

## While the old build remains

The old build's `javadoc` fails on the `@jenesis` tags of a `module-info.java` as unknown, so register each tag
the module uses as disabled there. `javadoc` takes no wildcard: `-tag jenesis.pin:X` on its command line,
`tags("jenesis.pin:X")` among Gradle's javadoc options, or a
`<tag><name>jenesis.pin</name><placement>X</placement></tag>` in the `<tags>` of the maven-javadoc-plugin.

Maven's compiler plugin compiles a `src/test/java/module-info.java` whatever its `testExcludes` or
`useModulePath` say, and fails on the modules it requires. Have Maven compile a copy of the tests instead: a
`copy-resources` execution of the maven-resources-plugin at `generate-test-sources` copies the `*.java` files
of `src/test/java`, all but `module-info.java`, into a folder of `target/`, which `default-testCompile` names as
its only `compileSourceRoots`.

## What was shaded

Layers are declared in `module-info.java`, so a dependency the old build shaded to keep it private, which the
`pom.xml` build kept plain as *[Migrating a Maven or Gradle build](/tool/migrating/#shading)* describes, moves
into a [module layer](/tool/dependencies/#keeping-a-dependency-private) now.

`java build/jenesis/Make.java skill/migrate` prints this phase for a coding agent as well, beside the steps of
the first.

{% demos 2, 4, 66 %}
