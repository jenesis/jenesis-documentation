---
order: 8
title: Other JVM languages
description: Compiling Kotlin, Scala and Groovy through their language plugins - alone or mixed with Java in one module - the compile order that decides which packages you can export, the standard-library dependency each needs, and enabling a Kotlin or Scala compiler plugin.
---

Jenesis is not a Java-only build tool. Name a language plugin, drop `.kt`, `.scala` or `.groovy` sources into
a module, and the build resolves the matching compiler and builds them, mixed freely with Java, into one modular
jar and its generated POM, with **no build script to write**. One line of `jenesis.plugins.properties` names
each language at the hook point `language`:

```properties
# jenesis.plugins.properties
kotlin+language=build.jenesis.plugin.kotlin
scala+language=build.jenesis.plugin.scala
groovy+language=build.jenesis.plugin.groovy
```

A language plugin needs no `plugin-<name>.properties`. It runs in every module that holds a source of its
extension, and wires its compiler into the same step graph *[Core concepts](/tool/core-concepts/)* described.
The build compiles no language but Java itself, so a module holding a `.kt`, `.scala` or `.groovy` source
without the plugin of its language fails, naming the line to add. A `pom.xml` project reads a folder beside its source directories, such as `src/main/kotlin` and
`src/test/kotlin`, only where `jenesis.maven.sources` names it - `jenesis.maven.sources=kotlin,groovy` in
`jenesis.properties` reads the folders the Kotlin and GMavenPlus plugins read by default.

This chapter covers what changes when a module holds more than Java: how two compilers share one module, the one
rule that decides which packages you can export, the standard-library dependency each language needs, and how
to run a compiler plugin.

## One module, two compilers

A mixed module is compiled by **two compilers in sequence**. The build runs the language plugin's compiler
and `javac` in a fixed order over the same sources, each producing its own classes into the module. Because both
write into one module, the exported jar looks exactly like a single-language one - a consumer never sees the
seam.

The order is not arbitrary, and it differs by language:

| Language | Order | Why |
| --- | --- | --- |
| Kotlin | `kotlinc`, then `javac` | `kotlinc` reads `.java` as source for symbol resolution but emits only Kotlin classes |
| Scala | `scalac`, then `javac` | `scalac` reads `.java` as source for symbol resolution but emits only Scala classes |
| Groovy | `javac`, then `groovyc` | `groovyc` cannot read `.java` as source; it resolves Java from the compiled class path |

For Kotlin and Scala, the language compiler runs **first**: it reads your `.java` files only to resolve symbols
(so `Sample.kt` can call a Java `Greeter`) but leaves the Java output to `javac`, which compiles the `.java`
sources and `module-info.java` afterwards. For Groovy it is the mirror image: `javac` runs **first** and owns all
Java output, then `groovyc` compiles the `.groovy` sources, reaching Java types through the classes `javac`
already produced.

<div class="note">
  <strong>Who owns <code>module-info.java</code>.</strong> Neither <code>kotlinc</code> nor <code>scalac</code>
  is handed the module declaration; <code>javac</code> always owns it. For <code>scalac</code> that is a
  necessity, since its Java parser trips over the dotted module name. Both compilers still receive your other
  <code>.java</code> sources for resolution.
</div>

{% demos 46, 50, 52 %}

## Which packages you can export

That order decides one thing you need to know: **whether a package holding only non-Java code can be exported.**

When `javac` validates an `exports <package>` directive, it checks that the package is populated in the module's
output. For **Kotlin and Scala** this just works: their compiler already ran, so `javac` sees the Kotlin or Scala
classes through `--patch-module` and accepts the export. You can export a package that contains a single Kotlin
(or Scala) class and no Java type at all.

For **Groovy** you cannot. `groovyc` runs *after* `javac`, so at export-check time the package's Groovy classes
do not exist yet and only Java types count. The rule is:

<div class="warning">
  A package named in an <code>exports</code> directive must contain <strong>at least one Java type</strong> when
  the module also uses Groovy. Add a Java type to a Groovy package you want to export, or keep the package
  internal (a <code>requires</code> with no <code>exports</code>). This is a permanent Groovy restriction, not a
  Jenesis one - it follows from <code>groovyc</code> resolving Java only from the compiled class path.
