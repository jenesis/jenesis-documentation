---
order: 14
title: Publishing
description: Publishing locally with export, staging a correct release bundle with the metadata a repository demands, publishing a bill of materials, and driving a release tool from the build.
---

A build ends at artifacts under `target/`. **Publishing** is what makes them available to somebody else: the
artifacts laid out as a repository, carrying the metadata a repository demands, and finally uploaded and
signed. Publishing to Maven Central is really two jobs - **produce a correct, complete bundle** and **upload
it** - and Jenesis owns the first while deliberately leaving the signed upload to a dedicated release tool.

## Publishing locally with `export`

Another project on the same machine can require a module only once it has been exported. A build writes its
artifacts under its own `target/`, and `stage` lays them out as repositories there too, but no other project
reads that folder. `export` is the step that installs them where other builds look:

```bash
java build/jenesis/Make.java export
```

It builds the project, lays out the release tree that the next section describes, and copies that tree into
the repositories your layout publishes to: the local Maven repository (`~/.m2/repository`) for `maven`, the
local module repository (`~/.jenesis`) for `modular`, and both for `modular_to_maven`. A project on the same
machine then requires the module by its name, as it would any other. That is the whole loop for a library
you are developing alongside its consumer, with no remote involved.

The export to the local Maven repository carries the generated POM, so it is not only for Jenesis. Maven reads
`~/.m2/repository` by default and Gradle reads it once a build declares `repositories { mavenLocal() }`, so
both take the module as an ordinary dependency, under the coordinate derived from its name.

A project that sets no version exports an unversioned module, whose POM carries `0-SNAPSHOT`. That suits two
projects changing together, but it names no build in particular: a `requires` without a pin takes whichever
build of the module was exported last. To depend on one build, export it with `jenesis.project.version` and
pin that version in the consumer; `pin` then records its checksum, and a build under
`jenesis.dependency.pin=strict` accepts it.

A consumer resolves its dependencies again when what it declares changes, not when another project exports a
new build of one of them. After exporting again under the same version, or without one, build the consumer
with `-Djenesis.executor.rebuild=true` to take the new export.

`jenesis.module.local` and `jenesis.maven.local` point the two local repositories elsewhere, for a build and
for the consumers that should see its export, for example a temporary folder that keeps your own
repositories untouched. The local Maven repository they name must already exist.

{% demos 59 %}

## Staging the release tree

The `stage` target materialises the full release tree in Maven repository layout under
`target/stage/maven/output/`: the main jar, the POM, and - when you ask for them - the `-sources.jar` and
`-javadoc.jar` that Central demands. You enable those and set the version from the command line:

```bash
java -Djenesis.project.version=1.0.0 \
     -Djenesis.project.sources=true \
     -Djenesis.project.documentation=true \
     build/jenesis/Make.java stage
```

Central also requires the POM to carry `name`, `description`, `url`, `<licenses>`, `<developers>`, and
`<scm>`. Jenesis folds two channels into each POM. Everything it can derive from the source comes first: the
coordinate and description from the module name and its Javadoc, or from the source `pom.xml`. A
`project.properties` file, pointed at with `-Djenesis.project.metadata=project.properties`, carries only what
a module declaration cannot express:

```properties
# project.properties
url=https://github.com/jenesis/jenesis
license.apache-2_0.name=Apache-2.0
license.apache-2_0.url=https://www.apache.org/licenses/LICENSE-2.0.txt
developer.raphw.name=Rafael Winterhalter
developer.raphw.email=rafael.wth@gmail.com
scm.connection=scm:git:https://github.com/jenesis/jenesis.git
scm.url=https://github.com/jenesis/jenesis
```

<div class="tip">
  A staged bundle is <strong>reproducible</strong>: jar entries carry a fixed timestamp, the manifest
  records <code>Created-By: Jenesis</code> rather than the JDK that ran the build, and Javadoc is generated
  with <code>-notimestamp</code>, so two independent builds of the same sources hash bit-for-bit identically -
  a consumer can verify the bytes on Central were built from the published sources. Declare your own
  <code>Created-By</code> and it is kept.
</div>

<div class="note">
  A POM generated from a module declaration lists the <em>resolved closure</em>: every artifact the module was
  built and tested against, at the version it resolved to, each a direct dependency of its own. Because the
  list is already complete, every entry also excludes everything beneath it - so a consumer inherits exactly
  what this build verified rather than re-deriving those subtrees from today's POMs. Nothing is hidden by
  that: each artifact is a first-class dependency, so dependency management and version overrides still reach
  it.
