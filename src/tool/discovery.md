---
order: 18
title: Discovery (proposal)
description: A proposed well-known file by which the owner of a domain says how its Java modules and Maven artifacts are published - the keys, their grammar, and how Jenesis reads them.
---

<div class="warning">
  The file format on this page is a <strong>proposal</strong> for any Java tool to adopt, so it may still change
  as others take it up. Jenesis reads it where <code>jenesis.repository.discover</code> is set.
</div>

A Java module name and a Maven groupId are reversed domain names: `net.bytebuddy` belongs to `bytebuddy.net`.
This proposal lets the owner of that domain say, in a small file on its website, how the modules and artifacts
named after it are published - which Maven artifact a module is, and where its files can be downloaded. A
domain that publishes the file needs no entry in a central module index, and a build that reads it asks the
domain first.

The format names Java modules and Maven groups, not a build tool, and it is a plain `java.util.Properties` file,
so any tool can read it with the JDK alone. This page describes the file first, then its grammar, and ends with
how Jenesis reads it and how Jenesis publishes its own.

## Where the file lives

A domain publishes the file at `https://<domain>/.well-known/java-repository.properties`, in UTF-8. A tool
reads the file of the shortest domain first - the two labels a vendor owns - and the file of a longer domain
only where no shorter one publishes a file:

| Looking up | Reads |
|---|---|
| `net.bytebuddy.agent` | `bytebuddy.net`, and `agent.bytebuddy.net` only where `bytebuddy.net` has no file |
| `build.jenesis` | `jenesis.build` |

The first file found speaks for every name below its domain: a key it does not hold is absent, not asked of a
subdomain. One request therefore answers for all the modules and groups of a vendor, and whoever owns a domain
controls its subdomains anyway. A vendor whose subdomains publish files of their own says so with `stop=false`:
the files of its subdomains are then read as well, the most specific file holding a key answers, and its own
entries stand for the subdomains whose files do not hold the key. A name that cannot be a domain - a single label, or one with a character such
as `+` - is never looked up.

## Three keys

The file has two keys for modules, one for each way a build resolves them, and one for Maven groups:

| Key | Value | Says |
|---|---|---|
| `module` | a location | where a module's files are |
| `moduletomaven` | `<groupId>:<artifactId>[:<extension>[:<classifier>]]` | which Maven artifact a module is published as |
| `maven` | a location | where a Maven group's artifacts are |

A location is any value naming `://`, which a Maven coordinate never does, so a `module` that names a coordinate
or a `moduletomaven` that names a location fails the build. A module mapped to a Maven artifact resolves as that
artifact, through the `maven` key and the usual Maven repositories. So a domain describes everything it
publishes in a few lines:

```properties
module=https://github.com/jenesis/jenesis/releases/download/v{version}/{module}-{version}{-classifier}.{type}
moduletomaven=build.jenesis:{module}
maven=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
```

The first says that every module below `jenesis.build` is attached as a jar to its GitHub releases. The second
maps every such module to the artifact of the same name in the group `build.jenesis`, written as Maven writes a
coordinate, without its version. The third says that the group's artifacts are attached to the same releases.

### Which module key answers

A tool that resolves modules on the module path alone, from their jars and the `requires` of their
`module-info`, asks `module` first; a tool that resolves modules through Maven, reading their POMs, asks
`moduletomaven` first. A key that does not answer leaves the request to the other: a template cannot name the
newest release, so a request without a version is answered through `moduletomaven` and the Maven metadata even
on the module path. A domain that publishes both keys therefore serves either kind of build, and a module path
needs no Maven at all.

## Locations: roots and templates

A location is an `https` URI in one of two forms.

A **root** is a URI without placeholders. For `maven` it is a traditional Maven repository - Maven Central, a
Nexus or Artifactory, or a folder in the Maven layout on any web server - read as a configured Maven repository
is, with its checksums. Its metadata is merged with that of the usual repositories, as Maven merges metadata
across repositories, so a version range or "the newest release" sees the versions of both:

```properties
maven=https://maven.example.com/releases/
```

For `module`, a root is a Jenesis module service such as `https://repo.jenesis.build/`.

A **template** is a URI with placeholders, which are filled in for every file a build asks for. It suits a
flat list of downloads, such as the assets of a GitHub release. Where the template names `{type}`, each file is
checked against a `.sha512`, `.sha256` or `.sha1` file next to it, the strongest one present, and a mismatch
fails the build. A template lists no versions, so it serves the versions a build names; the newest one comes
from a latest link, described next, and a version range is asked of the usual repositories.

## The newest version

A request that names no version - a `requires` without a pin, or "the newest release" of a Maven artifact -
is answered by a template only through **`<key>.latest=<link>`** beside it. A tool sends the link a `HEAD`
request and follows no redirect. It reads the version from a `Jenesis-ModuleVersion` header for `module`, or
`Jenesis-MavenVersion` for `maven`, where the answer has one, and otherwise from where the link redirects to,
matched against the template up to the end of the path segment that holds `{version}`:

