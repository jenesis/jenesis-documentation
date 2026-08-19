---
order: 6
title: Dependencies
description: Declaring dependencies in each layout, how they resolve over the Maven and module repositories, which version wins a conflict, pruning an unwanted transitive, and giving a nameless library a module name.
---

Every non-trivial build pulls in libraries. This chapter is about where you declare them, how Jenesis turns
each declaration into a downloaded jar, which version it settles on when two paths disagree, and the two
tags that let you correct a closure you do not control - dropping a transitive you do not want, and naming a
library that arrives without a module name of its own.

## Declaring a dependency

You never add a dependency in a build script. You declare it the same way the ecosystem already does, and the
place depends on your layout (see *[Core concepts](/tool/core-concepts/)*):

- A **`pom.xml`** project lists a dependency the normal Maven way, in `<dependencies>`:

  ```xml
  <dependency>
      <groupId>org.apache.commons</groupId>
      <artifactId>commons-text</artifactId>
      <version>1.12.0</version>
  </dependency>
  ```

- A **modular** project (`module-info.java`) declares a `requires`, and nothing else - the module name *is*
  the dependency:

  ```java
  module demo.app {
      requires com.fasterxml.jackson.databind;
  }
  ```

That is the whole surface. Jenesis reads these existing files, resolves the transitive closure, and puts the
result on the compile and runtime paths.

## The two repositories

Jenesis resolves through two named repositories, one per kind of coordinate:

- **`maven`** - Maven coordinates (`groupId:artifactId:version`). Fetched over HTTP from Maven Central
  (`https://repo1.maven.org/maven2/`) and hardlinked into your **local Maven repository** (`~/.m2/repository`),
  exactly where `mvn` keeps them.
- **`module`** - Java module names. Resolved through **repo.jenesis.build**, the module-name
  index that maps a name like `com.fasterxml.jackson.databind` to its artifact and 302-redirects to the file
  on Maven Central.

Which one a dependency uses follows from the layout. A `pom.xml` declares Maven coordinates, so it resolves
through `maven`. A `requires` names a module, so it resolves through `module` - and this is the step that turns
a module name into something downloadable. The **[Jenesis Modules](/modules/)** section documents that lookup
in full; the short version is that it is a thin, module-name-addressable mirror of Maven Central.

<div class="note">
  Under the default <code>modular_to_maven</code> layout, a <code>requires</code> is resolved to the declaring
  module's <em>Maven coordinate</em> (its POM is fetched through the module index), and transitive resolution
  then proceeds through Maven - so a module project reaches automatic-module and plain-classpath libraries too.
  The strict <code>modular</code> layout resolves purely by module name. <em>Core concepts</em> covers the
  difference; the <code>dependencies</code> selector below shows it concretely.
</div>

### Pointing at a different repository

To resolve through a corporate mirror or a private repository instead of the public defaults, set an
environment variable before the build - no project change required:

| Variable | What it overrides |
| --- | --- |
| `MAVEN_REPOSITORY_URI` | The Maven upstream. Accepts a comma-separated list, queried left to right; an entry may append `\|`-separated group ids to serve only those groups, and a bare `@` splices the default chain back in (`https://nexus.corp/,@`). |
| `MAVEN_REPOSITORY_TOKEN` | Sent verbatim as the `Authorization` header on every Maven fetch (e.g. `Bearer …` or `Basic …`). |
| `MAVEN_REPOSITORY_LOCAL` | The local Maven repository directory (default `~/.m2/repository`). |
| `JENESIS_REPOSITORY_URI` | The module-index base URL (default `https://repo.jenesis.build/`), with the same list/filter/`@` grammar. |
| `JENESIS_REPOSITORY_TOKEN` | The `Authorization` header for module-index fetches. |

<div class="warning">
  Fetches are refused over plaintext <code>http</code> - only <code>https</code> and <code>file</code> are
  allowed. A build that must pull from an internal <code>http</code> mirror has to opt in explicitly with
  <code>-Djenesis.repository.insecure=true</code>. A credential token is dropped before any redirect to a
  different host, so it never leaks to a redirect target.
</div>

## Seeing what resolved

The `dependencies` selector prints each module's resolved tree, the way `mvn dependency:tree` does:

```bash
java build/jenesis/Project.java dependencies
```

Each node shows the version every parent requested, the **negotiated** version inline when it differs
(`[1,2] -> 2`), the scope, the dependency's licence (`{Apache-2.0}`), and `local` for a module built inside
this project rather than fetched. A per-module *Resolved dependencies* list and a licence summary follow the
tree. It is the fastest way to answer "why is this version on my class path?" before you pin anything.

For a large closure, `-Djenesis.tree.format=compact` prints each dependency once instead of at every place it
is reached - the shape to skim when you only want the set, not the paths through it.

## Version negotiation

When two paths through the graph ask for different versions of the same library, Jenesis picks one. The rule
matches the repository:

- **Maven** coordinates use Maven's own **nearest-wins** conflict resolution, and understand version ranges
  and the `LATEST`/`RELEASE` selectors - the same behaviour `mvn` gives you.
- **Module** names use **first-parent-wins**: the first requirer reached in the resolution walk fixes the
  version, and a later, deeper requirer asking for a different version is ignored.