</div>

### Pointing a release at its sources

The repository URL says where a project lives, not which revision a release was built from. Three properties
say that: `jenesis.project.revision` names the revision, for Git the commit id; `jenesis.project.tag` names the
tag the release carries, if it has one; and `jenesis.project.tree` names the Git tree of that revision, which
identifies the content of the whole repository independently of its history. Pass them on the command that
stages the release:

```bash
java -Djenesis.project.version=1.0.0 \
     -Djenesis.project.tag=v1.0.0 \
     -Djenesis.project.revision=$(git rev-parse HEAD) \
     -Djenesis.project.tree=$(git rev-parse HEAD^{tree}) \
     build/jenesis/Make.java stage
```

A GitHub Actions workflow has the first two at hand: `${{ github.sha }}` is the commit the run builds, and
`${{ github.ref_name }}` is the tag when a pushed tag started the run. The tree comes from the checkout.

```yaml
- run: >
    java -Djenesis.project.tag=${{ github.ref_name }}
    -Djenesis.project.revision=${{ github.sha }}
    -Djenesis.project.tree=$(git rev-parse HEAD^{tree})
    build/jenesis/Make.java stage
```

Neither value is derived: projects name their tags differently, so the tag is not guessed from the version.
A value that does not change from release to release can also be declared in `project.properties`, as
`scm.tag`, `scm.revision` or `scm.tree`, and a source `pom.xml` contributes the `<tag>` of its `<scm>`. A property takes
precedence over a declared value, and an empty property, such as `-Djenesis.project.tag=`, records nothing even
when a value is declared.