```properties
module=https://github.com/jenesis/jenesis/releases/download/v{version}/{module}-{version}{-classifier}.{type}
module.latest=https://github.com/jenesis/jenesis/releases/latest/download/{module}.jar
```

GitHub redirects `releases/latest/download/<name>` to `releases/download/v<version>/<name>` of the newest
release, whatever `<name>` is, so the link names the version without downloading anything. A Jenesis module
service names it in its header for its unversioned path, `https://repo.jenesis.build/module/{module}/{module}.jar`.
The version is then checked against `<key>.since` and `<key>.suffixes` like any other, a link that answers `404`
leaves the request to the usual repositories, and a `maven` template answers Maven metadata naming that
version, merged with that of the usual repositories. A root or a coordinate lists its versions itself, so a
latest link beside one fails the build.

## Placeholders

| Placeholder | Filled with | `maven` | `module` | `moduletomaven` |
|---|---|---|---|---|
| `{groupId}` | `net.bytebuddy` | yes | | |
| `{groupPath}` | `net/bytebuddy` | yes | | |
| `{artifactId}` | `byte-buddy-agent` | yes | | |
| `{module}` | `net.bytebuddy.agent` | | yes | yes |
| `{-suffix}` | `-agent` | | yes | yes |
| `{version}` | `1.15.11` | yes | yes | |
| `{-classifier}` | `-sources`, or nothing for the plain jar | yes | yes | |
| `{type}` | `jar`, `pom`, `jar.asc`, `jar.sha256` | yes | yes | |

`{-suffix}` is the part of a module's name below the domain of the file that answered, its labels joined by
dashes after a leading one: nothing for `net.bytebuddy`, `-agent` for `net.bytebuddy.agent`. A template without
`{-classifier}` or `{type}` serves only the plain jar, so a sources jar or a signature is never answered with
the jar itself. A placeholder that the value does not know fails the build.

## Naming a module's Maven artifact

A coordinate with placeholders applies to every module below its domain. Where artifact names follow the module
names, `{module}` is enough; where they follow another pattern, `{-suffix}` usually is:

```properties
moduletomaven=net.bytebuddy:byte-buddy{-suffix}
```

This maps `net.bytebuddy` to `net.bytebuddy:byte-buddy` and `net.bytebuddy.agent` to
`net.bytebuddy:byte-buddy-agent`. A module whose suffix names no artifact, such as `net.bytebuddy.utility`,
finds nothing in the Maven repositories and resolves as if the file did not name it.

A coordinate without placeholders belongs to one module only - the one whose own domain publishes the file - so
an artifact that follows no pattern is named in a file at its module's own domain. A module without a version
in its request resolves to the newest release that the Maven metadata of the mapped artifact names.

## Restricting the versions a key serves

Two keys beside a key say which versions it serves:

- **`<key>.since=<version>`** names the first version. Earlier versions are asked of the usual repositories, so
  a project can move its downloads to a new location from one release on. Versions are ordered as Maven orders
  them: `1.2.3-rc.1` comes before `1.2.3`, and `1.10.0` after it.
- **`<key>.suffixes=<suffix>[,<suffix>...]`** lists the version qualifiers it serves - the part of a version
  after its first dash. A suffix matches the leading word of a qualifier, ignoring case, and `none` names a
  version without one. Without the key, every version is served.

```properties
maven=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven.since=0.16.0
maven.suffixes=none
```

Here `1.2.3` is served, while `1.2.3-SNAPSHOT` and every version before `0.16.0` go to the usual repositories;
`maven.suffixes=none,rc` would also serve `1.2.3-rc.1` and `1.2.3-RC2`. The metadata of a root lists only the
versions its key serves. A request that names no version is checked once a latest link named it; without
one, it cannot be checked against either key, so a key restricted by one leaves it to the usual repositories.

## The grammar

The file is read as `java.util.Properties` reads one, with `#` comments and `\` continuations, in UTF-8:

```
file          = *( entry ) [ stop ]
entry         = key "=" value
stop          = "stop=" ( "true" / "false" )         ; true, the default: no subdomain is asked
key           = ( "module" / "moduletomaven" / "maven" ) [ ".since" / ".suffixes" / ".latest" ]
module        = location
moduletomaven = coordinate
maven         = location
latest        = https-uri                            ; beside a template naming {version}, sent a HEAD request
coordinate    = groupId ":" artifactId [ ":" extension [ ":" classifier ] ]
location      = https-uri                            ; names "://": a root, or a template with placeholders
placeholder   = "{" ( "groupId" / "groupPath" / "artifactId" / "module" / "-suffix"
                    / "version" / "-classifier" / "type" ) "}"
