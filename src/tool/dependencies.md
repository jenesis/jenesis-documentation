---
order: 6
title: Dependencies
description: Declaring dependencies in each layout, how they resolve through Maven Central and the Jenesis Module Index, which version wins a conflict, pruning an unwanted transitive, and giving a nameless library a module name.
---

Every non-trivial build pulls in libraries. This chapter is about where you declare them, how Jenesis turns
each declaration into a downloaded jar, and which version it settles on when two paths disagree. It ends with
the two tags that let you correct a closure you do not control: dropping a transitive you do not want, and
naming a library that arrives without a module name of its own.

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

- **`maven`** - Maven coordinates (`groupId:artifactId:version`). Fetched over HTTPS from Maven Central
  (`https://repo1.maven.org/maven2/`) into your **local Maven repository** (`~/.m2/repository`), exactly
  where `mvn` keeps them, and hard-linked from there into the build.
- **`module`** - Java module names. Resolved through the **Jenesis Module Index** at `repo.jenesis.build`,
  which maps a name like `com.fasterxml.jackson.databind` to its artifact and redirects to the file on Maven
  Central.

Which one a dependency uses follows from the layout. A `pom.xml` declares Maven coordinates, so it resolves
through `maven`. A `requires` names a module, so it resolves through `module`, and this is the step that turns
a module name into something downloadable. The **[Jenesis Module Index](/modules/)** section documents that
lookup in full.

<div class="note">
  Under the default <code>modular_to_maven</code> layout, a <code>requires</code> is resolved to the declaring
  module's <em>Maven coordinate</em> (its POM is fetched through the module index), and transitive resolution
  then proceeds through Maven. A module project therefore reaches automatic-module and plain class-path
  libraries too. The strict <code>modular</code> layout resolves purely by module name. <em>Core concepts</em>
  covers the difference; the <code>dependencies</code> selector below shows it concretely.
</div>

### Pointing at a different repository

To resolve through a corporate mirror or a private repository instead of the public defaults, set a system
property or an environment variable before the build. No project change is required, and a property beats
the variable of the same name:

| Property (environment variable) | What it overrides |
| --- | --- |
| `jenesis.maven.uri` (`MAVEN_REPOSITORY_URI`) | The Maven upstream. Accepts a comma-separated list, queried left to right; an entry may append `\|`-separated group ids to serve only those groups, and a bare `@` splices the default chain back in (`https://nexus.corp/,@`). |
| `jenesis.maven.token` (`MAVEN_REPOSITORY_TOKEN`) | Sent verbatim as the `Authorization` header on every Maven fetch (e.g. `Bearer …` or `Basic …`; a [Jenesis Repository](/repository/authentication/) key can be given as is). |
| `jenesis.maven.local` (`MAVEN_REPOSITORY_LOCAL`) | The local Maven repository directory (default `~/.m2/repository`). |
| `jenesis.module.uri` (`JENESIS_REPOSITORY_URI`) | The module index base URL (default `https://repo.jenesis.build/`), with the same list/filter/`@` grammar. |
| `jenesis.module.token` (`JENESIS_REPOSITORY_TOKEN`) | The `Authorization` header for module fetches, when `jenesis.module.uri` points at a server that needs one. |
| `jenesis.module.local` (`JENESIS_REPOSITORY_LOCAL`) | The local module repository directory (default `~/.jenesis`). |

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

When the whole closure is more than you want to read, `-Djenesis.tree.format` narrows what the trees show:

| Value | What it prints |
| --- | --- |
| `full` | *(the default)* Every module's graph in full, external closure and all. |
| `compact` | Only the `local` modules, with everything external folded into a count per branch, so a large multi-module project shows its own shape at a glance. |

`-Djenesis.tree.tests=false` is a second, independent switch that applies under either format. It leaves out
the test modules (see *[Building and running](/tool/building-and-running/)*), which are not part of what the
project releases, so neither the trees nor the licence summary count what only a test run pulls in.

## Version negotiation

When two paths through the graph ask for different versions of the same library, Jenesis picks one. The rule
matches the repository:

- **Maven** coordinates use Maven's own **nearest-wins** conflict resolution, and understand version ranges
  and the `LATEST`/`RELEASE` selectors - the same behaviour `mvn` gives you.
- **Module** names use **first-parent-wins**: the first requirer reached in the resolution walk fixes the
  version, and a later, deeper requirer asking for a different version is ignored.

To override the negotiated result, declare the version you want directly: a `<version>` (or a
`<dependencyManagement>` entry) in Maven, or a **pin** in a modular project (the next chapter). A declared
version always beats what negotiation would have chosen.

### Choosing a different strategy

Each repository's rule is the sensible default, and each is selectable when you want another. On the Maven
side, `-Djenesis.resolver.maven` takes four values:

| Value | Rule |
| --- | --- |
| `maven` | *(the default)* Maven's own: declared versions, ranges and `RELEASE`/`LATEST` resolved from repository metadata, nearest-wins on a conflict, with ranges intersected when one competes. |
| `closest` | The same minus the range arbitration - the nearest declaration simply stands, and no metadata is fetched to settle a conflict. |
| `latest` / `release` | Ignore every declared version and take the `<latest>` or `<release>` entry of each coordinate's metadata. |

On the module side, `-Djenesis.resolver.module` decides what happens when two compiled `module-info` files
record different versions of the same requirement. `first` (the default) keeps the one nearest the roots,
`fail` reports the disagreement instead of discarding one, and `ignore` keeps no compiled version at all.

<div class="warning">
  <code>latest</code> and <code>release</code> are <strong>upgrade probes, not build modes</strong>. They
  override pinned versions too, so the checksum recorded beside a pin no longer describes the artifact that
  resolves and stops applying - under strict pinning the build then fails. Use them to find out what an
  upgrade would pull in, then record the result with <code>pin</code>.