</div>

## The standard-library dependency

Each language needs its standard library on the module path. You declare it as a normal `requires` in
`module-info.java`, and Jenesis resolves it through Maven like any other dependency:

| Language | `requires` | Resolves to |
| --- | --- | --- |
| Kotlin | `requires kotlin.stdlib;` | `org.jetbrains.kotlin:kotlin-stdlib` (plus its transitives) |
| Scala | `requires scala.library;` | `org.scala-lang:scala-library` |
| Groovy | `requires org.apache.groovy;` | `org.apache.groovy:groovy` |

The code compiles against what the module declares and nothing else - not against the libraries the compiler
itself runs on. Gradle's Kotlin plugin adds `kotlin-stdlib` to a project on its own, so a build moved from
Gradle declares it, as a `pom.xml` dependency or a `requires`, or `kotlinc` reports that it cannot access
`kotlin.Any`.

Groovy's jar carries an `Automatic-Module-Name`, so `org.apache.groovy` resolves as an automatic module. The
Scala standard library lives entirely in one module - `scala-library` - with `scala3-library_3` being an empty
aggregator, so nothing splits `package scala` across two modules and the Java Module System accepts it on the
module path with no hand-written wiring.

## Pinning the compiler

Every language compiler resolves in **the tool group of its plugin** - `kotlin:tool`, `scala:tool` or
`groovy:tool` - kept completely apart from your module's own `main`-group dependencies. That separation matters: the
running compiler is locked independently of the standard library your module ships against, so pinning a
different `kotlin-stdlib` for your code can never downgrade the `kotlinc` that compiles it. The documentation
tools and Zinc resolve beside them, in `kotlin:dokka`, `scala:scaladoc` and `scala:zinc`; Groovydoc shares the
`groovy:tool` group.

The compilers float a latest version by default. Run the `pin` step to record each resolved compiler jar with its
version and SHA-256, exactly as it pins your Java compilers and dependencies (see *[Pinning & bills of materials](/tool/pinning/)*):

```bash
java build/jenesis/Make.java pin
```

<div class="tip">
  For Scala and Groovy this is more than reproducibility. Their latest releases on Maven Central are often
  pre-release builds - a Scala <code>-RC</code> or a Groovy <code>-alpha</code>. An unpinned build skips a
  version with a pre-release qualifier while a version without one is published, and so takes the newest stable
  compiler of the day; pinning keeps the module on one compiler while you upgrade deliberately.
</div>

## Compiler arguments