since         = version
suffixes      = suffix *( "," suffix )
suffix        = 1*( ALPHA / DIGIT )                  ; "none" names a version without one
```

Of a key named twice, the last value counts, as `java.util.Properties` reads it, so every reader of the file
sees the same entry. A key that a reader does not know is ignored, so the format can grow without breaking older
readers. These files fail the build, naming the file:

- a key without a value, a suffix that is not a single word of letters and digits, and a `stop` that is
  neither `true` nor `false`;
- a placeholder the value does not know, and a coordinate that names no artifact;
- a coordinate in `module`, and a location in `moduletomaven`;
- a latest link beside a root or a coordinate, one that redirects somewhere the template does not describe, and
  one that names no version;
- a location that is not `https`, such as a `file:` or `jar:` URI.

## Trusting the file

The file is read over HTTPS, so the domain's certificate vouches for it. A location the file names is read over
HTTPS as well, after its placeholders are filled in, and a download is never redirected to anything but an
`http` or `https` location, so no file can make a tool read a local file. A file that cannot be fetched counts
as absent - no file, a host that does not exist, or one a proxy cannot reach - while a certificate that does
not verify fails the build. The file only says where a file comes from: a pinned dependency is still checked
against its pin, and a declared signature against its signature, so a domain that changed hands can break a
build but never change what it accepts.

## Reading the file with Jenesis

Jenesis reads the files when `jenesis.repository.discover` is set, on the command line or in
`jenesis.properties`:

```
java -Djenesis.repository.discover=true build/jenesis/Make.java
```

It then asks about every module and every Maven group before it asks any configured repository, reads each
domain's file once per build, and resolves anything a file does not name exactly as it does today. The
`modular` layout resolves modules on the module path and asks `module` first; `modular_to_maven`, the layout a
`module-info.java` gets by default, resolves them through Maven and asks `moduletomaven` first:

| Key | Default | Meaning |
|---|---|---|
| `jenesis.repository.discover` | `false` | Read the files of a module's or group's domain before the module and Maven repositories |

The file is always read at `https://<domain>/.well-known/java-repository.properties`: its location is a convention,
not a setting, so every build asks a domain the same question. A location named over plain `http` is followed only
where `jenesis.repository.insecure` allows it, and under `jenesis.repository.offline` no domain is asked at all.

{% demos 68, 69 %}

## Example: publishing Jenesis through its GitHub releases

Jenesis itself shows the whole route, from a release to the file that points at it. Its release stages a Maven
repository with `stage`, run with `jenesis.project.sources=true` and `jenesis.project.documentation=true`, so
`target/stage/maven/output/` holds the jar, the POM, the sources jar and the javadoc jar of
`build.jenesis:build.jenesis`. [JReleaser](https://jreleaser.org) attaches those four files to the GitHub
release, signs each one, and writes a checksum file beside each:

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
    - path: 'target/stage/maven/output/build/jenesis/build.jenesis/{{projectVersion}}/build.jenesis-{{projectVersion}}-sources.jar'
    - path: 'target/stage/maven/output/build/jenesis/build.jenesis/{{projectVersion}}/build.jenesis-{{projectVersion}}-javadoc.jar'
```

Every release then carries `build.jenesis-<version>.jar`, `.pom`, `-sources.jar` and `-javadoc.jar`, each with
a `.asc` signature and a `.sha256` checksum. One file at
[`https://jenesis.build/.well-known/java-repository.properties`](/.well-known/java-repository.properties)
covers every way a build asks for them:

```properties
module=https://github.com/jenesis/jenesis/releases/download/v{version}/{module}-{version}{-classifier}.{type}
module.latest=https://github.com/jenesis/jenesis/releases/latest/download/{module}.jar
module.suffixes=none
moduletomaven=build.jenesis:{module}
maven=https://github.com/jenesis/jenesis/releases/download/v{version}/{artifactId}-{version}{-classifier}.{type}
maven.latest=https://github.com/jenesis/jenesis/releases/latest/download/{artifactId}.pom
maven.suffixes=none
```

On the module path, a `requires build.jenesis` downloads `build.jenesis-<version>.jar` through `module`, with no
POM. Through Maven, it maps to `build.jenesis:build.jenesis` through `moduletomaven`, and a `pom.xml`
dependency on that artifact goes straight to `maven`. Through `{type}` and `{-classifier}`, the template serves
the jar, the POM, the sources and javadoc jars and every signature, and each file is checked against its
`.sha256`. The two latest links name the newest release, which GitHub's `releases/latest` points to, so a
`requires build.jenesis` without a pin resolves to it. `module.suffixes=none` and `maven.suffixes=none` say that
the releases hold no snapshots. A file that a release does not hold - the POM of a release made before it was
attached - and a version range, which a template cannot answer, are asked of the Maven repositories - Maven
Central by default, where the same files are published.
