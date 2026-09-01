---
order: 13
title: Publishing
description: Staging a correct release bundle, the metadata a repository demands, publishing it locally with export, publishing a bill of materials, and driving a release tool from the build.
---

A build ends at artifacts under `target/`. **Publishing** is what makes them available to somebody else: the
artifacts laid out as a repository, carrying the metadata a repository demands, and finally uploaded and
signed. Publishing to Maven Central is really two jobs - **produce a correct, complete bundle** and **upload
it** - and Jenesis owns the first while deliberately leaving the signed upload to a dedicated release tool.

## Staging the release tree

The `stage` target materialises the full release tree in Maven repository layout under
`target/stage/maven/output/`: the main jar, the POM, and - when you ask for them - the `-sources.jar` and
`-javadoc.jar` that Central demands. You enable those and set the version from the command line, or in code
on `Project` (`new Project().version("1.0.0")`):

```bash
java -Djenesis.project.version=1.0.0 \
     -Djenesis.project.sources=true \
     -Djenesis.project.documentation=true \
     build/jenesis/Project.java stage
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
  A staged bundle is <strong>reproducible</strong>: jar entries carry a fixed timestamp and Javadoc is
  generated with <code>-notimestamp</code>, so two independent builds of the same sources hash bit-for-bit
  identically - a consumer can verify the bytes on Central were built from the published sources.
</div>

<div class="note">
  A POM generated from a module declaration lists the <em>resolved closure</em>: every artifact the module was
  built and tested against, at the version it resolved to, each a direct dependency of its own. Because the
  list is already complete, every entry also excludes everything beneath it - so a consumer inherits exactly
  what this build verified rather than re-deriving those subtrees from today's POMs. Nothing is hidden by
  that: each artifact is a first-class dependency, so dependency management and version overrides still reach
  it.
</div>

## Publishing locally with `export`

`export` is a genuine publish, into a *local* repository:

```bash
java build/jenesis/Project.java export
```

It copies the staged tree into the repositories your layout publishes to: the local Maven repository
(`~/.m2`) for `maven`, the local module repository (`~/.jenesis`) for `modular`, and both for
`modular_to_maven`. Another project on the same machine then resolves the artifact immediately. That is the
whole loop for a library you are developing alongside its consumer, with no remote involved.

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
java build/jenesis/Project.java release
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

<div class="tip">
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-47-publishing">demo-44</a> stages a
  Central-ready bundle - POM metadata, sources and javadoc jars - and then resolves the coordinate straight
  back out of the staged tree to prove it is complete, entirely offline;
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-31-bom">demo-28</a> publishes a BOM of its own
  closure. Each is a runnable project - see <a href="/tool/demos/">Demos</a>.
</div>
