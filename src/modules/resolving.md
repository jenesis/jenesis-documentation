---
order: 2
title: Resolving through repo.jenesis.build
description: The URL shapes that turn a module name into a Maven Central download - the four routes, versions, classifiers, the redirect contract, using it from the build tool, and pointing at a mirror.
---

The Jenesis Module Index is served as an HTTP service at **[repo.jenesis.build](https://repo.jenesis.build/)**.
You ask for a module name, optionally a version, and a file name. The service answers with a **302
redirect** to the real file on Maven Central. Nothing is re-hosted: the module index only decides *which*
Maven artifact a module name maps to and points you at it.

The whole contract is a small, stable set of URL shapes, so anything that can follow a redirect is a
client - `curl -L`, a browser, or the Jenesis build tool. Every redirect is derived from one row of a
plain text file, and you can [read those files directly](#reading-the-index-directly) if you would
rather resolve yourself.

## The four routes

The path segment before the module name selects the route. The route decides which version space you
are addressing and which kind of module it can serve:

| Route | URL shape | Version segment is… |
| --- | --- | --- |
| `artifact` | `/artifact/<module>[/<mavenVersion>]/<file>` | The **Maven coordinate version**. Any file extension passes through verbatim. Serves named and automatic modules. |
| `module` | `/module/<module>[/<moduleVersion>]/<file>.jar` | The **module-info version** the publisher declared. Named modules only. |
| `sources` | `/sources/<module>[/<moduleVersion>]/<file>.jar` | The module-info version; the redirect appends `-sources` to the Maven file name. Named modules only. |
| `documentation` | `/documentation/<module>[/<moduleVersion>]/<file>.jar` | The module-info version; the redirect appends `-javadoc` to the Maven file name. Named modules only. |

Two version spaces are in play. `/artifact/` is keyed by the **Maven version**, the number you see in a
POM. `/module/`, `/sources/`, and `/documentation/` are keyed by the **module-info version**, the string
the publisher embedded in `module-info.class`. Pick the route that matches the version you are holding.

The `<file>` segment is required, and its name must start with the module name. Everything after that
is the extension, either after a `.` or after `-<classifier>.`. The `/module/`, `/sources/`, and
`/documentation/` routes accept **`.jar` only**; `/artifact/` accepts any extension.

<div class="note">
  Only a <strong>named</strong> module - one that ships a real <code>module-info.class</code> - is
  reachable through <code>/module/</code>, <code>/sources/</code>, and <code>/documentation/</code>. An
  <strong>automatic</strong> module, which only sets <code>Automatic-Module-Name</code> in its manifest,
  resolves through <code>/artifact/</code> alone. The same goes for the JDK's own module names
  (<code>java.*</code>, <code>jdk.*</code>): no Maven artifact can supply those on the module path, so
  <code>/module/</code> refuses them while <code>/artifact/</code> still answers.
</div>

## Versions are optional

The version segment can always be omitted. Leave it out and the service returns the **newest** version.
Newest is decided by Maven's version ordering, so a pre-release such as `2.1.0-alpha1` ranks above
`2.0.17`; name the version when you want a stable release.

```bash
# Newest Maven version of org.slf4j
curl -L -O https://repo.jenesis.build/artifact/org.slf4j/org.slf4j.jar

# A specific version, pinned
curl -L -O https://repo.jenesis.build/artifact/org.slf4j/2.0.9/org.slf4j.jar
```

With the segment present, the service looks for a row whose version matches **exactly** - there is no
range matching and no normalisation. A version the index has not seen yet is still answered: the service
assumes it exists on Maven Central under the module's newest coordinate and redirects there anyway,
flagging the response with an `X-Jenesis-BestEffort: true` header. That is what keeps a release from the
last few hours resolvable before the crawler has recorded it. If Maven Central has no such file, the
redirect target answers 404.

## `artifact` route: every file of a coordinate

On the `artifact` route the extension is opaque: whatever follows the module name becomes the suffix of
the Maven file name. Because the extension passes straight through, one route serves the jar, the POM,
its checksums and signatures, and Gradle module metadata:

```
# The jar
GET /artifact/org.slf4j/org.slf4j.jar
→ 302 …/org/slf4j/slf4j-api/2.0.10/slf4j-api-2.0.10.jar

# The POM of a specific version
GET /artifact/org.slf4j/2.0.9/org.slf4j.pom
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9.pom

# A checksum, or a signature - same pattern
GET /artifact/org.slf4j/2.0.9/org.slf4j.pom.sha256
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9.pom.sha256

# Gradle module metadata, if the publisher provides it
GET /artifact/org.slf4j/2.0.9/org.slf4j.module
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9.module
```

The file is always requested as `<module>.<extension>`, never as `<artifactId>-<version>.<extension>`,
and there is no `maven-metadata.xml`. The Jenesis build tool speaks exactly this shape, so for it the
`/artifact/` route is a complete repository. A stock Maven or Gradle resolver asks for Maven-shaped file
names and is not a client of this route.

## `module`, `sources`, and `documentation` routes

These three are keyed by the module-info version, serve named modules only, and accept only `.jar`. They
map to the main jar, the sources jar, and the javadoc jar of the same artifact:

```
GET /module/org.slf4j/2.0.9/org.slf4j.jar
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9.jar

GET /sources/org.slf4j/2.0.9/org.slf4j.jar
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9-sources.jar

GET /documentation/org.slf4j/2.0.9/org.slf4j.jar
→ 302 …/org/slf4j/slf4j-api/2.0.9/slf4j-api-2.0.9-javadoc.jar
```

A named release whose declared module-info version differs from its Maven version is left out of these
routes, because the service promises that the two agree (see the guarantee below). Such a release remains
reachable through `/artifact/` under its Maven version.

## Classifiers

A classifier is the part of the file name between the first hyphen and the next dot. It switches the
lookup to the classifier-scoped view of the module index and becomes a standard Maven classifier on the
redirect target:

```
GET /artifact/p6spy/p6spy-all.jar
→ 302 …/p6spy/p6spy/3.9.1/p6spy-3.9.1-all.jar
```

The same works on every route: `<module>-<classifier>.jar` under `/module/` resolves the classifier's jar
of a named module.

## The 302 response

A successful response is an empty-bodied HTTP `302` whose `Location` points at the Maven URL. It is
cached with `Cache-Control: public, max-age=<ttl>, stale-while-revalidate=86400`, where the TTL is an hour
on the public service.

The resolved coordinate is echoed back as response headers, so a client can record exactly what it
fetched without parsing the `Location`:

| Header | When | Value |
| --- | --- | --- |
| `X-Jenesis-GroupId` | always | Maven `groupId` of the resolved row. |
| `X-Jenesis-ArtifactId` | always | Maven `artifactId`. |
| `X-Jenesis-MavenVersion` | always | Maven coordinate version. |
| `X-Jenesis-ModuleVersion` | `/module/`, `/sources/`, `/documentation/` | The publisher-declared module-info version. Omitted on `/artifact/`, where the lookup key is already the Maven version. |
| `X-Jenesis-BestEffort` | a version the index has not recorded | `true` - the redirect was built from the module's newest coordinate rather than from a recorded row. |

### When a request fails

| Status | Meaning |
| --- | --- |
| `404` | Nothing could be served. The body says why when the module or version is the problem. |
| `405` | The request was not `GET` or `HEAD`. |
| `502` | The upstream index files are temporarily unreachable. |

A `404` has one of these causes:

- the path is not one of the four shapes, or the file name does not start with the module name;
- the file name has no extension, or a `.jar`-only route was asked for another extension;
- the module name is unknown to the index, or has no named release on a `/module/`-family route;
- the module has no resolved owner in this view.

## Stability guarantee

The service makes one promise you can build on. **A recorded `(module, moduleVersion)` always resolves to
the same Maven artifact, and that artifact's Maven version is the same number as the module version.**
Pin a module version in your build and every later rebuild resolves to the identical jar. Maven itself
does not enforce unique module versions; the index does.

The `/artifact/` lookup is stable for the same reason: Maven coordinates are immutable on Central. The
resolution of a name shifts only when the ownership of that name is re-decided - usually by an operator's
explicit policy, occasionally because an older publication of the name is discovered later.

<div class="note">
  A module resolves only if some artifact on Maven Central declared that module name. If you get a
  <code>404</code> for a name you expected, the artifact may ship neither a <code>module-info</code> nor
  an <code>Automatic-Module-Name</code>, or it may be an automatic module you asked for on
  <code>/module/</code> - try <code>/artifact/</code>. The <a href="/modules/reports/">reports</a> show
  what is and is not covered.
</div>

## Using it from the build tool

The Jenesis build tool points at `repo.jenesis.build` out of the box, and the layout decides which route
it uses. The default `modular_to_maven` layout translates each `requires` into a Maven coordinate through
`/artifact/`, so named and automatic modules alike resolve. The strict `modular` layout resolves purely by
module name through `/module/`, so every dependency must be a named module. That difference is the whole
reason a plain-jar library is reachable in one layout and not the other.

Three settings move a build to another deployment of the module index; the
[Dependencies](/tool/dependencies/) chapter of the build tool covers them in full:

| Setting | Environment variable | Purpose |
| --- | --- | --- |
| `-Djenesis.module.uri=<url>` | `JENESIS_REPOSITORY_URI` | The base URL of the module index (default `https://repo.jenesis.build/`). |
| `-Djenesis.module.token=<token>` | `JENESIS_REPOSITORY_TOKEN` | An `Authorization` header value sent on every request. |
| `-Djenesis.module.local=<dir>` | `JENESIS_REPOSITORY_LOCAL` | The local module repository consulted first (default `~/.jenesis`). |

From the command line, `curl -L` is all a manual lookup needs:

```bash
# Follow the redirect and save the jar
curl -L -O https://repo.jenesis.build/module/com.fasterxml.jackson.databind/com.fasterxml.jackson.databind.jar

# Inspect only - see the redirect target and the coordinate headers
curl -I https://repo.jenesis.build/module/com.fasterxml.jackson.databind/com.fasterxml.jackson.databind.jar
```

## Pointing at a mirror

The URL shapes *are* the contract, so any deployment that serves the same shapes is a drop-in replacement.
The reference service is a small HTTP function that reads four optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATA_BASE` | the index data on `raw.githubusercontent.com` | An HTTP(S) base URL the resolved-view files are fetched from. Point it at a fork or mirror to serve a different index. |
| `ARTIFACT_BASE` | `https://repo.maven.apache.org/maven2/` | The base URL the 302 redirects target. Point it at a Maven mirror or proxy. |
| `HOME_REDIRECT` | the project's GitHub page | Where a request for `/` redirects. |
| `REDIRECT_TTL` | `3600` (seconds) | The `max-age` on the 302, and the edge-cache TTL for the upstream reads. |

Any number of path segments *before* the route marker are ignored, so the same service works whether it
is mounted at `/`, `/mod/`, or `/jenesis/v1/`, with no configuration.

## <span id="reading-the-index-directly">Reading the index directly</span>

You do not have to go through the service at all. Each redirect comes from one row of a **resolved view**,
a plain tab-separated file you can read over `raw.githubusercontent.com` or any mirror - enough to build
a resolver of your own. Each module has a directory whose path mirrors its dot-separated name
(`com.fasterxml.jackson.core` → `com/fasterxml/jackson/core/`). It holds up to four files:

| File | Role |
| --- | --- |
| `versions.tsv` | The **audit log**: every `(groupId, artifactId, version)` that has ever declared this name, append-only in publication order, never pruned. |
| `artifacts.tsv` | The **resolved view** keyed by Maven version, read by `/artifact/`. |
| `modules.tsv` | The **resolved view** keyed by module-info version, read by `/module/`. Present only when the owner publishes named releases. |
| `owners.tsv` | An optional **ownership policy**: which publishing groupIds are `allowed` or `rejected` for this name. |

**`artifacts.tsv`** has four columns, sorted version-descending:

```
2.0.10  named      org.slf4j  slf4j-api
2.0.9   named      org.slf4j  slf4j-api
1.7.36  automatic  org.slf4j  slf4j-api
```

The columns are `version`, `type` (`named` or `automatic`), `groupId`, `artifactId`. Find the row whose
first column is your version and fetch `<artifactId>-<version>` from Maven Central.

**`modules.tsv`** has four columns, sorted module-version-descending, and lists named releases only:

```
2.0.10  org.slf4j  slf4j-api  2.0.10
2.0.9   org.slf4j  slf4j-api  2.0.9
```

The columns are `moduleVersion`, `groupId`, `artifactId`, `mavenVersion`. Match the first column, then
fetch the coordinate named by the last three. Classifier-scoped variants live alongside as
`artifacts-<classifier>.tsv` and `modules-<classifier>.tsv`.

<div class="warning">
  A module name is <strong>not</strong> a namespaced or authoritative identifier - it is just a string a
  jar carries, and unrelated artifacts can and do declare the same one. The resolved views already pick a
  single owner per name for you, using the audit log and the ownership policy; <a
  href="/modules/how-produced/">How the index is produced</a> explains how that owner is chosen, and the
  <a href="/modules/reports/">drift report</a> lists the names still in dispute. If you resolve directly,
  pin the <code>(groupId, artifactId)</code> you expect rather than trusting a name on its own.
</div>