The tag becomes the `<tag>` of the POM's `<scm>`; the POM has no element for a revision or a tree. The SBOM
records the tag and the revision as the `jenesis:scm:tag` and `jenesis:scm:revision` properties of the project's
component, and the tree as `jenesis:scm:swhid`, the [SWHID](https://docs.softwareheritage.org/devel/swh-model/persistent-identifiers.html) `swh:1:dir:<tree>`; a tree
that is not a 40-character Git tree id fails the build. When
`scm.connection` names a URL, such as `scm:git:https://github.com/jenesis/jenesis.git`, the SBOM also carries a
`vcs` reference that locates the sources at the revision, or at the tag when no revision is given, in the
notation SPDX uses for a download location: `git+https://github.com/jenesis/jenesis.git@<revision>`. A tag of
`HEAD`, which a `pom.xml` declares for the root of its repository, counts as no tag there.

{% demos 60 %}

## Publishing a bill of materials

A module can also publish the pin set of its own resolved closure, so a downstream project imports the versions
this one was built and tested against instead of curating its own. It is the emitting counterpart of the
[bills of materials](/tool/pinning/) you already know how to consume.

A `bom.properties` file in the configuration folder switches it on - the file may be empty, presence is the
switch. The modular layouts then render the module's closure as a properties file that `export` publishes
into the local module repository beside the module jar:

```
~/.jenesis/demo.bom/1.0.0/demo.bom.properties
```

Another project consumes it with `@jenesis.bom demo.bom`, exactly the way it consumes a hand-written file. The
BOM travels through the module layout only; the Maven export never carries it.

{% demos 17 %}

## Signing the jar itself

There are two signatures around a published jar, and they answer different questions. The detached one the
next section covers travels *beside* the artifact and says who published it. The other lives **inside** the
archive: `jarsigner`, the JDK's own signer, writes a manifest of digests and a signature block into the jar,
which a JVM can check as it loads the classes.

Naming a key store turns it on:

```
jenesis.jarsigner.keystore     the key store to sign with
jenesis.jarsigner.alias        the key within that store
jenesis.jarsigner.storepass    where the store's password is read from
jenesis.jarsigner.keypass      the same, where the key has a password of its own
jenesis.jarsigner.storetype    the JDK's own default otherwise, normally PKCS12
jenesis.jarsigner.tsa          a timestamp authority, so a signature outlives the certificate
jenesis.jarsigner.arguments    anything else jarsigner accepts
```

These are properties rather than a configuration file because where the key is and what unlocks it differ
between a laptop, a release machine and a CI runner, and a developer without the key still has to be able to
build. They belong to the machine that signs: a project's `jenesis.properties` or profile that sets any of
them is refused, since a file travelling with the sources would decide which key a build reaches for and
which file a password is read from. A machine holds them once, for everything built on it:

```properties
# ~/.jenesis/jenesis.properties
jenesis.jarsigner.keystore=/home/me/.keys/signing.p12
jenesis.jarsigner.alias=me
jenesis.jarsigner.storepass=file /home/me/.keys/signing.pass
```

and a release runner names them for one run, where a `-D` wins over that file:

```bash
java -Djenesis.jarsigner.keystore=/etc/jenesis/release.p12 \
     -Djenesis.jarsigner.alias=release \
     -Djenesis.jarsigner.storepass=env JENESIS_KEYSTORE_PASSWORD \
     build/jenesis/Make.java
```

**Naming any of those keys says the project signs its jar.** Saying that and then leaving the key store, the
alias or the password location unnamed stops the build rather than producing an unsigned jar - a release that
shipped unsigned because a runner forgot a flag is the one outcome worth refusing. A project that names none
of them does not sign.

A password is never a value, not even a property value. `storepass` and `keypass` take a location in
jarsigner's own grammar - `env <variable>` or `file <path>` - and anything else fails the build naming the two
forms; a password passed as `-D` would otherwise stand in the process list of the machine that runs the build.
The key store itself is referenced by path and never copied into `target/`, so no private key reaches the
build tree or a shared build cache.

Signing is part of producing the artifact rather than a step after it: the signer reads the jar the archiver
wrote and writes the signed jar in its place, so the unsigned jar never leaves the toolchain. The module's
inventory, both staged repositories, an `export` and a publication all see only the signed jar - and a
detached signature made afterwards covers the signed bytes.

<div class="note">
  The step re-runs when the jar changes or when any of those settings change. It does not hash the key
  store's contents, so replacing the key behind an unchanged path does not by itself invalidate the step:
  delete <code>target/</code> after a key rotation.
</div>

{% demos 58 %}

## The last mile: signing and uploading

The remote upload and GPG signing are not Jenesis's job. Point **[JReleaser](https://jreleaser.org/)** at
`target/stage/maven/output/` and it signs every artifact and uploads the bundle to Central. Jenesis stops at
the unsigned, validated bundle, so credentials and signing keys never enter the build.

This split is deliberate. Most people building a project never release it: releasing is a rare, tightly
controlled job for CI or a hardened environment that holds the keys. And the way you release evolves
independently of how the build produces artifacts.

### Driving the release tool from the build

You can still reach that tool through the same selector vocabulary as everything else. `release` is a target on
every layout, and it depends on `stage`, so what a release tool uploads is always the tree this build just
produced:

```bash
java build/jenesis/Make.java release
```

The target exists whether or not anything is configured; the *tool* is what a file activates. A `jreleaser.yml`
(or `.yaml`, `.toml`, `.json`) **at the project root** adds a `release/jreleaser` step - a project-root lookup
rather than the usual per-module configuration folder, because JReleaser resolves every path in its
configuration against one base directory. `-Djenesis.jreleaser.config=<path>` names a different file.

It contributes two steps. The first writes a `jreleaser.properties` holding `JRELEASER_PROJECT_VERSION`, the
version this build stamped, so the version is stated once rather than passed to two tools that can then
disagree. Point a configuration at it with
`environment: { variables: target/release/jreleaser/environment/output/jreleaser.properties }`. The second runs
the `jreleaser` executable found in the environment, forwarding the process environment unchanged. Every
`JRELEASER_*` credential is therefore read by JReleaser itself and never touched, logged, or stored by the
build.

<div class="warning">
  <code>release</code> is a <strong>dry run by default</strong>: every local phase runs and every remote one is
  skipped. A real release needs <code>-Djenesis.jreleaser.dryRun=false</code>, the single switch that separates
  a rehearsal from a publication - so no combination of selectors alone can publish.
</div>

<div class="note">
  JReleaser is expected from the environment rather than resolved as a dependency, the way
  <code>native-image</code> is. Every tool that <em>shapes</em> an artifact - a compiler, a linter - is pinned,
  because reproducing a build means reproducing it exactly. A release tool shapes nothing: it transmits a
  finished, already-reproducible tree. What it needs instead is credentials, network access, and a git identity,
  which belong to the release environment.
</div>

<div class="tip">
  Prefer a dedicated release integration wherever your CI offers one - JReleaser ships a GitHub Action, and
  other platforms offer equivalents. They pin the tool version, wire the platform's secret store, and publish
  the release logs. The <code>release</code> target is for what they do not cover: rehearsing a release
  locally, and releasing from a pipeline that has no such integration.
</div>
