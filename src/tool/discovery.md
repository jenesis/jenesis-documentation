---
order: 17
title: Discovery (proposal)
description: A proposed well-known file by which the author of a library says where its Maven artifacts and Java modules are published - why it matters, how to describe Maven artifacts, modules mapped to Maven and pure module repositories, and the grammar and algorithm for a client.
---

<div class="warning">
  The file format on this page is a <strong>proposal</strong> for any Java tool to adopt, so it may still change
  as others take it up. Jenesis reads it where <code>jenesis.repository.discovery</code> is set.
</div>

A Maven group ID or a Java module name are typically reversed domain names: `net.bytebuddy` belongs to
`bytebuddy.net`, for example.
This proposal lets whoever owns that domain say, in one small file on its website,
`https://<domain>/.well-known/java-repository.properties`, where the artifacts and modules named after it are
published. A build that reads the file downloads them from there - a GitHub release,
the author's own server, or a Maven repository of the author's choosing - before it asks any central repository.

The file is a plain
[`java.util.Properties`](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Properties.html)
file at a fixed address, so any tool can read it with the JDK alone,
and it is agnostic to any particularities of a given build tool. Publishing it costs the author a static
file; reading it costs a build one request per vendor.

## Do you suggest not having a central repository?

No. A central repository that keeps every version ever published, immutable and in one place, has real value. It
is also a great way to distribute a small open-source project released now and then: one account and one upload,
and every build finds the library, with no hosting for its author to keep alive. That low barrier to entry is
worth keeping.

