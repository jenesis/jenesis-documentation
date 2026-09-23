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
      requires org.apache.commons.text;
  }
  ```

That is the whole surface. Jenesis reads these existing files, resolves the transitive closure, and puts the
result on the compile and runtime paths.

A `requires` names no version, so Jenesis takes the newest release of the module, leaving out pre-releases.
To hold a module at a version of your choosing, name it in a `@jenesis.pin` tag in the comment above the
declaration:

```java
/**
 * @jenesis.pin org.apache.commons.text 1.12.0
 */
module demo.app {
    requires org.apache.commons.text;
}
```

The tag takes the module name and the version, and applies wherever that module turns up in the closure,
directly or through another module. Jenesis can also write these tags for you, fixing each module at the version it
resolved, as *[Recording the pins](/tool/pinning/#recording-the-pins)* in the next chapter describes.

## The two repositories

Jenesis resolves through two named repositories, one per kind of coordinate. Each comes with a default
source, and either can be [pointed elsewhere](#pointing-at-a-different-repository):

- **`maven`** - Maven coordinates (`groupId:artifactId:version`). By default fetched over HTTPS from Maven
  Central (`https://repo1.maven.org/maven2/`) into your **local Maven repository** (`~/.m2/repository`),
  exactly where `mvn` keeps them, and hard-linked from there into the build.