</div>

## Excluding a transitive

A dependency can drag in a transitive you do not want. Pruning it is a Maven mechanism (an exclusion tells
the resolver to skip a subtree of a POM), so it is available wherever a POM is read: in the `maven` layout,
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

One line names the module to prune and any number of `<groupId>/<artifactId>` targets. Repeated lines for
the same module add up, so a growing list of upstream mistakes stays readable. A target is an artifact, never
one of its variants, so it carries no version, type, or classifier. Excluding from a module the declaration
does not `requires` is an error rather than a silent no-op, because it is a typo in every case that matters.

Either way the artifact takes the whole subtree it pulled in with it. Because it never enters the resolved
closure, there is nothing left to leak: it is off the compile and test paths, absent from the generated POM,
and absent from the bill of materials and the compliance reports. The build never fetched it.

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
is then a module name like any other; the `opens` above is what lets args4j set the annotated fields by
reflection. Nothing is synthesised and no jar is rewritten. The artifact is placed under
`<alias>-<version>.jar`, which is exactly the name the JDK derives that automatic module and its version
from, so a stack trace out of it reads `org.kohsuke.args4j@2.33` and a pinned checksum keeps describing the
bytes on the command line.

Two rules keep an alias predictable. The declaration carries **no version**: the version comes from a pin, a
bill of materials, or the closure the alias names, is stated in one place only, and is what the file name
then carries. And it only ever *renames*: a jar
that already declares a `module-info` or an `Automatic-Module-Name` is rejected, because it is addressable
under that name already. An alias also travels. A project that depends on a module which declared one
inherits the name without redeclaring it.

<div class="tip">
  An alias does not have to be something you <code>requires</code> yourself. Naming a transitive dependency
  the project never mentions is enough to make it a module every other module can require. That is how a
  closure of plain jars is brought onto the module path one deliberate name at a time.
</div>

Aliases are a `modular_to_maven` feature: they reach an artifact by its Maven coordinate, which the strict
`modular` layout does not use.

## Replacing a module another artifact already carries

A package belongs to exactly one module, and a library that needs an API `requires` the module owning it.
Occasionally one does not: it copies the API's classes into its own jar and exports those packages under its
own name. Tomcat Embed is the notable case. `org.apache.tomcat.embed.core` exports the `jakarta.servlet`
packages itself, `org.apache.tomcat.embed.el` exports `jakarta.el`, and none of them depends on the API
artifact.

That leaves two modules exporting one package, which a module descriptor is meant to prevent. It breaks more
than your own code. A modular library names the API the only way a module can, in its descriptor - the
Jakarta Server Pages API states `requires transitive jakarta.servlet` - so a module of that name has to be on
the path or it does not resolve at all. Tomcat supplies the packages but not the name, and adding the API
artifact beside it carries the packages twice:

```
error: module not found: jakarta.el
error: module demo.override reads package jakarta.servlet
       from both jakarta.servlet and org.apache.tomcat.embed.core
```

An **override** states the relationship once, naming the module to replace and the modules that already carry
its packages:

```java
/**
 * @jenesis.override jakarta.servlet org.apache.tomcat.embed.core
 * @jenesis.override jakarta.el org.apache.tomcat.embed.el
 */
module demo.override {
    requires jakarta.servlet;
    requires jakarta.servlet.jsp;
    requires org.apache.tomcat.embed.core;
    requires org.apache.tomcat.embed.el;
}
```

Jenesis then places a module of that name which holds no packages of its own and requires each carrier
transitively. Reading it reads the carrier's copy under the API's name, because readability is what a
`requires` grants and the packages come from the carrier's own exports. One line names one module and any
number of carriers, repeated lines add up, and a carrier no resolved dependency declares is an error rather
than a silent no-op.

The declaration also drops every resolved artifact that declares the overridden module, whether it was
required directly or arrived through somebody else's POM. The closure therefore carries those packages once,
and so does the generated POM - a Maven consumer flattening this project onto a class path gets the carrier's
copy and no second one. Your published descriptor still says `requires jakarta.servlet`, which is the point:
it names the API rather than the server implementing it here. Consumers that build with Jenesis inherit the
declaration through the `Jenesis-Overrides` manifest attribute of the produced jar.

Two limits follow from the placed module holding no code. A qualified `exports … to jakarta.servlet` or
`opens … to jakarta.servlet` grants access to that module, not to the carrier that does the reflecting, so
open to the carrier or leave the directive unqualified. And requiring it reads everything the carrier exports,
so code can compile against `org.apache.catalina` while declaring only `requires jakarta.servlet`.

Overrides are a `modular_to_maven` feature, for the same reason aliases are: dropping the replaced artifact
means reaching it by its Maven coordinate. The strict `modular` layout rejects the tag.

<div class="note">
  Two artifacts that declare the same module name are refused wherever they meet, override or not. A module
  path resolves whichever of them comes first, so the build names both coordinates and stops rather than
  compiling against one and running against the other.
</div>

<div class="tip">
  Three runnable projects cover this chapter:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-30-maven-exclusions">demo-30</a> excludes
  Commons Lang from Commons Text and proves with a test that it is gone - in a POM, with the tag form beside
  it; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-34-module-alias">demo-34</a> gives args4j -
  a library with no module identity at all - a name of its own and opens a package to it; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-35-module-override">demo-35</a> puts the
  Jakarta Server Pages API, a modular library, on a module path with Tomcat Embed, which carries the servlet
  packages itself. Each is a runnable project - see <a href="/tool/demos/">Demos</a>.
</div>
