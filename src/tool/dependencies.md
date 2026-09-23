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
| `jenesis.module.source` | Who resolves a module name: `service` (the default) asks the index at `jenesis.module.uri`, `git` reads the index's published data itself and fetches what it resolves to from `jenesis.maven.uri`. |
| `jenesis.module.index` (`JENESIS_INDEX_URI`) | Where that published data is read from when `git` resolves, a folder of per-module files (default: the data published on GitHub). A fork or a mirror of it stands in here, as `jenesis.module.uri` stands in for the index itself. |

<div class="warning">
  Fetches are refused over plaintext <code>http</code> - only <code>https</code> and <code>file</code> are
  allowed. A build that must pull from an internal <code>http</code> mirror has to opt in explicitly with
  <code>-Djenesis.repository.insecure=true</code>. A credential token is dropped before any redirect to a
  different host, so it never leaks to a redirect target.
</div>

### What the build tells the module index

The [module index](/modules/resolving/) does not serve jars, it redirects to them, and three of its
choices are the build's to make. Jenesis states each one only when you have configured it, so an
unconfigured build leaves every choice with the index and gets the same answer any other client gets.

| What you set | What the index is told |
| --- | --- |
| `jenesis.maven.uri` (`MAVEN_REPOSITORY_URI`) | Redirect to the same repository Jenesis resolves Maven artifacts from, so module jars and Maven artifacts come from one host rather than two that disagree on what exists yet. |
| `jenesis.module.prerelease` | Whether a module asked for without a version may resolve to a pre-release. |
| `jenesis.module.speculative` | Whether a version the index has not recorded may be resolved from the module's newest coordinate, rather than answering that it has never seen it. |

The last two are choices rather than questions, so they hold either way: with
`jenesis.module.source=git` the build reads the published data itself and applies them there, by the same rule
the index applies - a version counts as a release when the version a module is keyed by and the Maven version
it resolves to both carry no pre-release qualifier.

Not every repository can be named to a third party, and Jenesis says nothing rather than guess: an entry
restricted to some groups cannot stand for the redirect of a module outside them, an `@` reference is not
expanded here, and a `file:` repository or one carrying credentials has no URL the index could use. Only
a repository reached over `http` or `https` is told anything at all.

## Seeing what resolved

The `dependencies` selector prints each module's resolved tree, the way `mvn dependency:tree` does:

```bash
java build/jenesis/Make.java dependencies
```

Each module gets one tree per scope, starting from the module itself and written like any other node: the
coordinate it is published under, its version, the scope and its module name, tagged `local` with the folder
it is built from (`maven/greeter/greeter 1-SNAPSHOT [compile] (module greeter, local ./sources)`). A module
built in the project carries the same `local` tag and folder wherever it appears in another module's tree.
Each node below shows the version every parent requested, the **negotiated** version inline when it differs
(`[1,2] -> 2`), the scope, the dependency's licence (`{Apache-2.0}`), and the module name. A per-module
*Resolved dependencies* list and a licence summary follow the tree. It is the fastest way to answer "why is
this version on my class path?" before you pin anything.

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

On the module side it is the same rule one axis up: a module reached through another module's `requires`
must carry a pin. A module the project declares itself - a sibling of a multi-project build among them - is
a declaration of the project and passes.

Because `pin` writes the whole resolved closure, a pinned project satisfies `managed` as it stands; the
strategy is what keeps it that way. It is worth pairing with strict pinning in CI, where the two answer
different questions: strict pinning asks whether every artifact has a checksum, `managed` asks whether every
version was a decision somebody wrote down.

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
Occasionally one does not: Tomcat Embed copies the API's classes into its own jar, so
`org.apache.tomcat.embed.core` exports the `jakarta.servlet` packages itself and depends on no API artifact.

That leaves two modules exporting one package. It breaks more than your own code: a modular library names the
API the only way a module can, in its descriptor - the Jakarta Server Pages API states
`requires transitive jakarta.servlet` - so a module of that name must be on the path, and adding the API
artifact beside Tomcat carries the packages twice:

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

Jenesis places a module of that name holding no packages of its own, requiring each carrier transitively, so
reading it reads the carrier's copy under the API's name. One line names one module and any number of
carriers; a carrier no resolved dependency declares is an error rather than a silent no-op.

The declaration also drops every resolved artifact that declares the overridden module, however it arrived, so
the closure and the generated POM carry those packages once. Your published descriptor still says
`requires jakarta.servlet` - it names the API, not the server implementing it here - and consumers building
with Jenesis inherit the declaration through the jar's `Jenesis-Overrides` manifest attribute.