What this proposal questions is that there is only one such repository, and that every library has to pass
through it. Today, that repository is Maven Central -
[Maven's default repository](https://maven.apache.org/ref/current/maven-model-builder/super-pom.html), and the
one most Java builds resolve from.

### The trouble with a single repository

Maven Central is, in effect, a monopoly: one repository, run by one company, that every build looks to and that
no build replaces on its own. That is a problem in itself, whatever its operator does today:

- **It is a single point of failure.** When Central cannot be reached, neither can any library published nowhere
  else. Its own [terms of service](https://central.sonatype.org/terms.html) state that outages may occur and
  that Sonatype is under no obligation to store or back up what is published.
- **It answers to no community.** Under the same terms, Sonatype decides at its sole discretion what it accepts,
  and may change the terms at any time without notice.
  [Google's mirror](https://storage-download.googleapis.com/maven-central/index.html), like those companies run,
  copies what Central holds, but publishing goes through Sonatype alone. The rest of the Java ecosystem is
  governed otherwise: the language through the [Java Community Process](https://jcp.org/en/home/index), the JDK
  under the [OpenJDK bylaws](https://openjdk.org/bylaws), and Maven at the
  [Apache Software Foundation](https://www.apache.org/foundation/how-it-works/).
- **It can change course quickly.** Sonatype is a private firm, majority-owned since
  [2019](https://www.sonatype.com/press-releases/vista-acquires-majority-interest-in-sonatype) by the private
  equity firm [Vista Equity Partners](https://www.vistaequitypartners.com/companies/sonatype/). Such a firm can
  change direction fast, all the more after a change of ownership, and the Java ecosystem has no say in either.
- **Its priorities become the ecosystem's.** Java modules have named a library the Java-native way since
  [Java 9](https://openjdk.org/projects/jdk9/) in 2017, almost ten years, yet Central
  [finds an artifact](https://central.sonatype.org/search/rest-api-guide/) by its coordinate, a class name or a
  checksum, never by its module name. A build cannot resolve a `requires` from Central without a mapping kept
  elsewhere, such as the [Jenesis Module Index](/modules/) - one reason modules are adopted slowly.

An alternative is therefore a contribution merely by existing: the textbook check on a monopoly is not that it
behaves well, but that its users could go elsewhere.

### Where the costs lead

The infrastructure is expensive, and Central is under constant pressure to pay for itself. Since October 2026,
publishing an artifact of a commercial nature requires Sonatype's paid
[Publisher Pro](https://central.sonatype.org/news/20260908_publisher_tiers_commercial_use/), and so does
publishing beyond [monthly quotas](https://central.sonatype.org/publish/maven-central-publishing-limits/) on file
count, release count and release size, which
[took effect](https://community.sonatype.com/t/maven-central-publishing-limits-are-now-in-effect/16675) the same
month. The quotas start where the busiest tenth of publishers begin, count every signature, checksum, POM,
sources and javadoc jar as a file, and may be adjusted over time; community projects can ask for an exemption.

Byte Buddy would mostly have stayed within today's quotas, but a
[release of it](https://repo1.maven.org/maven2/net/bytebuddy/) now publishes about 120 files and close to 70 MB,
so a second release in a month passes the size quota - as in about half the months since 2023 in which it
released. And quotas tighten. Sonatype's own repository manager was
[open source](https://github.com/sonatype/nexus-public) and without usage limits as Nexus Repository OSS, until
[version 3.77.0](https://community.sonatype.com/t/sonatype-nexus-repository-oss-is-now-community-edition/14324)
replaced it in 2025 with a
[Community Edition](https://www.sonatype.com/blog/sonatype-nexus-repository-community-edition): free of charge,
but not open source, used under an
[end-user licence agreement](https://www.sonatype.com/dnt/usage/community-edition-eula), and capped, with a
[paid Pro licence](https://help.sonatype.com/en/usage-center.html) required beyond the caps. A
[later release](https://community.sonatype.com/t/sonatype-nexus-repository-3-87-0-released/15852) cut those caps
to 40,000 components and 100,000 requests a day. Only a core with three formats remains open source.

Central's quotas count per organisation, across all of its namespaces, and every release must carry
[sources, javadoc, signatures and checksums](https://central.sonatype.org/publish/requirements/). An author who
nears them can only publish less: merge small modules or drop them, release fixes less often, or stop publishing
a second project of the same organisation. Each choice is reasonable for one author. Together they leave less on
offer, a cost every user of the ecosystem pays, though no invoice shows it.

And the restrictions come at an inconvenient time. The pace of publication is likely to accelerate with
agent-supported development: developers pushed
[nearly a billion commits to GitHub in 2025](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/),
a quarter more than the year before, and more code means more releases. Central is already strained - by
[Sonatype's own analysis](https://www.sonatype.com/blog/maven-central-and-the-tragedy-of-the-commons), 1% of IP
addresses consume 83% of its bandwidth - and with more releases and more builds, that strain will likely grow out
of proportion, with serious consequences for an ecosystem that depends on one repository. At the same time,
security issues in libraries are found at a far greater pace -
[published CVE records grew by 21% in 2025](https://github.blog/security/supply-chain-security/a-year-of-open-source-vulnerability-trends-cves-advisories-and-malware/) -
and every fix asks for a release, so authors must publish more often just as publishing more is what the quotas
restrict.

### Publishing beside it

The discovery file lets authors distribute what they build themselves, beside a central repository rather than
instead of it, and frees them from fitting their work to someone else's quota. Some already publish elsewhere:
[the Shibboleth project does not publish OpenSAML to Maven Central](https://shibboleth.atlassian.net/wiki/spaces/DEV/pages/1123844333),
because its terms require an indemnification its developers will not take on personally, and
[Jenkins releases its plugins and libraries](https://www.jenkins.io/doc/developer/publishing/artifact-repository/)
from its own repository. Today, a build finds them only once its user configures that repository; with a
discovery file, they are found by their name.

Other ecosystems already work this way. Go [asks the domain of a module path](https://go.dev/ref/mod#vcs-find)
where its code lives, and adds a [proxy and a checksum database](https://go.dev/ref/mod#private-module-privacy)
as a cache and a ledger, not as a place every module must be uploaded to. Homebrew
[formulae](https://docs.brew.sh/Formula-Cookbook) download each package from wherever its project hosts it, and
[taps](https://docs.brew.sh/Taps) let anyone publish formulae of their own.

- **Authors decide** where they publish, how finely and how often, and may remove an outdated version to save
  hosting, without a subscription.
- **The load is shared.** Every download an author's hosting serves is one Central does not serve.
- **Trust stays with the build.** Sonatype grants a group ID to whoever proves, by a
  [DNS record](https://central.sonatype.org/register/namespace/), that they own the domain it reverses to - the
  domain whose file a build reads. In 2024,
  [MavenGate](https://oversecured.com/blog/introducing-mavengate-a-supply-chain-attack-method-for-java-and-android-applications)
  showed how lapsed domains could be bought to take over group IDs; Sonatype
  [answered](https://thehackernews.com/2024/01/hackers-hijack-popular-java-and-android.html) that its checks
  prevent it. A discovery file always speaks for whoever owns the domain now, so what protects a build is what it
  recorded: declared signatures, and pinned checksums as Jenesis,
  [Maven](https://maven.apache.org/resolver/expected-checksums.html),
  [Gradle](https://docs.gradle.org/current/userguide/dependency_verification.html) and
  [Bazel](https://github.com/bazel-contrib/rules_jvm_external) record them, compared
  [side by side](/why/tool/#verify-what-the-build-downloads).

### Many central repositories

Once authors say where they publish, a central repository no longer depends on uploads to be complete. It could
populate itself by monitoring the authors' distribution servers: follow the latest links of the modules and
artifacts it knows, notice each new release as it appears, and fetch it as a build would. It could keep every
version as first fetched, close to publication, so that a version once seen never changes. Or it could keep only
the checksums it recorded then and refuse any later file that does not match - the guarantee of central storage,
without storing the artifacts. A discovery file may name Maven Central itself, so nothing changes for an author
who publishes there. And as a project grows into different needs, its author can move it elsewhere by
changing the file, as the owner of a domain moves a website to another host without changing its address.

Anyone could run such a repository, so there need not be only one. Several could exist side by side, competing on
availability, on the record they keep and on the checks they run, and offering proxying and supply chain
security as a service - a market that a single central repository does not allow for today.

Such a market also lets the Java ecosystem face a question it will have to entertain at some point: whether
every version must be kept forever. Maven Central
[never removes what was published](https://central.sonatype.org/faq/can-i-change-a-component/), but no one can
hoard all code forever, and the constraints of recent years show where that premise leads. With several
repositories, an author can drop an outdated version from their own hosting, and a repository that still keeps
it can charge for doing so. A build that relies on Byte Buddy 0.1, a pre-release from 2014, would then pay a
premium to keep it available - and that cost is an incentive to migrate away once the legacy has become too
expensive.

Hosting thereby moves back towards the authors who produce the code, and the choice of whom to trust towards the
users who run it.

## Describing Maven artifacts

The rest of this page is the proposal itself: the file a domain publishes and how a build reads it, starting with
Maven artifacts, then modules mapped to Maven, then modules alone, and finally the sources of a release.

A domain publishes the file at `https://<domain>/.well-known/java-repository.properties`, a
[well-known location](https://www.rfc-editor.org/rfc/rfc8615), in UTF-8. Its `maven`
key says where the artifacts named after that domain are, and the name in brackets the artifact it is for:

```properties
maven[build.jenesis]=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis].suffixes=none
```

This file at `jenesis.build` says that the artifact `build.jenesis` is attached to the GitHub releases of
Jenesis, and that those releases hold no snapshots. A dependency on `build.jenesis:build.jenesis:0.15.4` then
downloads `https://github.com/jenesis/jenesis/releases/download/v0.15.4/build.jenesis-0.15.4.jar`. A key without
brackets, `maven=...`, serves every artifact of every group below the domain.

### Which file answers

For `net.bytebuddy.agent`, a tool reads the file of `bytebuddy.net` - the two labels a vendor owns - and the
file of `agent.bytebuddy.net` only where `bytebuddy.net` publishes none. The first file found speaks for every
name below its domain, so one request answers for all of a vendor's groups, and a key it does not hold is
absent rather than asked of a subdomain. A vendor whose subdomains publish files of their own adds `delegate=true`:
those files are then read as well, the most specific one holding a key answers, and the vendor's own entries
stand for the rest.

### Several projects under one domain

A domain often serves more than one project, each released on its own and with versions of its own. Each key
then names the artifacts it is for in brackets, and the keys beside it carry the same selector. `jenesis.build`
serves the build tool, the launcher, the crawler and the modules of Jenesis Repository, all in the group
`build.jenesis`, from the GitHub releases of four repositories:

```properties
maven[build.jenesis]=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis].latest=https://github.com/jenesis/jenesis/releases/latest/download/{artifactId}.pom
maven[build.jenesis.launcher]=https://github.com/jenesis/jenesis-launcher/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis.launcher].latest=https://github.com/jenesis/jenesis-launcher/releases/latest/download/{artifactId}.pom
maven[build.jenesis.crawler]=https://github.com/jenesis/jenesis-modules/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis.crawler].latest=https://github.com/jenesis/jenesis-modules/releases/latest/download/{artifactId}.pom
maven[build.jenesis.repository.*]=https://github.com/jenesis/jenesis-repository/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis.repository.*].latest=https://github.com/jenesis/jenesis-repository/releases/latest/download/{artifactId}.pom
```

`maven` selects by artifact ID, and `module` and `moduletomaven` select by module name. A selector ending in `*`
selects every name that starts with the rest, as `maven[build.jenesis.repository.*]` does for the modules of
Jenesis Repository, all named `build.jenesis.repository.*`. The exact name wins over the longest such prefix, and
either over the key for all. A name that no key of the file selects, in a file without a key for all, is absent
from it.

### Roots and templates

A location takes one of two forms:

- A **root** is a URI without placeholders: a traditional Maven repository such as Maven Central, a Nexus or an
  Artifactory, or any web server holding files in the Maven layout. It is read with its checksums, and its
  `maven-metadata.xml` is merged with that of the usual repositories, so a version range sees the versions of
  both - `maven=https://maven-repository.example.com/releases/`.
- A **template** names each file through placeholders, which suits a flat list of downloads such as the assets
  of a GitHub release. Where a template names `{type}`, each file is checked against the `.sha512`, `.sha256` or
  `.sha1` beside it, the strongest one present, and a mismatch fails the build.

A Maven template fills in `{groupId}` (`net.bytebuddy`), `{groupPath}` (`net/bytebuddy`), `{artifactId}`,
`{version}`, `{-classifier}` (`-sources`, or nothing for the plain jar) and `{type}` (`jar`, `pom`, `jar.asc`,
`jar.sha256`). A template without `{-classifier}` or `{type}` serves only the plain jar, so a sources jar or a
signature is never answered with the jar itself.

### Which versions a key serves

Two keys beside a key restrict the versions it serves, and leave every other version to the usual repositories:

- **`<key>.since=<version>`** names the first version, so an author can move downloads to a new place from one
  release on. Versions are ordered as
  [Maven orders them](https://maven.apache.org/pom.html#version-order-specification): `1.2.3-rc.1` comes before `1.2.3`, `1.10.0` after it.
- **`<key>.suffixes=<suffix>[,<suffix>...]`** lists the qualifiers it serves - the part of a version after its
  first dash, matched by its leading word, ignoring case. `none` names a version without one; without the key,
  every version is served.

With `maven.since=0.16.0` and `maven.suffixes=none`, `1.2.3` is served, while `1.2.3-SNAPSHOT` and everything
before `0.16.0` is not. The metadata of a root lists only the versions its key serves.

### The newest version

A template cannot list versions, so "the newest release" comes from a link beside it, `<key>.latest`. A tool
sends the link a `HEAD` request, follows no redirect, and reads the version from where it redirects to, matched
against the template:

```properties
maven[build.jenesis].latest=https://github.com/jenesis/jenesis/releases/latest/download/{artifactId}.pom
```

GitHub [redirects](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
`releases/latest/download/<name>` to `releases/download/v<version>/<name>` of the newest release, whatever
`<name>` is, so the link names the version without downloading anything. The version is then
checked like any other, and the template answers Maven metadata naming it, merged with that of the usual
repositories.

A link may instead name a `maven-metadata.xml`, so that the files come from one place and the versions from a
Maven repository - a release's assets, say, and the list of what was published that a privately hosted Maven
repository keeps:

```properties
maven[build.jenesis].latest=https://maven-repository.example.com/releases/{groupPath}/{artifactId}/maven-metadata.xml
```

A link ending in `/maven-metadata.xml` is downloaded rather than sent a `HEAD` request. Its release, among the
versions the key serves, is the newest version, and the template answers the file's versions, limited to those
it serves, as its metadata - so a version range sees them too.

### Reading the files with Jenesis

Jenesis reads the files where `jenesis.repository.discovery` is set, on the command line or in
`jenesis.properties`. It asks about every Maven group before any configured repository, reads each domain's file
once per build, and resolves what no file names as it always has. To rely on the files alone, empty the
repositories beside them, so that nothing falls back:

```
jenesis.repository.discovery=true
jenesis.maven.uri=
jenesis.module.uri=
```

A location over plain `http` is followed only where `jenesis.repository.insecure` allows it.

{% demos 69 %}

## From modules to Maven artifacts

A module that is published as a Maven artifact is mapped to it by the `moduletomaven` key, whose value is a
Maven coordinate, `<groupId>:<artifactId>[:<extension>[:<classifier>]]`, without its version:

```properties
moduletomaven=build.jenesis:{module}
```

`{module}` is the module's name, so this one line maps every module below `jenesis.build` to the artifact of the
same name in the group `build.jenesis`. The artifact then resolves as any Maven dependency does - through the
`maven` key of the previous chapter and the usual Maven repositories - and a request without a version takes the
newest release its Maven metadata names. A domain that publishes both keys needs no entry in a module index.

Where artifact names follow another pattern, `{-suffix}` follows it. It is the part of the module's name below
the file's domain, its labels joined by dashes after a leading one: nothing for `net.bytebuddy`, `-agent` for
`net.bytebuddy.agent`. One line maps every Byte Buddy module:

```properties
moduletomaven=net.bytebuddy:byte-buddy{-suffix}
```

A module whose suffix names no artifact, such as `net.bytebuddy.utility`, finds nothing and resolves as if the
file did not name it. A coordinate without placeholders belongs to one module only - the one whose own domain
publishes the file - unless its key selects a module. An artifact that follows no pattern is then named for its
module in the same file:

```properties
moduletomaven[com.example.legacy]=com.example:example-classic
```

A build that resolves modules through Maven, reading their POMs, asks `moduletomaven` first. In Jenesis that is
the `modular_to_maven` layout, the one a `module-info.java` gets by default.

## Pure module repositories

A module that is not published to Maven, or a build that resolves modules on the module path alone, uses the
`module` key. Its value is a location, in the same two forms:

- A **template** names each module file. `{module}`, `{-suffix}`, `{version}`, `{-classifier}` and `{type}` are
  filled in, and files are checked against their checksums as for Maven.
- A **root** is a Jenesis module service, such as `https://repo.jenesis.build/`, asked as a configured module
  repository is.

```properties
module[build.jenesis]=https://github.com/jenesis/jenesis/releases/download/v{version}/{module}-{version}{-classifier}.{type}
module[build.jenesis].latest=https://github.com/jenesis/jenesis/releases/latest/download/{module}.jar
module[build.jenesis].suffixes=none
```

A build that resolves a module from its jar and the `requires` of its `module-info` asks `module` first - in
Jenesis, the `modular` layout - and so downloads `build.jenesis-<version>.jar` with no POM and no Maven at all.
`module.latest` names the newest version for a `requires` that no pin names. A Jenesis module service may serve
as the latest link too, `https://repo.jenesis.build/module/{module}/{module}.jar`: it names the version in a
`Jenesis-ModuleVersion` header, which is read before the redirect.

A key that does not answer leaves the request to the other, so a domain that publishes both `module` and
`moduletomaven` serves either kind of build.

{% demos 68 %}

## The sources of a release

A release's sources belong to it as much as its jar does, so the file names them too. Maven Central asks for a
sources jar beside every artifact; here, the domain names an archive of the sources of each version instead,
typically the one a code host keeps of every tag, as GitHub keeps
[an archive of every release](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives):

```properties
sources[build.jenesis]=https://github.com/jenesis/jenesis/archive/refs/tags/v{version}.zip
```

`sources` is a template that names `{version}`, and it takes the placeholders of `maven` for a Maven dependency
and those of `module` for a module. It is selected like the other keys, so a domain with several projects names
the archive of each, and `.since` and `.suffixes` limit the versions it answers for. Jenesis lists the archive in
the [CycloneDX](https://cyclonedx.org/docs/1.6/json/#components_items_externalReferences_items_type) SBOM of a
build, as the `source-distribution` reference of each dependency the file answers for, so whoever reads the SBOM
finds the code each jar was built from.

{% demos 68 %}

## Publishing everything a build may ask for

One release can serve every kind of build at once: the module path, a module resolved through Maven, and a Maven
dependency, each with its signatures and checksums. Jenesis does so itself. Its release stages a Maven
repository, and [JReleaser](https://jreleaser.org) attaches the jar and the POM to the GitHub release. JReleaser [signs](https://jreleaser.org/guide/latest/reference/signing.html)
every file it attaches, and [`checksum.individual`](https://jreleaser.org/guide/latest/reference/checksum.html)
has it upload a `.sha256` beside each, as in this excerpt of Jenesis's own
[`jreleaser.yml`](https://github.com/jenesis/jenesis/blob/main/jreleaser.yml):

```yaml
signing:
  active: ALWAYS
  pgp:
    armored: true
    mode: MEMORY

release:
  github:
    owner: jenesis
    name: jenesis
    tagName: 'v{{projectVersion}}'

checksum:
  individual: true

files:
  artifacts:
    - path: 'target/stage/maven/output/build/jenesis/build.jenesis/{{projectVersion}}/build.jenesis-{{projectVersion}}.jar'
    - path: 'target/stage/maven/output/build/jenesis/build.jenesis/{{projectVersion}}/build.jenesis-{{projectVersion}}.pom'
```

Every release then holds `build.jenesis-<version>.jar` and `.pom`, each with an `.asc` and a `.sha256`, and one file at
[`https://jenesis.build/.well-known/java-repository.properties`](/.well-known/java-repository.properties) points
every kind of request at them:

```properties
module[build.jenesis]=https://github.com/jenesis/jenesis/releases/download/v{version}/{module}-{version}{-classifier}.{type}
module[build.jenesis].latest=https://github.com/jenesis/jenesis/releases/latest/download/{module}.jar
module[build.jenesis].suffixes=none
moduletomaven=build.jenesis:{module}
maven[build.jenesis]=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven[build.jenesis].latest=https://github.com/jenesis/jenesis/releases/latest/download/{artifactId}.pom
maven[build.jenesis].suffixes=none
```

| A build asks for | Answered by | Downloads |
|---|---|---|
| `requires build.jenesis` on the module path | `module` | `build.jenesis-<version>.jar` |
| `requires build.jenesis`, resolved through Maven | `moduletomaven`, then `maven` | `build.jenesis-<version>.pom`, then the jar |
| the Maven dependency `build.jenesis:build.jenesis:<version>` | `maven` | the POM, then the jar |
| a signature | `module` or `maven` | `.jar.asc`, `.pom.asc` |
| a checksum, to check each download | the same template | `.jar.sha256`, `.pom.sha256` |
| its sources | `sources` | nothing: the archive GitHub keeps of the release's tag |
| the newest version | `module.latest`, `maven.latest` | nothing: a `HEAD` request that GitHub redirects |

The same file holds such keys for the launcher, the crawler and Jenesis Repository, which are released from
repositories of their own, as *[Several projects under one domain](#several-projects-under-one-domain)* shows.

The `module` template names files by module name, which works because Jenesis's artifact ID is its module name.
Where the two differ, name the files the way the artifacts are named instead, with `{-suffix}` -
`.../byte-buddy{-suffix}-{version}{-classifier}.{type}` - or publish `moduletomaven` alone.

### Attaching the files to earlier releases

A release made before its POM was attached leaves that POM to the usual repositories, if the build has any.
[`github-backfill.sh`](https://github.com/jenesis/jenesis/blob/main/github-backfill.sh) attaches what such
releases lack, for any project on GitHub whose artifacts a Maven repository holds. It needs `gh`, signed in to an
account that may edit the releases, and `curl`:

```
./github-backfill.sh --repository=jenesis/jenesis --artifact=build.jenesis:build.jenesis
./github-backfill.sh --repository=jenesis/jenesis --artifact=build.jenesis:build.jenesis --apply
```

For every release whose tag matches `--tag` (`v{version}` by default), or for the versions named, it downloads the
jar and the POM of each `--artifact` with their `.asc` signatures, checks each against its `.sha1`, and attaches
them with a `.sha256`. The first command only lists what it would upload; `--apply` uploads it. A file already on
a release must be identical to the repository's copy, and a signature is copied, never made. The repositories are
read from `MAVEN_REPOSITORY_URI` as Jenesis reads it, or from `--maven`, so the files can come from a mirror such
as [Google's](https://storage-download.googleapis.com/maven-central/index.html).

`--sources` and `--javadoc` add those jars, but neither is needed, and Jenesis's own releases attach neither. Sources and javadoc are not really repository
artifacts: GitHub already publishes the
[source code of every release](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives)
as an archive, and javadoc jars seem rather outdated - Central accepts
[placeholders](https://central.sonatype.org/publish/requirements/) for both, and Jenesis can stage an
[intentionally empty one](/tool/publishing/#staging-the-release-tree).


## Implementing a client

This chapter is for the authors of tools that read the file.

### The grammar

The file is read as `java.util.Properties` reads one, with `#` comments and `\` continuations, in UTF-8. Of a
key named twice the last value counts, and a key a reader does not know is ignored, so the format can grow:

```
file          = *( entry / delegate )
entry         = key "=" value
delegate      = "delegate=" ( "true" / "false" )     ; false, the default: no subdomain is read
key           = kind [ "[" selector "]" ] [ ".since" / ".suffixes" / ".latest" ]
kind          = "module" / "moduletomaven" / "maven" / "sources"
selector      = 1*( ALPHA / DIGIT / "_" / "." / "-" ) [ "*" ] ; an artifact ID for maven, a module name
                                                     ; otherwise, or the start of one before "*"
module        = location
moduletomaven = coordinate
maven         = location
sources       = location                             ; a template naming {version}
latest        = https-uri                            ; beside a template naming {version}: a redirecting
                                                     ; link, or one ending in "/maven-metadata.xml"
coordinate    = groupId ":" artifactId [ ":" extension [ ":" classifier ] ]
location      = https-uri                            ; names "://": a root, or a template with placeholders
placeholder   = "{" ( "groupId" / "groupPath" / "artifactId" / "module" / "-suffix"
                    / "version" / "-classifier" / "type" ) "}"
since         = version
suffixes      = suffix *( "," suffix )
suffix        = 1*( ALPHA / DIGIT )                  ; "none" names a version without one
```

| Placeholder | `maven` | `module` | `moduletomaven` | `sources` |
|---|---|---|---|---|
| `{groupId}`, `{groupPath}`, `{artifactId}` | yes | | | for a Maven dependency |
| `{module}`, `{-suffix}` | | yes | yes | for a module |
| `{version}` | yes | yes | | yes |
| `{-classifier}`, `{type}` | yes | yes | | |

### Finding a key

To find a key for a module name, or for a group ID and an artifact ID:

1. Skip a name that cannot be a domain: one label, or a label with anything but letters, digits, `_` and `-`.
2. Reverse the labels into domains, shortest first, from two labels to all of them: `net.bytebuddy.agent` gives
   `bytebuddy.net`, then `agent.bytebuddy.net`.
3. Fetch each domain's file once per run, remembering an absent file as well as a present one. A file that cannot
   be fetched - a `404`, an unknown host, a proxy that cannot reach it - is absent.
4. Skip a domain without a file. In a file, take the key that selects the module name or artifact ID exactly,
   else the one whose selector is the longest prefix of it, else the key for all. That key becomes the answer,
   unless it is the key for all, its value a coordinate without placeholders, and the domain shorter than the
   name's own.
5. Stop after the first file found, unless it says `delegate=true`; the last answer found counts.

### Answering a request

1. Choose the keys: `maven` for a Maven request; for a module, `module` then `moduletomaven` on the module path,
   or the other way round when resolving through Maven.
2. For a request without a version against a template, read its latest link. A link ending in
   `/maven-metadata.xml` is downloaded, and its release among the versions the key serves is the version; a
   Maven metadata request is answered with its versions, limited the same way. Any other link is sent a `HEAD`
   request without following redirects: a `404` names no version, and otherwise take the
   `Jenesis-ModuleVersion` or `Jenesis-MavenVersion` header, or match the `Location` against the template up to
   the end of the path segment holding `{version}`.
3. Check the version against `.since` and `.suffixes`; a request still without a version passes over a key
   that restricts versions.
4. Resolve: expand a coordinate and resolve it as a Maven artifact; ask a root as a repository, listing only
   the versions the key serves; fill in a template, download the file, and check it against the strongest
   checksum beside it.
5. Check the name a module's jar declares, in its `module-info` or as its `Automatic-Module-Name`, against the
   module name that was asked for, whichever key answered.
6. Where a key does not answer, try the next one, then the configured repositories.

### Failing and trusting

A tool fails, naming the file, on a key without a value, a selector that is no name or prefix, a suffix that is
not a word, a `delegate` that is neither `true` nor `false`, an unknown placeholder, a coordinate that names no
artifact, a coordinate in `module` or a location in `moduletomaven`, a `sources` that is no template naming
`{version}`, a latest link beside a root, a coordinate or a template without `{version}`, a latest link that leads
elsewhere or names no version, and a module jar that declares another name than the one asked for, or none.

Every location is read over `https` once its placeholders are filled in, and a redirect is followed only to
`http` or `https`, so no file can make a tool read a local `file:` or `jar:` URI. A certificate that does not
verify fails the build. A domain answers only for names below it, and checking the name a downloaded module
declares keeps it from answering for one of them with another module, which a coordinate in `moduletomaven` could
otherwise name. The file only says where a file comes from: a pinned checksum or a declared signature
still decides what is accepted. A domain that changes hands passes its file to the new owner, so for every
version a build pinned, the new owner can break the build but never change what it accepts; a version the build
did not pin is only as trustworthy as the domain's owner, unless a
[declared signature](/tool/securing-the-supply-chain/#provenance-who-produced-the-bytes) names who must have
produced it.