- **`module`** - Java module names. By default resolved through the **Jenesis Module Index** at
  `repo.jenesis.build`, which maps a name like `com.fasterxml.jackson.databind` to its artifact and redirects
  to the file on Maven Central.

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
| `jenesis.module.source` | Who resolves a module name: `service` (the default) asks the index at `jenesis.module.uri`, `git` reads the index's published data itself and fetches what it resolves to from `jenesis.maven.uri`. |
| `jenesis.module.index` (`JENESIS_INDEX_URI`) | Where that published data is read from when `git` resolves, a folder of per-module files (default: the `data/modules/` folder of the [`jenesis/jenesis-modules`](https://github.com/jenesis/jenesis-modules/tree/main/data/modules) repository). A fork or a mirror of it stands in here, as `jenesis.module.uri` stands in for the index itself. |

<div class="warning">
  Fetches are refused over plaintext <code>http</code> - only <code>https</code> and <code>file</code> are
  allowed. A build that must pull from an internal <code>http</code> mirror has to opt in explicitly with
  <code>-Djenesis.repository.insecure=true</code>. A credential token is dropped before any redirect to a
  different host, so it never leaks to a redirect target.
</div>

{% demos 59 %}

### What the build tells the module index

The [module index](/modules/resolving/) does not serve jars, it redirects to them, and three of its
choices are the build's to make. Jenesis states each one only when you have configured it, so an
unconfigured build leaves every choice with the index and gets the same answer any other client gets.

| What you set | What the index is told |
| --- | --- |
| `jenesis.maven.uri` (`MAVEN_REPOSITORY_URI`) | Redirect to the same repository Jenesis resolves Maven artifacts from, so module jars and Maven artifacts come from one host rather than two that disagree on what exists yet. |
| `jenesis.module.prerelease` | Whether a module asked for without a version may resolve to a pre-release. |
| `jenesis.module.speculative` | Whether a version the index has not recorded may be resolved from the module's newest coordinate, rather than answering that it has never seen it. |

The last two are choices rather than questions, so they hold either way. With `jenesis.module.source=git`
the build asks no service at all. It reads the index's data from the
[`jenesis/jenesis-modules`](https://github.com/jenesis/jenesis-modules/tree/main/data/modules) repository on
GitHub, one file per module, which can be cloned or forked like any other repository; `jenesis.module.index`
points a build at such a copy. No build therefore has to rely on an index that Jenesis hosts. The two choices
are applied there by the same rule the index applies - a version counts as a release when the version a
module is keyed by and the Maven version it resolves to both carry no pre-release qualifier.

Not every repository can be named to a third party, and Jenesis says nothing rather than guess: an entry
restricted to some groups cannot stand for the redirect of a module outside them, an `@` reference is not
expanded here, and a `file:` repository or one carrying credentials has no URL the index could use. Only
a repository reached over `http` or `https` is told anything at all.

## Seeing what resolved

The `dependencies` selector prints each module's resolved tree, the way `mvn dependency:tree` does:

```bash
java build/jenesis/Make.java dependencies
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

When two paths through the graph ask for different versions of the same library, Jenesis picks one. By
default, the rule matches the repository:

- **Maven** coordinates use Maven's own **nearest-wins** conflict resolution, and understand version ranges
  and the `LATEST`/`RELEASE` selectors - the same behaviour `mvn` gives you.
- **Module** names use **first-parent-wins**: the first requirer reached in the resolution walk fixes the
  version, and a later, deeper requirer asking for a different version is ignored.

To override the negotiated result, declare the version you want directly: a `<version>` (or a
`<dependencyManagement>` entry) in Maven, or a [`@jenesis.pin`](#declaring-a-dependency) tag in a modular
project. A declared version always beats what negotiation would have chosen.

### Choosing a different strategy

Each repository's rule is the sensible default, and each is selectable when you want another. On the Maven
side, `-Djenesis.resolver.maven` takes:

| Value | Rule |
| --- | --- |
| `maven` | *(the default)* Maven's own: declared versions, ranges and `RELEASE`/`LATEST` resolved from repository metadata, nearest-wins on a conflict, with ranges intersected when one competes. |
| `closest` | The same minus the range arbitration - the nearest declaration simply stands, and no metadata is fetched to settle a conflict. |
| `latest` / `release` | Ignore every declared version and take the `<latest>` or `<release>` entry of each coordinate's metadata. |
| `stable` | Like `release`, but skipping every version whose qualifier marks it a pre-release - a milestone, a release candidate, an early-access build. |
| `fail` | Refuse to arbitrate: a coordinate two dependencies require at different versions stops the build, naming both versions. |
| `managed` | `fail`, and additionally refuse any version the project did not name itself - see below. |

On the module side, `-Djenesis.resolver.module` decides what happens when two compiled `module-info` files
record different versions of the same requirement. `first` (the default) keeps the one nearest the roots,
`fail` reports the disagreement instead of discarding one, `ignore` keeps no compiled version at all, and
`managed` is `fail` plus the rule below.

### Letting nothing in that you did not name

`fail` turns a silent decision into a stopped build. `managed` goes one step further: every version that
reaches the closure has to be one the project named.

```
-Djenesis.resolver.maven=managed
-Djenesis.resolver.module=managed
```

On the Maven side that means a coordinate the project neither declares itself nor names in dependency
management - one that arrived only because a dependency's own POM mentioned it - stops the build:

```
No managed version for com.fasterxml.jackson.core:jackson-core which resolved to 2.22.1
as another dependency's POM declares it (add it to dependencyManagement, or run the pin selector)
```

On the module side the rule is the same: a module reached only through another module's `requires` stops
the build unless the project names its version itself, in a [`@jenesis.pin`](#declaring-a-dependency) tag. A module the project declares itself - a sibling of a
multi-project build among them - is a declaration of the project and passes.

<div class="warning">
  <code>latest</code> and <code>release</code> are <strong>upgrade probes, not build modes</strong>. They
  override pinned versions too, so the checksum recorded beside a pin no longer describes the artifact that
  resolves and stops applying - under strict pinning the build then fails. Use them to find out what an
  upgrade would pull in, then record the result with <code>pin</code>.
</div>

### How fresh the metadata is

Anything that resolves from repository metadata - a range, `RELEASE`, `LATEST`, `STABLE` - is only as current
as the `maven-metadata.xml` behind it, so Jenesis reads that file from the repository every time it resolves
one. There is no expiry to tune and no `-U` to remember: a version that appeared five minutes ago is found on
the next resolution.

The copy kept in `.jenesis/artifacts` is the fallback, not the source. It is rewritten on every successful
read and used only when the repository cannot be reached, so a build that resolved once keeps resolving
offline, at the versions it last saw. Nothing is written into `~/.m2/repository`, whose `maven-metadata.xml`
belongs to Maven.

A resolution is still only repeated when the dependency set changes, because the step that performs it is
cached like every other. `RELEASE` therefore means *the newest version as of the last resolution*, which is
what `pin` exists to make explicit.

## Excluding a transitive

A dependency can drag in a transitive you do not want. Pruning it is a Maven mechanism, so it works wherever
a POM is read: the `maven` layout, and the default `modular_to_maven`, whose `requires` resolve through
Maven. In a `pom.xml` it is the usual `<exclusions>` block:

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

One line names the module to prune and any number of `<groupId>/<artifactId>` targets; repeated lines add up.
A target is an artifact rather than one of its variants, so it carries no version, type or classifier, and
excluding from a module the declaration does not `requires` is an error rather than a silent no-op.

Either way the artifact takes its whole subtree with it and never enters the resolved closure: off the
compile and test paths, absent from the generated POM, the bill of materials and the compliance reports. The
build never fetched it.

<div class="note">
  The strict <code>modular</code> layout is the one place this does not apply. Resolution there matches module
  descriptors and never reads a POM, so there is no transitive POM dependency to prune and the tag is rejected
  rather than ignored. Nothing is lost: a module only ever sees what it <code>requires</code>.
</div>

{% demos 16 %}

## Naming a library that has no module name

Some libraries still ship as a plain jar: no `module-info`, and not even an `Automatic-Module-Name`. On the
module path such a jar becomes an automatic module named after its *file*, which changes with the file and so
cannot be `requires`d reliably. An **alias** gives one a name your project chooses. That works for a jar you
require yourself and equally for a transitive dependency your project never mentions, which would otherwise
be loaded on the class path. A closure of plain jars is brought onto the module path this way, one
deliberate name at a time:

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
reflection. Nothing is synthesised and no jar is rewritten.

Aliases are a `modular_to_maven` feature: they reach an artifact by its Maven coordinate, which the strict
`modular` layout does not use.

{% demos 18 %}

## Replacing a module another artifact already carries

Few projects need this. A handful of libraries use the Java Module System incorrectly: rather than requiring
an API's module, they copy its packages into their own jar. Tomcat Embed is one of them, as
`org.apache.tomcat.embed.core` exports the `jakarta.servlet` packages itself. A library that correctly
`requires jakarta.servlet` then cannot share a module path with Tomcat, because two modules would export one
package.

An **override** names the module to replace and the module that already carries its packages:

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

Jenesis drops the replaced artifact from the closure and puts a module of that name in its place, which reads
the carrier's copy of the packages. `requires jakarta.servlet` keeps meaning what it says, in your code and in
the libraries you depend on. Like aliases, overrides need the `modular_to_maven` layout.

{% demos 20 %}

## Keeping a dependency private

Every section so far assumed the module path can hold what the build resolves. It cannot always. A module
path admits one module per name, so a library that needs a different version of some dependency than its
consumer has nowhere to put it. The usual answer elsewhere is shading: rewrite the dependency's bytecode
under new package names and copy it in. That takes reflection, `Class.forName`, resource lookup,
`META-INF/services`, jar signatures and stack traces with it, and it leaves the seam implicit.

The JVM already has the mechanism for this, and it serves the class path just as well as the module path. A
second copy of a library goes behind a class loader of its own and keeps every package name it had; for
modules, that loader backs a `ModuleLayer` of its own. Jenesis lets the module that needs the isolation
declare it:

```java
/**
 * @jenesis.layer render api      my.library.spi
 * @jenesis.layer render provider com.example.renderer
 */
module my.library {
    requires build.jenesis.launcher;
    requires my.library.spi;
}
```

Two lines, and each says which side it declares. `api` names the one module the library shares with the
layer; `provider` names a root the layer holds, and its whole closure comes with it. Repeat the `provider`
line for more roots. A root is a module name, as here, or any other coordinate, such as
`maven/<groupId>/<artifactId>`, and the layer resolves in a dependency group of its own,
`layer:render`. A pin for something in the layer carries that group in front, as in
`@jenesis.pin layer:render/maven/com.fasterxml.jackson.core/jackson-core 2.15.4`.

The library reaches its layer by name, and gets back the implementation:

```java
Report report = Launcher.instance("render", Report.class);
```

**Consumers declare nothing.** They require the library and know nothing of what it hides; a consumer may
even resolve a different version of the same dependency for itself. The declaration travels to them in the
`Jenesis-Layer` manifest attribute of the produced jar, exactly as an alias or an override does, and any
build that resolves that jar reconstructs the layer from it. Discovery runs to a fixpoint, so a module
inside a layer may isolate a dependency of its own, without limit.

{% demos 21 %}

### Libraries that name themselves nowhere

A layer splits a module path and a class path exactly as an application does, because the libraries worth
isolating are usually the ones that were never modularized. What carries a module identity - a
`module-info`, an `Automatic-Module-Name`, or a name you give it with `@jenesis.alias` - is resolved into
the layer. The rest is the layer's own class path, read by the layer's automatic modules as they would read
a plain `-cp`.

So a legacy tree costs one line, for the jar your code actually calls:

```java
/**
 * @jenesis.alias commons.beanutils commons-beanutils/commons-beanutils
 */
module my.library.impl {
    requires commons.beanutils;
    requires my.library.spi;

    provides my.library.spi.Beans with my.library.impl.ConvertingBeans;
}
```

Commons Logging and Commons Collections arrive as Commons BeanUtils' own dependencies, are named nowhere,
and become the layer's class path. One rule of the Java Module System decides how this can be used: only an
automatic module reads the unnamed module, which is why the alias matters - a jar with no identity becomes
an *automatic* module when you name it, and an automatic module can read a class path. A module with a
descriptor of its own cannot, and `javac` will not let it try.

{% demos 22 %}

### What the build refuses

Each of these is reported when it is declared, naming what to write instead:

- a layer declared without `requires build.jenesis.launcher`, the module a layer is reached through;
- a layer that names an API module but nothing to isolate, or something to isolate but no API module;
- an API module the declaring module does not itself require;
- a `requires` on a module the same module isolates - it is off that module's path, and `javac` would say
  so anyway;
- a layer that isolates nothing, because the API module already shares all of it;
- a layer that provides a contract it also holds, which would look the service up against a different class
  of the same name and find no provider;
- a layer that holds no module at all, since a layer is reached through the modules it holds;
- two layers of one name, because a name is global - it is the dependency group the layer resolves in.

<div class="note">
  A layer is defined while the JVM runs, so a packaging that resolves its module graph ahead of time refuses
  a project that declares one rather than flattening it.
</div>