Two limits follow from the placed module holding no code. A qualified `exports … to jakarta.servlet` or
`opens … to jakarta.servlet` grants access to that module rather than to the carrier that does the
reflecting, so open to the carrier or leave the directive unqualified; and requiring it reads everything the
carrier exports, so code can compile against `org.apache.catalina` while declaring only
`requires jakarta.servlet`.

Overrides are a `modular_to_maven` feature, as aliases are: dropping the replaced artifact means reaching it
by its Maven coordinate. The strict `modular` layout rejects the tag.

<div class="note">
  Two artifacts that declare the same module name are refused wherever they meet, override or not. A module
  path resolves whichever comes first, so the build names both coordinates and stops rather than compiling
  against one and running against the other.
</div>

<div class="demo">
  Three runnable projects cover this chapter:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-16-maven-exclusions">demo-16</a> excludes
  Commons Lang from Commons Text and proves with a test that it is gone - in a POM, with the tag form beside
  it; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-18-module-alias">demo-18</a> gives args4j -
  a library with no module identity at all - a name of its own and opens a package to it; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-20-module-override">demo-20</a> puts the
  Jakarta Server Pages API, a modular library, on a module path with Tomcat Embed, which carries the servlet
  packages itself. Each is a runnable project - see <a href="/tool/demos/">Demos</a>.
</div>

## Keeping a dependency private
Every section so far assumed the module path can hold what the build resolves. It cannot always. A module
path admits one module per name, so a library that needs a different version of some dependency than its
consumer has nowhere to put it. The usual answer elsewhere is shading: rewrite the dependency's bytecode
under new package names and copy it in. That takes reflection, `Class.forName`, resource lookup,
`META-INF/services`, jar signatures and stack traces with it, and it leaves the seam implicit.

The Java Module System already has the mechanism for this. A second copy of a library goes in a
`ModuleLayer` of its own, with its own class loader, and keeps every package name it had. Jenesis lets the
module that needs the isolation declare it:

```java
/**
 * @jenesis.layer render api      my.library.spi
 * @jenesis.layer render provider maven/com.example/renderer-impl
 */
module my.library {
    requires build.jenesis.launcher;
    requires my.library.spi;
}
```

Two lines, and each says which side it declares. `api` names the one module the library shares with the
layer; `provider` names a root the layer holds, and its whole closure comes with it. Repeat the `provider`
line for more roots. A root is an ordinary coordinate, so `module/<name>` and
`maven/<groupId>/<artifactId>` both work, and the layer resolves in a dependency group of its own,
`layer:render`, which pins, verifies and reports like every other group:

```java
 * @jenesis.pin layer:render/maven/com.fasterxml.jackson.core/jackson-core 2.15.4 SHA-256/8dc921…
```

The library reaches its layer by name, and gets back the implementation:

```java
Report report = Launcher.instance("render", Report.class);
```

**Consumers declare nothing.** They require the library and know nothing of what it hides; a consumer may
even resolve a different version of the same dependency for itself. The declaration travels to them in the
`Jenesis-Layer` manifest attribute of the produced jar, exactly as an alias or an override does, and any
build that resolves that jar reconstructs the layer from it. Discovery runs to a fixpoint, so a module
inside a layer may isolate a dependency of its own, without limit.

### What crosses, and what cannot

A layer's configuration is built from its host's, so any module the layer does not itself hold resolves from
the host. That is what makes the API module the *same* class on both sides, and what lets an instance cross
the boundary as an ordinary interface call rather than a proxy. Everything the API module reaches is shared
for the same reason, derived rather than declared.

The consequence is worth stating plainly, because it is equally true of shading: **a dependency whose types
your API module reaches is exposed by it and cannot be isolated behind it.** Here the build says so, instead
of leaving it to a `LinkageError` far from its cause. Keep the API module thin.

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

<div class="demo">
  Two runnable projects cover this section:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-21-module-layers">demo-21</a> runs three
  versions of Jackson in one JVM - nested, and exercised by tests - with the consumer declaring nothing; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-22-module-layer-legacy">demo-22</a> hides
  Commons BeanUtils and the jars it drags, naming only the one its code calls. Each is a runnable project -
  see <a href="/tool/demos/">Demos</a>.
  To also see a dependency resolved from somewhere else, <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-59-module-convention">demo-59</a> resolves modules from your own Maven repository, and <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-17-bom">demo-17</a> curates versions with a bill of materials.
</div>
