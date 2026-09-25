---
order: 17
title: Reference
description: A lookup for the command line - targets and selectors - a grouped table of every configuration key with its default, and the built-in steps a selector can name.
---

The earlier chapters built up Jenesis one topic at a time. This one is the flat reference you come back to:
how to invoke the build, the target and selector grammar, every `jenesis.*` configuration key with its
default, and the vocabulary of built-in steps a selector can name. Each entry links to the chapter that
explains it in full.

## Invoking the build

Every project ships its build as source under `build/jenesis/Make.java`. The canonical invocation
recompiles that engine and runs it:

```bash
java build/jenesis/Make.java [selectors…]
```

A package-manager install (see *[Getting started](/tool/getting-started/)*) adds a second form:

| Form | Invocation | Notes |
| --- | --- | --- |
| Source | `java build/jenesis/Make.java` | The canonical form; compiles the embedded engine on each run. |
| Installed | `jenesis` | The command from SDKMAN, Homebrew or Scoop. It runs the *installed* engine against the current directory, not the sources under `build/jenesis/`, so it also builds a project that embeds none. |

Settings may lead the arguments after the main class (`java build/jenesis/Make.java
-Djenesis.project.version=1.0.0 build`), and `@<file>` stands for the arguments a file holds - `#` comments
to the end of a line, quotes group, `@@<text>` is a literal `@`, and a file names no further file. See
*[Configuration](/tool/configuration/#a-whole-run-in-a-file)*.

<div class="note">
  How the JDK tool steps launch is set by <code>-Djenesis.process.factory=tool|fork</code>:
  <code>tool</code> (the default) runs <code>javac</code>/<code>jar</code> in-process; <code>fork</code> runs
  them as separate processes for stricter sandboxes. A GraalVM native image defaults to <code>fork</code>,
  since it has no in-process JDK tools.
</div>

## Targets

Positional arguments are **selectors**. With none, the build runs its **default target**, `build`, which
compiles and packages every module. `Project.defaultTarget(...)` changes the default (there is no matching
property). The top-level targets the shipped layouts register:

| Target | What it runs |
| --- | --- |
| `build` | Compile, check, test, and package every module (the default). |
| `stage` | Materialise the release tree under `target/stage/…` (see *[Publishing](/tool/publishing/)*). |
| `export` | Publish the staged tree - into the local Maven repository (`~/.m2`), the local module repository (`~/.jenesis`), or both, depending on the layout. |
| `release` | Hand the staged tree to a configured release tool; a dry run unless told otherwise (see *[Publishing](/tool/publishing/)*). |
| `plugin/<name>` | Run a plugin the project names under the hook point `plugin`, which runs only when named (see *[Extending the build](/tool/extending-the-build/#plugins-for-the-whole-project)*). |
| `pin` | Rewrite every `pom.xml` / `module-info.java` so the transitive closure is pinned at source (see *[Pinning &amp; bills of materials](/tool/pinning/)*). |
| `dependencies` | Print each module's resolved dependency graph with licences. |
| `ide` | Generate IntelliJ IDEA, VS Code, and Eclipse project metadata at the project root. |
| `help` | Print a one-screen orientation: how to start, the selectors, and how to make a step verbose. |
| `skill` | Print the briefing a coding agent works from. |
| `metadata` | Refresh the metadata module outputs without building artifacts. |
| `configuration` | Print every setting with the value in force, one per line: `jenesis.<key>=<value> [set\|default\|unset] <what it does>`. Built to grep, and the tool's own property reference. |
| `properties` | Print every `jenesis.*` setting in force for this run - from the command line, `jenesis.properties` or a profile alike - sorted by key. |

## Selectors

A selector picks part of the build graph. Three shapes exist.

**Module selectors** start with `+`: the active layout rewrites `+<name>` into that module's path, so one
module builds without dragging in its siblings. A nested module is named by joining its path segments with
`+`, as in `+api+client`. `+` alone names the module whose descriptor sits at the project root - a root
`pom.xml` that is itself a module; an aggregator-only root or a pure modular project has no such module.

```bash
java build/jenesis/Make.java +mymodule      # build just this module's subgraph
```

**Path selectors** are a slash-delimited path of `module/step` identities matched against the graph, with two
wildcards:

- `:` matches exactly one segment.
- `::` matches any depth - `::/sign` matches every `sign` step anywhere in the tree.

Wildcards are **lenient**: a branch that fails to match is silently skipped. A **literal** path that does not
resolve throws `Unknown selector: …`. Once a step is matched, its predecessors run unconditionally, so its
inputs are always real folders.

| Invocation | What runs |
| --- | --- |
| `java build/jenesis/Make.java` | The **default target**, `build`: the whole graph. On a warm cache, every step is `[SKIPPED]`. |
| `java build/jenesis/Make.java ::/test` | Every `test` step at any depth, plus its predecessors. |
| `java build/jenesis/Make.java build/::/test` | The same, anchored under the top-level `build` module. |
| `java build/jenesis/Make.java +mymodule` | Only the named module's subgraph. |
| `java build/jenesis/Make.java pin/module-api+client` | Only the `api/client` module's pins. |

A `+<module>` selector narrows **`build`** and nothing else. `pin`, `stage` and `export` are entry points of
their own, so `pin +mymodule` runs the whole project's pin *and* that module's build rather than a pin
narrowed to one module. To pin a single module, name its step: the `pin` target holds one
`module-<path>` step per module, where `<path>` is the module's source folder URL-encoded, because a
selector splits on `/`.

<div class="tip">
  Selectors are not part of the cache key - they only gate scheduling. A step run under a selector produces
  the same cached output a full build would, so a later unselected run hits the cache. See
  <em><a href="/tool/core-concepts/">Core concepts</a></em> for how change detection works.
</div>

## Configuration keys

Every knob is a system property, passed with `-D` or set in a `jenesis.properties` file - see
*[Configuration](/tool/configuration/)* for files, profiles, and precedence. Some also read an environment
variable as a fallback. Defaults apply when the key is unset.

The build prints this same catalogue for itself: `configuration` lists every key with the value in force and
where it came from, one line each, so `configuration | grep cache` answers what is available and what is set
in one step.

### Project & layout

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.project.layout` | `auto` | The layout: `auto`, `maven`, `modular`, `modular_to_maven`. |
| `jenesis.project.target` | `target` | The per-build output folder. Safe to delete for a clean build. A project's own file names only a folder inside the project. |
| `jenesis.project.version` | *(unset)* | Stamps this version onto every artifact the build produces. Unset, a module stays unversioned - no version in its descriptor and none in its path in the modular tree - and its generated POM, which cannot omit one, carries `0-SNAPSHOT`. |
| `jenesis.project.tag` | *(unset)* | The source control tag recorded in the generated POM's `<scm>` and in the SBOM; empty records none, even over a declared `scm.tag` (see *[Publishing](/tool/publishing/#pointing-a-release-at-its-sources)*). |
| `jenesis.project.revision` | *(unset)* | The source revision, for Git the commit id, recorded in the SBOM; empty records none, even over a declared `scm.revision`. |
| `jenesis.project.tree` | *(unset)* | The Git tree id of the release, as `git rev-parse HEAD^{tree}` prints it, recorded in the SBOM as a SWHID; empty records none, even over a declared `scm.tree`. |
| `jenesis.project.metadata` | *(unset)* | Path-separated list of project-level POM metadata files (conventionally one `project.properties`). |
| `jenesis.project.sources` | `false` | Also assemble a per-module sources jar. |
| `jenesis.project.documentation` | `false` | Also assemble a per-module javadoc jar. |
| `jenesis.project.resources` | *(unset)* | Comma-separated `<path>:<target>` pairs of project files or folders placed among the resources of every module, as `LICENSE:META-INF/LICENSE,NOTICE:META-INF/NOTICE` (see *[Supply-chain features](/tool/supply-chain/#the-licence-text-in-the-jar)*). |
| `jenesis.project.watch` | `false` | Keep the process alive and rebuild on every source change (see *[Building &amp; running](/tool/building-and-running/)*). |

### The entry point (`build/jenesis/Make.java`)

`Make` is the entry point every command names. It carries no build logic and names no engine class, so the
Java launcher compiles one small file rather than the whole engine before the build starts. These settings are read from the command
line and from `jenesis.properties` at the project root.

| Property | Default | Effect |
| --- | --- | --- |
| `jenesis.make.root` | `.` | The directory scanned for `module-info.java` / `pom.xml`. Command-line only. |
| `jenesis.make.profiles` | *(unset)* | Comma-separated **profile** names to activate. |
| `jenesis.make.compile` | `true` | Compile the build sources once and run the build from those classes, over a class loader of their own. One batch compile beats the launcher compiling class by class as it loads them, so this is faster even for a build that runs a single time. |
| `jenesis.make.classes` | `.jenesis/classes` | Where those classes land, relative to the project root. They go under `.jenesis/` with the rest of the build's by-products, so nothing lands in the sources. A project's own file names only a folder inside the project. |
| `jenesis.make.daemon` | `false` | Hand the build to a reused JVM, which keeps a warm JIT between calls. `--stop` as the sole selector shuts it down. |
| `jenesis.toolchain.version` | *(unset)* | The JDK the build runs on, as `25`, `25.0.3` or `25-temurin`. `Make.java` and `Execute.java` start again on a matching installed JDK when the running one does not match (see *[Building &amp; running](/tool/building-and-running/#the-jdk-a-build-runs-on)*). |
| `jenesis.toolchain.searchpath` | `@` | Comma-separated folders searched for that JDK, absolute or under `~`, with `*` for any one folder name; `@` stands for the operating system's usual locations, and empty only checks the running JDK. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.toolchain.installer` | *(unset)* | A program run with the version as its last argument when no JDK on the search path matches, such as `jenesis-jdk`; a name is looked up on the `PATH`, a path is absolute or starts with `~`. Command line or `~/.jenesis/jenesis.properties` only (see *[Building &amp; running](/tool/building-and-running/#installing-a-missing-jdk)*). |

What a daemon saves is compiling speed, not setup. A Jenesis build has no script to parse - the project is
described by `pom.xml` or `module-info.java` and configured by properties files - so nothing parsed or
compiled is held between calls. What is held is a warm JIT, and a build spends its time inside `javac`, which
a JVM that has already compiled a few modules runs faster. The daemon therefore pays in proportion to how
much a build compiles: nothing on a build that compiles little, where the socket costs more than the warm
code saves, and about a third off a five-module project. Compiling the build sources once, which is on by
default, is what removes the large fixed cost; the daemon is the increment after that.

Only `jenesis.*` properties travel with a call to a daemon, which clears and sets them again around every
build. Everything a running JVM cannot change is the daemon's identity instead - the build sources, the
environment, the JVM arguments, any other `-D` - and a call differing in one of them replaces the daemon
rather than being served by one configured for something else.

| Property | Default | Effect |
| --- | --- | --- |
| `jenesis.daemon.idle` | `10800` | Seconds of idleness after which the daemon exits. |
| `jenesis.daemon.options` | `-Xmx2g` | JVM options for the daemon process itself, whitespace separated. Command line or `~/.jenesis/jenesis.properties` only. |

| `jenesis.make.global` | `$HOME` | Base folder whose `.jenesis/` subfolder holds the user-global `jenesis.properties`; empty string disables it. Command-line only. |
| `jenesis.project.configuration` | `build.jenesis/` | Comma-separated project-wide configuration folders; `@` splices the default back in, and `@<name>` splices what `jenesis.<name>` or the environment variable `<name>` holds. |
| `jenesis.project.boms` | the configuration folders | Path-separated list of folders searched for `pin-<name>.properties` files. |
| `jenesis.project.artifacts` | `.jenesis/artifacts` | The project-local folder resolved artifacts are materialised into (hard-linked from `~/.m2` where possible), in every layout. It also holds a copy of each repository's `maven-metadata.xml`, so a `RELEASE` or range still resolves when the repository is unreachable. A project's own file names only a folder inside the project. |

{% demos 5 %}

### Building & testing

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.test.skip` | `false` | Register no test steps, so no tests run. Naming the key with no value is `true`; `=false` runs the tests. |
| `jenesis.test.filter` | *(unset)* | Comma-separated `<classRegex>[#<method>]` list; runs only matching tests. |
| `jenesis.test.tag` | *(unset)* | Comma-separated test tags / groups to include. |
| `jenesis.test.engine` | *(auto)* | Force the engine: `junit-platform`, `junit4`, or `testng`. |
| `jenesis.test.parallel` | `false` | Run tests in parallel where the framework supports it. |
| `jenesis.test.reporting` | `false` | Emit test reports under `reports/tests/`: legacy JUnit XML and Open Test Reporting XML for `junit-platform`, TestNG's own report for `testng`. |
| `jenesis.test.incremental` | *(off)* | Run only the tests a change can reach; the value names the digest algorithm. |
| `jenesis.test.force` | `false` | `true` runs the tests even when nothing changed and the recorded scope already covers the request. |
| `jenesis.archive.timestamp` | `1980-02-01T00:00:00Z` | The date and time recorded on every entry of the jars, jmods and zips the build produces; an ISO-8601 date-time with an offset between `1980-01-01T00:00:02Z` and `2099-12-31T23:59:59Z`. Empty turns the fixed time off, which is discouraged (see *[Building &amp; running](/tool/building-and-running/#reproducible-archives)*). |
| `jenesis.stage.tests` | `false` | Include test-variant artifacts when staging, and the modules tagged `@jenesis.test abstract` that they require. |
| `jenesis.sbom.cyclonedx` | `true` | Emit a CycloneDX SBOM; set `false` to skip it. |
| `jenesis.legal.notices` | `META-INF/NOTICE,META-INF/LICENSE,META-INF/license/,META-INF/licenses/,LICENSE,about.html` | Comma-separated jar entries taken as legal notices into a `.jmod`, a linked or packaged image and beside a native image, from the module's jar and from each runtime dependency's jar; names match regardless of case and also with an extension, and an entry ending in `/` takes the folder below it (see *[Packaging](/tool/packaging/#licences-in-each-form)*). |
| `jenesis.compliance` | `true` | Run the licence and vulnerability checks; `false` skips both. |
| `jenesis.source.<tool>` | `true` | Per-linter switch (`checkstyle`, `pmd`, `detekt`, `ktlint`, `scalastyle`, `scalafmt`, `codenarc`). |
| `jenesis.validator.spotbugs` | `true` | Run SpotBugs when its filter file is present. |
| `jenesis.format.java` / `.ktlint` / `.scalafmt` | `true` | Per-formatter switch. |
| `jenesis.format.rewrite` | `false` | Rewrite sources in place instead of verifying. |
| `jenesis.observe.jacoco` | `true` | Run JaCoCo coverage when its file is present. |
| `jenesis.observe.native` | `true` | Run the GraalVM tracing agent when its file is present. |
| `jenesis.mutate.pitest` | `true` | Run PIT mutation testing when its file is present. |
| `jenesis.artifact.japicmp` | `true` | Run the japicmp API comparison when its file is present. |
| `jenesis.compile.errorprone` | `true` | Run Error Prone when an `errorprone.properties` is present; `javac` forks while it does, to grant the plugin the compiler internals it reads. |
| `jenesis.generate.<tool>` | `true` | Per-generator switch (`xjc`, `protoc`, `avro`, `wsimport`, `openapi`, `antlr`). |

The quality and packaging *files* these keys gate (`checkstyle.xml`, `packaging.properties`, and the like)
are covered in *[Code quality &amp; testing](/tool/code-quality-and-testing/)*, *[Generating
sources](/tool/generating-sources/)*, *[Supply-chain features](/tool/supply-chain/)*, and
*[Packaging](/tool/packaging/)*.

### Dependencies & pinning

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.dependency.pin` | *(lenient)* | Pinning mode: `strict`, `versions`, or `ignore`. |
| `jenesis.dependency.signature` | `none` | Signature verification after each download: `none`, `declared`, or `strict`. |
| `jenesis.dependency.native` | `ignore` | What to do when a module runs a jar whose `Jenesis-Native-Access` names a module it does not grant with `@jenesis.native`: `ignore`, `warn`, or `strict`. |
| `jenesis.pin.bom` | `keep` | Whether the `pin` step keeps (`keep`) or flattens (`flatten`) BOM references. |
| `jenesis.pin.file` | *(unset)* | Write the whole project's pins to this properties file instead of rewriting the module declarations. A project's own file names only a folder inside the project. |
| `jenesis.pin.checksum` | `true` | Whether `pin` writes SHA checksums alongside versions. |
| `jenesis.pin.retain` | `groups` | Which lines a refresh keeps although it did not write them: `groups` those of a group the run resolved nothing in, `all` every one (a project built in more than one layout), `none` none. |
| `jenesis.platform.<token>` | *(detected)* | Add (`=true`) or remove (`=false`) a platform token used to select guarded pins. |
| `jenesis.plugin.<name>` | `true` | `false` leaves out the plugin `<name>` that `jenesis.plugins.properties` names (see *[Extending the build](/tool/extending-the-build/#adding-plugins-to-the-stock-build)*). |
| `jenesis.project.plugins` | `true` | `false` leaves out every plugin that `jenesis.plugins.properties` names, while `pin` still pins those of the whole project (see *[Extending the build](/tool/extending-the-build/#pinning-them)*). |
| `jenesis.project.digest` | `SHA-256` | Digest algorithm the `pin` step uses to checksum artifacts. |
| `jenesis.openpgp.command` | `gpgv` | Binary forked to verify detached OpenPGP signatures. A name is looked up on the `PATH`; a value containing a separator is used as a path. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.openpgp.expiry` | `signing` | What an expired signing key means: `ignored` accepts it whenever it signed, `signing` accepts what it signed before it expired, `current` always rejects it. |
| `jenesis.project.signatures` | *(the configuration folders)* | Path-separated locations searched for a local `signature-<name>.properties` key list. |
| `jenesis.sigstore.uri` | *(the trust root the tool carries)* | The Sigstore trust root a bundle is checked against. Jenesis carries the published root of the public instance as source; naming another replaces it, for a private instance or a root that has rotated. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.sigstore.issuers` | `github.com=token.actions.githubusercontent.com` | Comma-separated `<host>=<issuer>` pairs for identity hosts whose OpenID Connect issuer is not the host itself. Both sides are written without a scheme. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.resolver.maven` | `maven` | Maven version strategy: `maven`, `closest`, `latest`, `release`, `stable`, `fail`, or `managed`. `fail` refuses a coordinate two dependencies require at different versions; `managed` refuses that and every version the project neither declares nor names in dependency management. |
| `jenesis.resolver.module` | `first` | What happens when two module descriptors record different versions: `first`, `fail`, `ignore`, or `managed`. `managed` additionally refuses a module reached through another module's `requires` that carries no pin. |

### Repositories

| Key (env fallback) | Default | Effect |
| --- | --- | --- |
| `jenesis.maven.uri` (`MAVEN_REPOSITORY_URI`) | Maven Central | Upstream Maven repository URL(s); supports filters and references. A project's own file may name them, and `jenesis.maven.token` is then not sent. |
| `jenesis.maven.local` (`MAVEN_REPOSITORY_LOCAL`) | `~/.m2/repository` | Local Maven repository for reads and `export`. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.maven.token` (`MAVEN_REPOSITORY_TOKEN`) | *(unset)* | `Authorization` header sent to the Maven upstream. Command line or `~/.jenesis/jenesis.properties` only. It travels only to a `jenesis.maven.uri` named in the environment, on the command line or there, never to the built-in public repository. |
| `jenesis.module.uri` (`JENESIS_REPOSITORY_URI`) | `https://repo.jenesis.build/` | The Jenesis Module Index URL(s) module names resolve through; same list/filter/`@` grammar. A project's own file may name them, and `jenesis.module.token` is then not sent. |
| `jenesis.module.local` (`JENESIS_REPOSITORY_LOCAL`) | `~/.jenesis` | The local module repository, read first and written by `export`. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.module.source` | `service` | Who resolves a module name: `service` asks the index at `jenesis.module.uri`, `git` reads its published data itself and fetches from `jenesis.maven.uri`. |
| `jenesis.module.index` (`JENESIS_INDEX_URI`) | `data/modules/` in [`jenesis/jenesis-modules`](https://github.com/jenesis/jenesis-modules/tree/main/data/modules) | Where `git` reads that data from - a fork or mirror of the index's per-module files. |
| `jenesis.module.prerelease` | *(unset)* | Whether a module asked for without a version may resolve to a pre-release. Unset states no preference: the newest release is served, and a module that has only pre-releases resolves to nothing. |
| `jenesis.module.speculative` | *(unset)* | Whether a version the index has not recorded may be resolved from the module's newest coordinate. Unset states no preference, and the version is guessed. |
| `jenesis.openpgp.uri` (`OPENPGP_REPOSITORY_URI`) | `keyserver.ubuntu.com`, `keys.openpgp.org` | HKP key server roots a declared fingerprint resolves through; same list/`@` grammar, asked in order. A project's own file may name them. |
| `jenesis.openpgp.local` (`OPENPGP_REPOSITORY_LOCAL`) | `.jenesis/keys` | Where fetched keys are held, one file per fingerprint; an empty `openpgp.uri` makes this the only source. A project's own file names only a folder inside the project. |
| `jenesis.module.token` (`JENESIS_REPOSITORY_TOKEN`) | *(unset)* | `Authorization` header sent to the module index. Command line or `~/.jenesis/jenesis.properties` only. It travels only to a `jenesis.module.uri` named in the environment, on the command line or there, never to the built-in public repository, and only to the first of several. |
| `jenesis.repository.insecure` | `false` | Permit plaintext (`http://`) fetches. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.repository.retries` | `2` | Retries for a transient fetch failure (`0` disables). |
| `jenesis.repository.backoff` | `125` | Initial retry wait in milliseconds, doubling each attempt. |
| `jenesis.repository.connect.timeout` | `10000` | Connect timeout for a repository fetch, in milliseconds. |
| `jenesis.repository.read.timeout` | `30000` | Read timeout for a repository fetch, in milliseconds. |

### Caching

| Key (env fallback) | Default | Effect |
| --- | --- | --- |
| `jenesis.cache.uri` | *(none)* | Shared build cache: a `file://` or `http(s)://` URI (see *[Build performance &amp; isolation](/tool/build-performance-and-isolation/)*). Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.project.cache` | *(off)* | Project-local on-disk build cache (a path; empty enables `.jenesis/cache`). A project's own file names only a folder inside the project. |
| `jenesis.cache.project` (`JENESIS_CACHE_PROJECT`) | *(unset)* | Project header sent to an HTTP cache. |
| `jenesis.cache.key` (`JENESIS_CACHE_KEY`) | *(unset)* | Auth key sent to an HTTP cache. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.cache.connect` | `PT1S` | HTTP cache connect timeout, as an ISO-8601 duration. |
| `jenesis.cache.read` | `PT10S` | HTTP cache read timeout, as an ISO-8601 duration. |
| `jenesis.cache.insecure` | `false` | Permit the cache key over plaintext `http://`. Command line or `~/.jenesis/jenesis.properties` only. |

### Running & containers

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.execute.module` | *(prompt)* | The module to run with `Execute.java`. |
| `jenesis.execute.mainClass` | *(inferred)* | The main class to run. |
| `jenesis.project.docker` | `false` | Build inside a throwaway container. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.project.docker.image` | *(hardened)* | Image for the build container. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.project.docker.mount` | *(none)* | `<host>[:<container>],…` read-only bind mounts. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.project.docker.mountWritable` | *(none)* | Writable bind mounts. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.project.docker.env` | *(none)* | `<name>[=<value>],…` environment forwarded into the container. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.execute.docker` | `false` | Run the launched program in a container. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.execute.docker.image` / `.mount` / `.env` | *(as above)* | The run-side equivalents. Command line or `~/.jenesis/jenesis.properties` only. |

### Releasing

Read by the `release` target - see *[Publishing](/tool/publishing/)*.

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.jreleaser.config` | *(discovered)* | The release-tool configuration file; must exist when named. |
| `jenesis.jreleaser.dryRun` | `true` | Perform every local phase and skip every remote one; `false` publishes. |
| `jenesis.jreleaser.executable` | `jreleaser` | The executable to locate. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jreleaser.command` | `full-release` | The subcommand to run. |

Read by the signing step - see *[Publishing](/tool/publishing/)*. Naming any of them says the project signs
its jar, and the build then stops rather than producing an unsigned one if the key store, the alias or the
password location is missing.

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.jarsigner.keystore` | *(unset)* | The key store `jarsigner` signs the produced jar with, in place of the unsigned one. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.alias` | *(unset)* | The name of the key within that store. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.storepass` | *(unset)* | Where that store's password is read from: `env <variable>` or `file <path>`, never the password itself. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.keypass` | *(unset)* | The same, for a key that carries a password of its own. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.storetype` | *(the JDK's own)* | The store's type as `jarsigner` names it, normally `PKCS12`. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.tsa` | *(unset)* | A timestamp authority to stamp the signature with, so it outlives the certificate. Command line or `~/.jenesis/jenesis.properties` only. |
| `jenesis.jarsigner.arguments` | *(unset)* | Further `jarsigner` arguments, whitespace separated. Command line or `~/.jenesis/jenesis.properties` only. |

### Output & the execution engine

| Key | Default | Effect |
| --- | --- | --- |
| `jenesis.print.progress` | `true` | Per-step `[STARTED]`/`[SKIPPED]`/… lines; `false` runs silently. |
| `jenesis.print.docker` | `true` | Print the Docker image a step is wrapped in. |
| `jenesis.print.command` | `false` | Print each external tool's command line. |
| `jenesis.print.process` | `false` | Stream every external tool's output; `jenesis.print.<command>` targets one tool. |
| `jenesis.print.tests` | `false` | Stream the test JVM's command and output. |
| `jenesis.print.fetch` | `false` | Print a `[FETCHED]` line per downloaded artifact. |
| `jenesis.print.cache` | `false` | Print `[LOADED]`/`[STORED]` lines for the build cache, local and shared. |
| `jenesis.print.signatures` | `false` | Print a `[VERIFIED]` line per checked dependency with the key or the identity that signed it, `[EXPIRED]` with both dates where the key has since expired, and `[UNDECLARED]`/`[UNSIGNED]` for the ones no declaration covers. |
| `jenesis.print.checksum` | `false` | Append input/output checksums under each `[EXECUTED]` line. |
| `jenesis.print.pins` | `false` | Print a `[KEPT]` line per pin a refresh kept although no closure resolved it. |
| `jenesis.print.divergence` | `false` | Print a `[DIVERGED]` line per coordinate the project pins at more than one version; `divergence.properties` is written either way. |
| `jenesis.print.aliases` | `false` | Print an `[ALIAS]` line per `@jenesis.alias` whose target already declares that module name. |
| `jenesis.print.jreleaser` | `false` | Stream the release tool's output. |
| `jenesis.tree.format` | `full` | The `dependencies` tree rendering: `full` or `compact`. |
| `jenesis.tree.tests` | `true` | Include the test modules in the `dependencies` trees and their licence summary. |
| `jenesis.executor.digest` | `MD5` | Digest for the per-file content and per-step config hashes. |
| `jenesis.executor.timeout` | `PT0S` | ISO-8601 per-step timeout; `PT0S` disables it. |
| `jenesis.executor.rebuild` | `false` | Delete `target/` first, forcing a full rebuild. |
| `jenesis.executor.aggregate` | `false` | Let independent step failures aggregate into one report instead of failing at the first. |
| `jenesis.executor.concurrency` | `0` | The most build steps that run at once across the whole build; `0` means no limit. |
| `jenesis.process.factory` | `tool` | How JDK tool steps launch: `tool` (in-process) or `fork`. |
| `jenesis.process.concurrency` | `0` | The most JDK tool runs that happen at once across the whole build; `0` means no limit. |
| `JAVA_HOME` (env) | *(from `java.home`)* | Locates the JDK binaries when the runtime is not a JDK. |

## Built-in steps

A selector names a **step** by its identity. The build is a tree of these; the identities below are the ones
you address on the command line. Each produces one output folder from its inputs, and its full behaviour is
in the linked chapter.

### Per module

| Step | Produces |
| --- | --- |
| `binary` | The Java toolchain for one module; its `compiled`, `classes`, `validate`, and `artifacts` steps sit beneath it. |
| `compiled` | Compiled classes from sources and the compile class path (`javac`, or a language compiler). |
| `classes` | The version-stamped classes exposed to downstream consumers. |
| `validate` | Byte-code analysis (SpotBugs, as `validate/spotbugs`). |
| `artifacts` | The packaged jar. |
| `check` | Static-analysis findings (Checkstyle, PMD, detekt, …). |
| `format` | Formatting verification, or an in-place rewrite. |
| `dependencies` | The resolved, fetched dependency closure. |
| `test` (`executed`) | The test run and its reports. |
| `observed` | The coverage- or trace-wrapped test run. |
| `mutate` | The mutation-testing report (PIT). |
| `compliance` | The licence and vulnerability check results. |
| `sbom` | The CycloneDX bill of materials. |
| `documentation` | The javadoc (or Dokka) output and its jar. |
| `pom` | The emitted `pom.xml`. |

### Packaging

Wired by keys in `packaging.properties` - see *[Packaging](/tool/packaging/)*.

| Step | Produces |
| --- | --- |
| `legal` | The legal notices of the module's jar and its runtime dependencies, for its `.jmod` and a native image. |
| `jmod` | A `.jmod` link-time module. |
| `jlink` | A custom runtime image. |
| `jpackage` | A native installer or self-contained app image. |
| `bundle` | A self-contained `bundle.zip` of the application. |
| `launcher` | A single executable launcher jar (see *[Jenesis Launcher](/launcher/)*). |
| `docker` | A container build context - a `Dockerfile` and the jars it copies. |
| `native-image` | A GraalVM native executable. |
| `modules` | The dependency closure rewritten into explicit named modules (from `modules.properties`). |

### Top level

The `build`, `stage`, `export`, `release`, and `pin` modules are the top-level targets in the table above;
each layout wires the `maven` and/or `modular` staging and export sub-steps under them. When a project names
plugins of the whole project, `build` also holds `preprocess/custom/<name>`, which runs before any module is built,
and `postprocess/transform/<name>` and `postprocess/inspect/<name>`, which run over every module after it is built,
while `stage` holds `transform/<name>` and `inspect/<name>` - with the stock staging then in `staged/<tree>` and
each `stage/<tree>` merging it with what the transforms of stage added - `export` and `release` hold
`custom/<name>` beside their own steps, and the top-level `plugin` holds a plugin of the hook point `plugin` as
`plugin/<name>`, run only when named; `stage/project` holds what the transforms placed in the project (see *[Extending the
build](/tool/extending-the-build/#plugins-for-the-whole-project)*).

## Source declarations

Everything a module declares about its build is a Javadoc tag on `module-info.java` - or, in the `maven`
layout, the POM equivalent named beside it. Tags are read from the module's documentation
comment in either form - the traditional `/** ... */` and the Markdown `///` of
[JEP 467](https://openjdk.org/jeps/467) - and `pin` writes back in whichever form the comment
already uses. This is the whole vocabulary:

| Tag | Declares | Chapter |
| --- | --- | --- |
| `@jenesis.release <N>` | The Java release to compile against (`maven.compiler.release` in a POM); the running JDK's release when absent. | *[Building &amp; running](/tool/building-and-running/)* |
| `@jenesis.main <class>` | The module's entry point (`<mainClass>` in a POM). | *[Building &amp; running](/tool/building-and-running/)* |
| `@jenesis.test [<module>\|abstract]` | Marks this module as the test module of another, or as test infrastructure that declares no tests of its own (`abstract`). | *[Building &amp; running](/tool/building-and-running/)* |
| `@jenesis.plugin [<compiler>] <token>` | An annotation processor, or a compiler plugin for a named compiler. | *[Other JVM languages](/tool/other-jvm-languages/)* |
| `@jenesis.attach <token> [<options>]` | A library to attach as a Java agent (`<!--jenesis.attach-->` in a POM). | *[Building &amp; running](/tool/building-and-running/)* |
| `@jenesis.native <token>…` | Native access for the modules named, this one only when it names itself; a module in a layer is granted with `@jenesis.layer <name> native` instead (`<!--jenesis.native-->` in a POM). | *[Building &amp; running](/tool/building-and-running/#granting-native-access)* |
| `@jenesis.exclude <module> <group>/<artifact>…` | Transitives to prune from a requirement (`<exclusions>` in a POM). | *[Dependencies](/tool/dependencies/)* |
| `@jenesis.alias <module> <group>/<artifact>[/<type>[/<classifier>]]` | A module name for an artifact that has none. | *[Dependencies](/tool/dependencies/)* |
| `@jenesis.override <module> <module>…` | A module to replace with the modules that already carry its packages. | *[Dependencies](/tool/dependencies/)* |
| `@jenesis.layer <name> api <module>` | The one module this module shares with the layer `<name>`. | *[Dependencies](/tool/dependencies/#keeping-a-dependency-private)* |
| `@jenesis.layer <name> provider <token>` | A root the layer `<name>` isolates, with its whole closure: a module name or a `<repository>/<coordinate>`. Repeat for more roots. | *[Dependencies](/tool/dependencies/#keeping-a-dependency-private)* |
| `@jenesis.layer <name> native <token>` | Passes this module's native access on to a module of the layer `<name>`; this module then needs native access itself. | *[Building &amp; running](/tool/building-and-running/#granting-native-access)* |
| `@jenesis.pin <token> <version> [<algorithm>/<hash>] [(<guard>)]` | An exact version and checksum (`<!--jenesis.pin-->` / `<dependencyManagement>` in a POM); a trailing `(<token>,…)` guard applies the line only on a matching platform. Parentheses, not brackets: a bracketed word is a link in a Markdown documentation comment. | *[Pinning &amp; bills of materials](/tool/pinning/)* |
| `@jenesis.bom <token> [<version> [<algorithm>/<hash>]]` | A bill of materials to import. | *[Pinning &amp; bills of materials](/tool/pinning/)* |
| `@jenesis.signature <algorithm>/<fingerprint> <token>…` | The OpenPGP key that signs these coordinates' artifacts; a Maven token may end in `/*` to cover a whole groupId, and a lone `[<group>/]signature-<name>.properties` reads the keys from a local list. | *[Securing the supply chain](/tool/securing-the-supply-chain/#provenance-who-produced-the-bytes)* |
| `@jenesis.signature Sigstore/<host>/<path> <token>…` | The identity that signs these coordinates, for a repository that publishes a `.sigstore.json` beside the artifact. The path is a prefix of the identity a certificate names, and the host also names the issuer that must have authenticated it. | *[Securing the supply chain](/tool/securing-the-supply-chain/#an-identity-instead-of-a-key)* |