A `process-kotlinc.properties` in a configuration folder hands `kotlinc` arguments of its own, written as
`process-javac.properties` writes them for `javac` (see *[Building & running](/tool/building-and-running/#passing-extra-arguments-to-a-tool)*):

```properties
# build.jenesis/process-kotlinc.properties
-api-version=2.0
-java-parameters=
-J-Xss4m=
```

Each line is an argument of the compiler. A `-J<option>` line or a `-D` line goes to the JVM that runs it
instead, as the `kotlinc` command passes them, so the last line gives that JVM `-Xss4m`. For Scala and Groovy,
`process-scalac.properties` and `process-groovyc.properties` configure the JVM each compiler runs in.

## Compiling incrementally

`-Djenesis.kotlin.incremental=true` compiles Kotlin incrementally, as Gradle does by default: after an edit, only
the sources the change reaches are compiled again. The compiler runs through the Kotlin Build Tools API, which needs
Kotlin 2.3 or newer, in the JVM every compilation of the build shares, rather than in Kotlin's own daemon. That JVM ends with the build, unless `jenesis.process.mode=daemon` keeps it for the next one. `-Djenesis.scala.incremental=true` compiles Scala with Zinc, the
incremental compiler sbt is built on, in the same way.

{% demos 46, 49 %}

## Tests and internal declarations

Kotlin's `internal` visibility ends at the module, and a module's tests reach into it all the same: the build
hands `kotlinc` the tested module's jar as a friend path when it compiles the tests, as Gradle and the Kotlin
Maven plugin do. A test that calls an `internal` function compiles without an argument of its own, in a
`pom.xml` build's test sources and in a module that names its tested module with `@jenesis.test`.

The build names a module for `kotlinc` after its artifact ID, as the Kotlin Maven plugin does, or after its
module name where it publishes no artifact, and its tests after that name with `_test` appended. It is the name
of the `META-INF/<name>.kotlin_module` file and the suffix of the binary name of an `internal` member. A
`-module-name` line in `process-kotlinc.properties` names the module otherwise.

{% demos 46 %}

## A compiler plugin

A Kotlin or Scala compiler plugin is declared exactly like a Java annotation processor
(*[Building & running](/tool/building-and-running/)*),
with one addition: **name the language plugin first**, so the compiler plugin resolves in that plugin's own group
rather than on `javac`'s processor path.

```java
/**
 * @jenesis.plugin kotlin:tool maven/org.jetbrains.kotlin/kotlin-serialization-compiler-plugin
 */
module demo.serialize {
    requires kotlinx.serialization.core;
}
```

Jenesis resolves the compiler plugin under the `kotlin:tool` group, and the Kotlin compiler picks up the jar and loads
it itself - you never name an entry point. Above, the `kotlinx.serialization` plugin generates a `@Serializable`
class's `serializer()`, and the `requires` provides the annotation and the runtime types the generated code
references. The Scala path is identical: `@jenesis.plugin scala:tool <coordinate>` resolves in the `scala:tool`
group, and `scalac` loads the plugin the same way.

<div class="warning">
  A plugin runs <strong>only because it is declared</strong>. Delete the <code>@jenesis.plugin</code> line and
  the plugin is no longer handed to the compiler - the generated code is never produced and the build fails to
  compile whatever referenced it. Nothing on the class or module path is scanned for plugins implicitly.
</div>

The plugin's version is pinned the usual way, coordinated to the compiler - the `pin` step writes back its
`@jenesis.pin` line for you.

{% demos 48 %}

## API documentation

When you build documentation jars (`jenesis.project.documentation`, *Building & running*), each language plugin
documents its own sources: Dokka for Kotlin, `scaladoc` for Scala, `groovydoc` for Groovy, beside `javadoc` for
Java. A module with one language and no Java is documented by that language's tool at the root of the
archive. Where a module mixes languages, `javadoc` renders the Java at the root and each other language renders
in a folder named after its plugin - `kotlin/`, `scala/` or `groovy/`. Either way the produced `-javadoc.jar`
always has a root `index.html`, so it satisfies a repository like Maven Central.

The Groovy plugin documents the module's Java sources with Groovydoc as well where its
`plugin-groovy.properties` sets `include-java=true`.

### Configuring Dokka

The `dokka.` values of a `plugin-kotlin.properties` in the module's configuration folder take the options the
Dokka Gradle plugin and the `dokka-maven-plugin` take. Every value is optional, and an unknown one fails the
build:

| Value | Meaning |
| --- | --- |
| `dokka.module-name` | the name the pages give the module, `documentation` unless set |
| `dokka.format` | `html`, the default, or `javadoc` for javadoc-styled pages |
| `dokka.documented-visibilities` | any of `public`, `protected`, `internal`, `private` and `package` |
| `dokka.suppress-obvious-functions`, `dokka.skip-empty-packages` | `true` unless set to `false` |
| `dokka.suppress-inherited-members`, `dokka.skip-deprecated`, `dokka.report-undocumented` | `false` unless set to `true` |
| `dokka.suppressed-packages` | regular expressions of packages to leave out, comma-separated |
| `dokka.fail-on-warning` | `true` fails the build on a warning of Dokka's |
| `dokka.jdk-version` | the Java feature release the JDK links point at |
| `dokka.source-link`, `dokka.source-link-suffix` | the URL of the module's sources, and the line suffix, `#L` unless set |
| `dokka.external-link.<name>`, `dokka.external-link.<name>.package-list` | documentation to link to, and its package list |
| `dokka.footer-message` | the footer of every page |

```properties
# sources/META-INF/build.jenesis/plugin-kotlin.properties
dokka.module-name=Kotlin demo
dokka.footer-message=Documented by Dokka, built by Jenesis
```

Dokka failing, including on a warning under `dokka.fail-on-warning=true`, fails the build.

{% demos 46 %}
