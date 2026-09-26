---
order: 11
title: Supply-chain features
description: Build-time supply-chain support - generating a CycloneDX SBOM, checking dependency licences against a policy, scanning for known vulnerabilities, and hardening the whole build.
---

A build is only as trustworthy as the code it pulls in. Jenesis has four build-time features for knowing and
governing that closure: a **software bill of materials** that records exactly what you shipped, a **licence
check** that gates the build on your policy, a **vulnerability scan** against the OSV advisory database, and
the **pinning** that guarantees the bytes you build are the bytes you vetted - extended by
[signature verification](/tool/securing-the-supply-chain/#provenance-who-produced-the-bytes), which checks who signed an artifact as
it is downloaded. None of them needs a plugin or a
build script - each turns on from a convention, over the same resolved dependency graph.

<div class="note">
  This is about hardening <em>your own</em> build. <a href="/repository/">Jenesis Repository</a> is a
  different product that works on the serving side, as artifacts are published and proxied. Here, everything
  runs inside your build, against the dependencies you resolve.
</div>

## Software bill of materials

Every build emits a **CycloneDX** SBOM by default - a machine-readable list of every resolved component with
its version, content hash, and declared licence. There is nothing to enable and no external tool: the `sbom`
step runs before the jar is sealed and writes the document in one move, from the dependency graph, checksums,
and licences the build already has.

```bash
java build/jenesis/Make.java
```

The SBOM is a supply-chain counterpart to the `dependencies` selector (see *[Dependencies](/tool/dependencies/)*):
where that *prints* the resolved graph, the SBOM *freezes* it into a publishable artifact. It lands in three
places, one per consumer:

- **Embedded in the jar**, at `META-INF/sbom/<artifact>.cdx.json`, so the bill of materials travels inside the
  artifact. The jar's manifest records `Sbom-Format: CycloneDX` and an `Sbom-Location` header pointing at it.
  An executable [launcher jar](/launcher/producing-a-launcher-jar/) carries a document of its own at the same
  place, which describes the project as an `application` and adds the launcher it shades as a dependency - once
  if the module already depends on the same version, beside it if on another. A [native image](/tool/packaging/)
  compiles its jars away, and their documents with them, so one of its own is staged beside the binary as
  `<image>.cdx.json`. It describes the project as an `application` and adds the GraalVM that compiled the binary
  as a `platform` it depends on, named after the vendor and version in that GraalVM's `release` file. That file
  names no licence, so the component carries none unless `jenesis.graalvm.license` names one.
- **As a report**, collected on `stage` into `target/stage/reports/output/sbom/<module>/` alongside the other
  build reports.
- **As a Maven attachment**, when a Maven repository is staged: `stage` drops
  `<artifact>-<version>-cyclonedx.json` next to the pom and jar, so `export` publishes it to Maven Central as
  the conventional CycloneDX attached artifact.

Each component carries its `pkg:maven/…` package URL, its `SHA-256` hash, and its licence, with a `dependsOn`
relationship back to the project. The document's `metadata.component` describes the project itself from the
POM - its description, licence, developers (as CycloneDX `authors`), organization (as its `supplier`),
homepage and source repository (as `website` and `vcs` references), and the `copyright`, `manufacturer` and
`publisher` that `project.properties` declares - filling in only what is declared. The tag and the revision a release
was built from, when given, are recorded as well, including a `vcs` reference that locates the sources at that
revision (see *[Publishing](/tool/publishing/#pointing-a-release-at-its-sources)*).

A dependency resolved through Maven takes its licence from its POM. One resolved as a Java module, under the
`modular` layout, has no POM and takes it from its jar instead: from the component its embedded CycloneDX SBOM
describes, so a jar built by Jenesis carries its licence to every build that uses it, or else from its OSGi
`Bundle-License` header, which many jars on Maven Central declare. The `dependencies` selector shows the same
licences.

<div class="tip">
  The SBOM is <strong>reproducible</strong>: its <code>serialNumber</code> is a UUID derived from the
  document's own content, and no creation <code>timestamp</code> is written (a timestamp cannot be made
  deterministic). A reproducible build reproduces the exact same SBOM, serial number included.
</div>

### Choosing the format, or turning it off

An optional `sbom.properties` in the configuration folder selects the format:

| `format=` | Result |
| --- | --- |
| `json` | CycloneDX JSON - the default, also used when the file or the key is absent |
| `xml` | CycloneDX XML |
| `none` | disables the SBOM |

Any other value fails the build. To suppress the SBOM without adding a file, pass the default-`true` boolean
override `-Djenesis.sbom.cyclonedx=false`. Like every configuration file, `sbom.properties` is profile-aware,
so a `release` profile can select the XML format while everyday builds keep JSON (see
*[Configuration](/tool/configuration/)*).

### Identifying the sources

With `swhid=true` in `sbom.properties`, the SBOM also identifies the sources the module was built from: its
component carries a `jenesis:source:swhid` property whose value is a [SWHID](https://docs.softwareheritage.org/devel/swh-model/persistent-identifiers.html), the
identifier Software Heritage defines for a directory. It is one hash over every source root of the module
together: the source folders and resource folders the project declares, but not what a generator writes during
the build.

The hash depends on nothing but the files' paths and bytes. It is the same whether the sources come from a Git
checkout, another version control system or a plain folder, and neither a file's timestamp nor its permissions
change it. It is computed like this:

1. Every regular file below a source root is taken with its path relative to that root, using `/` as the
   separator. Roots are merged into one tree; when two roots hold a file at the same path, their bytes must be
   equal, or the build fails. Empty folders contribute nothing.
2. A file's id is the SHA-1 of the ASCII header `blob <size>`, a zero byte, and the file's bytes.
3. A folder's id is the SHA-1 of the ASCII header `tree <length>`, a zero byte, and one entry per file or
   subfolder. An entry is the mode (`100644` for every file, `40000` for a folder), a space, the name in UTF-8,
   a zero byte, and the 20 bytes of the file's or subfolder's id. Entries are sorted by the bytes of their name,
   where a subfolder's name compares as if it ended in `/`.
4. The value is `swh:1:dir:` followed by the root folder's id in lowercase hexadecimal.

These are the rules Git uses for its tree objects. For a module with a single source root that holds only
files committed unchanged, none of them executable or a symbolic link, the value therefore equals
`swh:1:dir:` followed by what `git rev-parse <revision>:<path of the root>` prints.

The hash is off by default because it records the bytes as they were checked out: a file checked out with
Windows line endings gives a different value than the same file checked out with Unix line endings, where the
compiled classes would not differ. A `.gitattributes` that fixes line endings keeps the value the same on every
machine (see *[Building &amp; running](/tool/building-and-running/)*).

### The licence text in the jar

The SBOM names the project's licence; the text of the licence travels as a file. `jenesis.project.resources`
places files or folders of the project among the resources of every module, tests included, each at the path
after its colon, so one line in `jenesis.properties` puts a licence into every jar the build writes:

```properties
# jenesis.properties
jenesis.project.resources=LICENSE:META-INF/LICENSE,NOTICE:META-INF/NOTICE
```

Pairs are separated by commas, and a folder is placed as a folder, as in `licenses:META-INF/licenses`. Editing a
placed file builds the jars again. A path must exist and stay within the project, symbolic links included, and a
target must be a relative path without `..` that no other pair names. A module that brings a resource of its own
at the same path fails the build rather than losing one of the two.

{% demos 29 %}

## Licence compliance

The licence check gates the build on the licences of its resolved dependencies. It stays **off until a
`licensing.properties` file exists** in the configuration folder (`build.jenesis/` under the project root by
default). The file's presence enables the check; its contents configure it.

The check runs over the shipped (`main` compile/runtime) dependencies; in-build snapshots and build-tool
closures are excluded. Each dependency's declared licence is normalised to a canonical SPDX identifier and a
category. A dependency that declares no licence is read from its jar instead: its embedded CycloneDX SBOM
first, then the OSGi `Bundle-License` header, then a `META-INF/LICENSE` text file matched heuristically. The
verdicts are written to `reports/compliance/licenses.txt`, one line per dependency (`OK`, `DENIED`, `MISSING`,
`WARN`, or `UNKNOWN`):

```
mysql/mysql-connector-java/5.1.49 [DENIED] The GNU General Public License, Version 2
org.apache.commons/commons-lang3/3.14.0 [OK] Apache-2.0
```

The file's keys:

- **`allowed`** (comma-separated) fails any dependency whose licence is not on the list. Entries match the SPDX
  id, the category, or the raw name/URL: `Apache-2.0`, `Apache`, or `permissive` all match an Apache licence,
  while `strong-copyleft` matches the GPL family. A dependency with several licences passes if *any one* is
  allowed, because Maven lists licences disjunctively. A **`denied`** list of the same syntax rejects matches
  outright.
- **`unknown`** = `ignore` | `warn` | `fail` gates a missing licence, **default `fail`**: "no declared licence"
  is legally all-rights-reserved, so the strict default refuses it.
- **`override.<coordinate>`** curates a wrong or empty declaration, keyed by the dependency coordinate (the
  `maven/` prefix, with or without a version): `override.maven/org.example/widget=Apache-2.0`.

```properties
# build.jenesis/licensing.properties
allowed=permissive,weak-copyleft
unknown=fail
```

The category keywords are `permissive`, `weak-copyleft`, `strong-copyleft`, `network-copyleft`, and
`public-domain`. An unrecognised key fails the build. To skip the check, remove the file.

### Teaching it about a licence (optional)

Normalisation draws on comprehensive built-in tables, so most projects need no configuration. To teach the
check about a licence it does not know - a differently worded name, or an identifier that lacks a category -
drop an optional `spdx.properties` in the configuration folder. It uses one prefixed key space:

```properties
# build.jenesis/spdx.properties
alias/A\ Company\ License=Apache-2.0
category/Apache-2.0=permissive
```

`alias/<declared name>` normalises a licence name as written in a POM to its canonical SPDX id; a space in the
name is written `\ `, since an unescaped one would end the key. A licence that
names no identifier is matched by its URL as well, written without its scheme, a leading `www.`, a `.txt`,
`.html`, `.htm`, `.php` or `.md` extension, or a trailing slash: `alias/example.com/licenses/widget=Apache-2.0` covers
`https://www.example.com/licenses/widget.txt`. `category/<SPDX id>` classifies an identifier. Each entry
**appends** to the built-in tables rather than replacing them, and the same classification feeds both the
licence check and the SBOM's licence identifiers. The project's own licences are identified the same way, so
its SBOM names them by SPDX id as well. It is distinct from `licensing.properties`, which is the
enforcement policy, not the classification.

{% demos 30 %}

## Vulnerability scanning

The vulnerability check gates the build on the **known vulnerabilities** of its resolved dependencies. Like the
licence check, it stays off until its file, **`vulnerability.properties`**, exists in the configuration
folder. With the file present, the build queries the public [OSV.dev](https://osv.dev) advisory database -
no account, no API key - for the resolved coordinates, writes every match to
`reports/compliance/vulnerabilities.txt`, and applies your threshold:

```properties
# build.jenesis/vulnerability.properties
severity=critical
```

The keys:

- **`severity`** = `low` | `medium` | `high` | `critical` is the threshold; a matched advisory at or above it
  is flagged.
- **`warn`** = `true` | `false` (default `false`): a flagged advisory **warns** (reported, build passes) when
  `true`, or **fails** the build when `false`.
- **`osv.endpoint`** (optional) overrides the OSV endpoint (default `https://api.osv.dev`).

<div class="warning">
  The OSV fetch is the one supply-chain feature that reaches the network at build time, and it runs
  <em>only</em> when <code>vulnerability.properties</code> is present. Remove the file to keep the build fully
  offline.
</div>

An unrecognised key fails the build. The licence and vulnerability checks are two halves of the same
`compliance` step, each turned on by the presence of its own file, so you can run either, both, or neither.
To keep both files in place but skip both checks for a single build, pass the default-`true` override
`-Djenesis.compliance=false`.

{% demos 31 %}

## Hardening the whole build

The SBOM, licence, and vulnerability checks all describe the closure they resolve. **Pinning** is what makes
that closure trustworthy in the first place: Jenesis pins every dependency by version *and* by the `SHA-256`
checksum of the jar, and verifies each download against its pin. A coordinate whose bytes do not match its
recorded checksum is rejected outright, which is exactly what happens if a repository serves a swapped or
compromised artifact. *[Pinning & bills of materials](/tool/pinning/)* covers how to record pins, how
`-Djenesis.dependency.pin=strict` requires them, and how to refresh a frozen closure deliberately. A hardened
supply chain layers the checks above on top of a fully pinned, strict build.
*[Securing the supply chain](/tool/securing-the-supply-chain/)* sets out which attack each of these
answers and where each one stops.

### Why strict pinning matters

Only the resolved **artifacts** carry a checksum; the `pom.xml` files read during resolution are *not* pinned,
because some servers apply harmless whitespace or line-ending changes that would produce spurious mismatches.
That leaves one gap: a tampered POM could try to introduce a dependency the jar checksums do not cover.
**Strict pinning closes it.** Any dependency a POM newly adds arrives as a coordinate with no pin, which
strict mode rejects, so a manipulated POM cannot quietly pull in an unverified artifact. This is why strict
pinning is recommended for builds in unsecured environments and for releases.

{% demos 26 %}
