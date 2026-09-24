---
order: 7
title: Pinning & bills of materials
description: Freezing the resolved closure at exact versions and SHA-256 checksums recorded in your own sources, enforcing those pins, and sharing a curated set of them through a bill of materials.
---

*[Dependencies](/tool/dependencies/#declaring-a-dependency)* pinned a single module at a version you chose.
Jenesis aims further: a pin for **every** dependency in the transitive closure, each with the **SHA-256
checksum** of its jar, written for you rather than by hand and committed with your sources. A later build that
resolves a jar whose bytes do not match the recorded checksum **fails**, so the build is resistant to a
supply-chain swap at a coordinate you already trusted. The second half of the chapter is how to share one
such record across modules and projects instead of repeating it.

## Recording the pins

You rarely write pins by hand. The `pin` selector resolves the closure, hashes each jar, and rewrites your
sources:

```bash
java build/jenesis/Make.java pin
```

It is opt-in - not part of `build` - and it writes into your project tree rather than under `target/`: a
`@jenesis.pin` tag per dependency in a **modular** project, a `<dependencyManagement>` block with a
`<!--Checksum/…-->` comment per entry in a **`pom.xml`** project. Commit the result and the pin set travels
with the project.

`pin` is project-wide, and a `+<module>` selector beside it narrows `build` rather than the pin. To pin one
module, name its step - `<path>` is the module's folder with `+` in place of `/`, as the step's folder under
`target/` is named:

```bash
java build/jenesis/Make.java pin/module-api+client
```

A pin in `module-info.java` reads:

```java
/**
 * @jenesis.pin org.apache.commons.text 1.12.0 SHA-256/8f2b...c41
 */
module demo.app {
    requires org.apache.commons.text;
}
```

A project on the [JEP 467](https://openjdk.org/jeps/467) Markdown form declares them in `///` comments
instead, and `pin` writes back in whichever form the comment already uses - creating a `/** … */` only where
there is no comment at all, so a project never ends up with one of each.

<div class="warning">
  <strong>Explanatory prose goes above the tag block, never below or between the tags.</strong> A javadoc tag
  owns every line beneath it until the next tag, so a paragraph written under a <code>@jenesis.pin</code>
  arrives as part of that pin's value. Jenesis rejects such a declaration and quotes the absorbed text back
  at you; the fix is always to move the description into the comment's body.
</div>

<div class="tip">
  Re-run <code>pin</code> whenever you change a dependency; it refreshes the versions and checksums from the
  new closure. To record versions without checksums, pass <code>-Djenesis.pin.checksum=false</code>. The
  digest defaults to SHA-256 and is set with <code>-Djenesis.project.digest=&lt;algorithm&gt;</code>.
</div>

In the `modular_to_maven` layout, which a `module-info.java` project uses by default, a module name pins the
module a `requires` names, and everything that module's POM brings in is pinned by its Maven coordinate. To
hold one of those at another version, change its coordinate line:

```java
/**
 * @jenesis.pin org.apache.commons.text 1.12.0
 * @jenesis.pin org.apache.commons/commons-lang3 3.17.0
 */
module demo.app {
    requires org.apache.commons.text;
}
```

commons-text's POM asks for commons-lang3 3.14.0; the coordinate line overrides it wherever the closure
reaches it, and the next `pin` records the checksum of the version you chose.

A refresh rewrites every line of the closure it resolved and removes every other line, except those of a
group this run resolved no closure for: the documentation tool's pins, in a group of their own that only
`-Djenesis.project.documentation=true` resolves, survive a run that does not build documentation.
`-Djenesis.pin.retain` chooses what survives:

| Value | Keeps a line the refresh did not write when |
| --- | --- |
| `groups` (default) | the run resolved nothing in its group |
| `all` | always - for a project built in more than one layout, since `modular` pins a transitive module by its name where `modular_to_maven` pins it by its Maven coordinate |
| `none` | never |

`-Djenesis.print.pins=true` reports every line a refresh kept:

```
[KEPT]      ./source/store/module-info.java: kept, resolved by no closure: dokka/maven/org.jsoup/jsoup 1.16.1 SHA-256/1f11...e901
```

Each module resolves its own closure, and nothing makes two modules agree on a version. `pin/divergence`
writes every coordinate the project pins at more than one version into `divergence.properties`, naming the
versions and the modules holding each, and `-Djenesis.print.divergence=true` prints the same:

```
[DIVERGED]  main/maven/org.slf4j/slf4j-api is pinned at 2.0.13 (greeter-testing), 2.0.16 (app greeter greeter-test)
```

That is not a failure - more than one version is legitimate until you decide otherwise - but it is the signal
that a shared [bill of materials](#sharing-pins-a-bill-of-materials) is overdue.

## Pinning one variant of a module

Some libraries publish several jars under one coordinate - same module name, different bytes - distinguished
by a *classifier*. Because a module name has exactly one artifact on the module path, the classifier is a
**value on the pin** rather than part of the coordinate, written with a leading colon:

```java
/**
 * @jenesis.pin mutiny.zero :jdk-flow:0.4.3 SHA-256/0556f076...
 */
module demo.classifier {
    requires mutiny.zero;
}
```

The pin stays keyed by the bare module name, so it applies wherever that module turns up in the closure -
directly or transitively - and exactly one variant is ever present, mirroring the module path's own rule.

### Choosing the variant per machine

Where a classifier commits to one variant, a **platform guard** declares several and lets the build pick. Each
pin line may end with a parenthesised guard, and the line whose guard matches the machine wins:

```java
/**
 * @jenesis.pin org.openjfx.javafx.base :linux:21.0.3 SHA-256/...
 * @jenesis.pin org.openjfx.javafx.base :win:21.0.3 SHA-256/... (windows)
 * @jenesis.pin org.openjfx.javafx.base :mac-aarch64:21.0.3 SHA-256/... (macos,aarch64)
 */
```

The active platform is a set of **tokens**: the detected operating system and chipset, one of
`windows`/`linux`/`macos` plus one of `x86_64`/`aarch64`. A guard matches when *all* its tokens are active, the
most specific match wins, and an unguarded line is the fallback. Every variant stays committed with its own
checksum. Selection only decides which checksum-validated line applies, so the build stays reproducible on
every machine.

`-Djenesis.platform.<token>=true` adds a token and `=false` removes a detected one. That is how
`-Djenesis.platform.linux=false -Djenesis.platform.windows=true` cross-resolves a Windows closure from a Linux
host, and how a free-form token (`fips`, `musl`) names a build flavour of your own. The same `[<guard>]` suffix
works on a `pom.xml`'s `<!--jenesis.pin ... -->` block, where it selects a coordinate's version per platform.

<div class="warning">
  Two corner cases to know. Classifier pins resolve through the <strong>module index</strong> only, so
  they need the <code>modular</code> layout: a classified artifact shares its coordinate's POM, so
  <code>modular_to_maven</code> has no per-classifier POM to translate through. And two equally specific
  guards fail the build, while an unmatched guard with no fallback simply leaves the module unpinned.
</div>

{% demos 24, 25 %}

## Enforcing the pins

How strictly the recorded pins are enforced is controlled by one property,
`-Djenesis.dependency.pin`:

| `-Djenesis.dependency.pin` | Versions | Checksums |
| --- | --- | --- |
| *(unset - the default)* | honoured where pinned | verified where a pin carries one; a dependency with no checksum is allowed |
| `strict` | honoured | **required** - any third-party dependency without a pinned checksum fails the build |
| `versions` | honoured | not verified |
| `ignore` | float freely | not verified |

The default already validates every checksum you have recorded; a mismatch always fails the build. **Strict**
mode goes further and refuses to build at all until *nothing* is left unpinned, which is what you want in CI
once a project is fully pinned. Run `pin`, commit, then build under `-Djenesis.dependency.pin=strict` so no
new un-vetted artifact can slip in unnoticed.

Strict mode pairs well with the `managed` resolution strategy from
*[Dependencies](/tool/dependencies/#letting-nothing-in-that-you-did-not-name)*. Because `pin` writes the whole
resolved closure, a pinned project satisfies `managed` as it stands, and the strategy keeps it that way. The two
answer different questions: strict pinning asks whether every artifact has a checksum, `managed` asks whether
every version was a decision somebody wrote down.

<div class="note">
  First-party artifacts built within the project are exempt from the strict checksum requirement - only
  third-party jars pulled from a repository must be pinned. So a multi-module project's own modules never need
  a checksum to satisfy strict mode.
</div>

{% demos 26 %}

## Refreshing the pins

Pins freeze the closure, so a pinned project never picks up a newer version on its own. To deliberately refresh
them, run `pin` with the enforcement turned off:

```bash
java -Djenesis.dependency.pin=ignore build/jenesis/Make.java pin
```

`ignore` sets the recorded checksums aside and keeps a pinned version only for a dependency the project
declares directly; every other version is resolved afresh. `pin` then rewrites each `pom.xml` (or
`module-info.java`) with the resulting versions and freshly computed checksums.

Resolving afresh does not by itself mean newer: versions are chosen by the
*[resolution strategy](/tool/dependencies/#choosing-a-different-strategy)*, as in any build. To move the
closure forward, pick the strategy for the refresh. `stable` takes the newest version of each Maven
coordinate that is not a pre-release, declared ones included:

```bash
java -Djenesis.dependency.pin=ignore -Djenesis.resolver.maven=stable build/jenesis/Make.java pin
```

<div class="warning">
  This step <em>establishes</em> trust rather than enforcing it. Because it bypasses checksum verification
  while it resolves, it re-blesses whatever the repository currently serves; a swapped artifact would be
  written in as an accepted pin just the same. Run it only on a <strong>trusted machine</strong> against a
  <strong>trusted repository</strong>, review the resulting diff, and commit it. Every subsequent build then
  enforces the new pins against the artifacts you just vetted.
  <em><a href="/tool/securing-the-supply-chain/#provenance-who-produced-the-bytes">Recording who signed a dependency</a></em> closes
  exactly this gap: it checks who signed an artifact before a checksum for it is written.
</div>

## Sharing pins: a bill of materials
Pins written per module are exact but repetitive: the same versions recur across modules, and across projects
that want to stay in step. A **bill of materials** is that same pin set in one file, imported instead of
repeated. A module then declares only *what* it requires while the BOM decides *which version* and *which
bytes*.

A local BOM is a `pin-<name>.properties` file in the project's BOM location - by default the same
`build.jenesis/` [configuration folder](/tool/configuration/) everything else uses. Its keys name a module or a
Maven `<groupId>/<artifactId>`, as a pin does, and its values are a version and an optional checksum:

```properties
# build.jenesis/pin-lang3.properties
org.apache.commons.lang3 = 3.20.0
org.apache.commons/commons-lang3 = 3.20.0 SHA-256/69e5c9fa...263f4
```

A module imports it with a `@jenesis.bom` tag, which mirrors `@jenesis.pin`:

```java
/**
 * @jenesis.bom pin-lang3.properties
 * @jenesis.bom org.slf4j/slf4j-bom 2.0.16
 */
module demo.bom {
    requires org.apache.commons.lang3;
    requires org.slf4j;
}
```

The second line shows the other source a BOM can come from: **a published Maven BOM**, whose
`<dependencyManagement>` is imported the way Maven imports it, parent chains and nested imports included. A
third form names a module, which resolves a BOM published under that module name through the module index
or from your local module repository, versioned and checksummed, or floating to the latest published file.

{% demos 18 %}

### Which source seals how much

The three forms differ in how far they can be sealed, and that difference is the whole reason to know which
one you are importing:

| Source | Written as | Checksums |
| --- | --- | --- |
| A local file | `pin-<name>.properties` | Whatever the file records - byte-stable, so entries can carry hashes and need no pins at all. |
| A published module BOM | `<module> [<version> [<algorithm>/<hash>]]` | The reference itself is content-verified; strict pinning requires the hash. |
| A Maven BOM | `<groupId>/<artifactId> <version>` | The reference carries none: repositories re-serialise POMs, so a hash over one is not stable. `pin` records the resolved artifacts instead. |

All three satisfy `-Djenesis.dependency.pin=strict`, a Maven BOM by way of the artifact pins `pin` writes for
what resolves through it. Precedence is local-first: an explicit `@jenesis.pin` always overrides a BOM entry,
and when two BOMs manage the same coordinate the **last declared wins**, so broad curation is declared first
and local refinement last.

### What `pin` does with a BOM

By default it writes no `@jenesis.pin` line for a coordinate a BOM already supplies, removes one that has
become redundant, and pins the BOM reference itself by content. `-Djenesis.pin.bom=flatten` inverts the
migration: the BOM declarations go and the closure is pinned in full.

### Refreshing a bill of materials

A project that keeps its pins in a local BOM had nowhere for `pin` to write: the goal rewrites module
declarations, so the shared file was maintained by hand. `-Djenesis.pin.file` names a properties file to
write **instead**:

```bash
java -Djenesis.pin.file=build.jenesis/pin-project.properties build/jenesis/Make.java pin
```

The run then adds a single step over the union of every module's closure rather than one per module, so one
writer produces one file, and it emits the keys `@jenesis.bom` reads: a module under its own name, a Maven
artifact as `<groupId>/<artifactId>`, and anything carrying a type or a classifier under its repository. The
module declarations are left alone.

Only the `main` group is written. A BOM is read under the group its declaration names, so a coordinate
belonging to a tool's own group - the linter or alternative compiler a build module resolves for itself -
would be read back as a repository name, and is left out rather than written wrong. First-party modules of
the project are left out too, for the same reason a pin never records them: they are built, not resolved.