To override the negotiated result, declare the version you want directly - a `<version>` (or a
`<dependencyManagement>` entry) in Maven, or a **pin** in a modular project (below). A declared version always
beats what negotiation would have chosen.

### Choosing a different strategy

Each repository's rule is the sensible default, and each is selectable when you want another. On the Maven
side, `-Djenesis.resolver.maven` takes four values:

| Value | Rule |
| --- | --- |
| `maven` | *(the default)* Maven's own: declared versions, ranges and `RELEASE`/`LATEST` resolved from repository metadata, nearest-wins on a conflict, with ranges intersected when one competes. |
| `closest` | The same minus the range arbitration - the nearest declaration simply stands, and no metadata is fetched to settle a conflict. |
| `latest` / `release` | Ignore every declared version and take the `<latest>` or `<release>` entry of each coordinate's metadata. |

On the module side, `-Djenesis.resolver.module` decides what happens when two compiled `module-info` files
record different versions of the same requirement: `first` (the default) keeps the one nearest the roots,
`fail` reports the disagreement instead of discarding one, and `ignore` keeps no compiled version at all.

<div class="warning">
  <code>latest</code> and <code>release</code> are <strong>upgrade probes, not build modes</strong>. They
  override pinned versions too, so the checksum recorded beside a pin no longer describes the artifact that
  resolves and stops applying - under strict pinning the build then fails. Use them to find out what an
  upgrade would pull in, then record the result with <code>pin</code>.
</div>

## Excluding a transitive

A dependency can drag in a transitive you do not want. Pruning it is a Maven mechanism - an exclusion tells
the resolver to skip a subtree of a POM - so it is available wherever a POM is read: in the `maven` layout,
and in the default `modular_to_maven` layout, whose `requires` resolve through Maven.

In a `pom.xml` it is an `<exclusions>` block, exactly as in Maven - the excluded artifact never reaches the
class path, tests included:

```xml
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-text</artifactId>
    <version>1.12.0</version>
    <exclusions>
        <exclusion>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-lang3</artifactId>
        </exclusion>
    </exclusions>
</dependency>
```

A `module-info.java` states the same thing as a tag, since it has no `<dependencies>` block to hang it on:

```java
/**
 * @jenesis.exclude org.apache.commons.text org.apache.commons/commons-lang3
 */
module demo.sample {
    requires org.apache.commons.text;
}
```

One line names the module to prune and any number of `<groupId>/<artifactId>` targets, and repeated lines for
the same module add up, so a growing list of upstream mistakes stays readable. A target is an artifact, never
one of its variants, so it carries no version, type, or classifier. Excluding from a module the declaration
does not `requires` is an error rather than a silent no-op - it is a typo in every case that matters.

Either way the artifact takes the whole subtree it pulled in with it, and because it never enters the resolved
closure there is nothing left to leak: it is off the compile and test paths, absent from the generated POM, and
absent from the bill of materials and the compliance reports, which is the honest answer - the build genuinely
never fetched it.

<div class="note">
  The strict <code>modular</code> layout is the one place this does not apply. Resolution there matches module
  descriptors and never reads a POM, so there is no transitive POM dependency to prune and the tag is rejected
  rather than ignored. Nothing is lost: a module only ever sees what it <code>requires</code>.
</div>

## Naming a library that has no module name

Some libraries still ship as a plain jar: no `module-info`, and not even an `Automatic-Module-Name`. On the
module path such a jar becomes an automatic module named after its *file*, which changes with the file and so
cannot be `requires`d reliably. An **alias** gives one a name your project chooses:

```java
/**
 * @jenesis.alias org.kohsuke.args4j args4j/args4j
 */
module demo.cli {
    requires org.kohsuke.args4j;

    opens demo.cli to org.kohsuke.args4j;
}
```

The tag maps a module name onto a `<groupId>/<artifactId>` the resolved closure already contains, and the name
is then a module name like any other - the `opens` above is what lets args4j set the annotated fields by
reflection. Nothing is synthesized and no jar is rewritten: the artifact is placed under the aliased file name,
which is exactly the name the JDK derives an automatic module from, so a pinned checksum keeps describing the
bytes on the command line.

Two rules keep an alias predictable. It carries **no version** - the version comes from a pin, a bill of
materials, or the closure the alias names, and is stated in one place only. And it only ever *renames*: a jar
that already declares a `module-info` or an `Automatic-Module-Name` is rejected, because it is addressable
under that name already. An alias also travels: a project that depends on a module which declared one inherits
the name without redeclaring it.

<div class="tip">
  An alias does not have to be something you <code>requires</code> yourself. Naming a transitive dependency
  the project never mentions is enough to make it a module every other module can require - which is how a
  closure of plain jars is brought onto the module path one deliberate name at a time.
</div>

Aliases are a `modular_to_maven` feature: they reach an artifact by its Maven coordinate, which the strict
`modular` layout does not use.

<div class="tip">
  Two runnable projects cover this chapter:
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-27-maven-exclusions">demo-27</a> excludes
  Commons Lang from Commons Text and proves with a test that it is gone - in a POM, with the tag form beside
  it; and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-31-module-alias">demo-31</a> gives args4j -
  a library with no module identity at all - a name of its own and opens a package to it. Each is a runnable
  project - see <a href="/tool/demos/">Demos</a>.
</div>
