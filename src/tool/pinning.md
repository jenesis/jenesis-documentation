---
order: 7
title: Pinning & bills of materials
description: Freezing the resolved closure at exact versions and SHA-256 checksums recorded in your own sources, enforcing those pins, and sharing a curated set of them through a bill of materials.
---

*[Dependencies](/tool/dependencies/)* ended with a resolved closure - the exact set of jars a build compiles
and runs against. But that set can still drift: a `RELEASE` selector or an unpinned range resolves to whatever
is newest today. This chapter is about freezing it.

**Pinning** records every dependency in the transitive closure with both an exact version *and* the SHA-256
checksum of the jar, in your own committed sources. A later build that resolves a jar whose bytes do not match
the recorded checksum **fails**, so the build is resistant to a supply-chain swap at a coordinate you already
trusted. The second half of the chapter is how to share one such record across modules and projects instead
of repeating it.

## Recording the pins

You do not write pins by hand. The `pin` selector resolves the closure, hashes each jar, and rewrites your
sources with the result:

```bash
java build/jenesis/Project.java pin
```

`pin` is opt-in (it is not part of the default `build`) and it writes back into your project tree rather than
under `target/`. In a **modular** project it adds a `@jenesis.pin` tag per dependency on the module
declaration; in a **`pom.xml`** project it fills a `<dependencyManagement>` block, tagging each entry with a
`<!--Checksum/…-->` comment. Commit the result and the pin set travels with the project.

A pin in `module-info.java` reads:

```java
/**
 * @jenesis.pin com.fasterxml.jackson.databind 2.18.2 SHA-256/8f2b...c41
 */
module demo.app {
    requires com.fasterxml.jackson.databind;
}
```

The grammar is `@jenesis.pin <group>/<repository>/<coordinate> <version> [<algorithm>/<hash>]`, with two
shorthands for a project's own dependencies (the `main` group):

| You write | Means |
| --- | --- |
| `com.fasterxml.jackson.databind` | a module name - `main/module/…` |
| `org.slf4j/slf4j-api` | a Maven `groupId/artifactId` - `main/maven/…` |
| `main/maven/org.foo/bar/jar/native` | a coordinate with a type or classifier, written in full |

A module project can therefore pin a plain Maven transitive it pulls in (say a non-modular library behind a
named module) with the `groupId/artifactId` form, even though its own dependencies resolve through the module
index. Two optional additions to that grammar, a classifier and a platform guard, are the subject of the next
section. Everything else `pin` writes and refreshes for you.

<div class="tip">
  Re-run <code>pin</code> whenever you change a dependency; it refreshes the versions and checksums from the
  new closure and drops entries that no longer resolve. To record versions without checksums, pass
  <code>-Djenesis.pin.checksum=false</code>. The digest defaults to SHA-256 and is set with
  <code>-Djenesis.project.digest=&lt;algorithm&gt;</code>.
</div>

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
pin line may end with a bracketed guard, and the line whose guard matches the machine wins:

```java
/**
 * @jenesis.pin org.openjfx.javafx.base :linux:21.0.3 SHA-256/...
 * @jenesis.pin org.openjfx.javafx.base :win:21.0.3 SHA-256/... [windows]
 * @jenesis.pin org.openjfx.javafx.base :mac-aarch64:21.0.3 SHA-256/... [macos,aarch64]
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

<div class="note">
  First-party artifacts built within the project are exempt from the strict checksum requirement - only
  third-party jars pulled from a repository must be pinned. So a multi-module project's own modules never need
  a checksum to satisfy strict mode.
</div>

## Refreshing the pins

Pins freeze the closure, so a pinned project never picks up a newer version on its own. To deliberately refresh
them, run `pin` with the enforcement turned off:

```bash
java -Djenesis.dependency.pin=ignore build/jenesis/Project.java pin
```

`ignore` drops every existing pin: versions float to the latest the repository offers and the recorded
checksums are not consulted. `pin` then re-resolves that fresh closure and rewrites each `pom.xml` (or
`module-info.java`) with the new versions and freshly computed checksums.

<div class="warning">
  This step <em>establishes</em> trust rather than enforcing it. Because it bypasses checksum verification
  while it resolves, it re-blesses whatever the repository currently serves; a swapped artifact would be
  written in as an accepted pin just the same. Run it only on a <strong>trusted machine</strong> against a
  <strong>trusted repository</strong>, review the resulting diff, and commit it. Every subsequent build then
  enforces the new pins against the artifacts you just vetted.
</div>

## Sharing pins: a bill of materials

Pins written per module are exact but repetitive: the same versions recur across modules, and across projects
that want to stay in step. A **bill of materials** is that same pin set in one file, imported instead of
repeated. A module then declares only *what* it requires while the BOM decides *which version* and *which
bytes*.

A local BOM is a `pin-<name>.properties` file in the project's BOM location - by default the same
`build.jenesis/` [configuration folder](/tool/configuration/) everything else uses. Its keys follow the pin
grammar without the group, and its values are a version and an optional checksum:

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

<div class="tip">
  Every demo ships already pinned, so any of them shows the result. Four are about pinning itself:
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-30-module-classifier">demo-30</a> pins a
  classified variant of a module and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-32-platform-guard">demo-32</a> switches
  between two variants with a guard;
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-28-bom">demo-28</a> imports a Maven BOM and a
  local pin file side by side and builds under strict pinning with almost no pin lines of its own, and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-42-supply-chain-security">demo-42</a> proves
  both guarantees by getting them wrong on purpose - an unpinned dependency and a wrong checksum, each
  rejected. See <a href="/tool/demos/">Demos</a>.
</div>
