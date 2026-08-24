---
order: 10
title: Supply-chain features
description: Build-time supply-chain support - generating a CycloneDX SBOM, checking dependency licences against a policy, scanning for known vulnerabilities, and hardening the whole build.
---

A build is only as trustworthy as the code it pulls in. Jenesis has four build-time features for knowing and
governing that closure: a **software bill of materials** that records exactly what you shipped, a **licence
check** that gates the build on your policy, a **vulnerability scan** against the OSV advisory database, and
the **pinning** that guarantees the bytes you build are the bytes you vetted. None of them needs a plugin or a
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
java build/jenesis/Project.java
```

The SBOM is a supply-chain counterpart to the `dependencies` selector (see *[Dependencies](/tool/dependencies/)*):
where that *prints* the resolved graph, the SBOM *freezes* it into a publishable artifact. It lands in three
places, one per consumer:

- **Embedded in the jar**, at `META-INF/sbom/<artifact>.cdx.json`, so the bill of materials travels inside the
  artifact. The jar's manifest records `Sbom-Format: CycloneDX` and an `Sbom-Location` header pointing at it.
- **As a report**, collected on `stage` into `target/stage/reports/output/sbom/<module>/` alongside the other
  build reports.
- **As a Maven attachment**, when a Maven repository is staged: `stage` drops
  `<artifact>-<version>-cyclonedx.json` next to the pom and jar, so `export` publishes it to Maven Central as
  the conventional CycloneDX attached artifact.

Each component carries its `pkg:maven/…` package URL, its `SHA-256` hash, and its licence, with a `dependsOn`
relationship back to the project. The document's `metadata.component` describes the project itself from the
POM - its description, licence, developers (as CycloneDX `authors`), and homepage and source repository (as
`website` and `vcs` references) - filling in only what the POM declares.

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
alias/A Company License=Apache-2.0
category/Apache-2.0=permissive
```

`alias/<declared name>` normalises a licence name as written in a POM to its canonical SPDX id;
`category/<SPDX id>` classifies an identifier. Each entry **appends** to the built-in tables rather than
replacing them, and the same classification feeds both the licence check and the SBOM's licence identifiers.
It is distinct from `licensing.properties`, which is the enforcement policy, not the classification.

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

## Hardening the whole build

The SBOM, licence, and vulnerability checks all describe the closure they resolve. **Pinning** is what makes
that closure trustworthy in the first place: Jenesis pins every dependency by version *and* by the `SHA-256`
checksum of the jar, and verifies each download against its pin. A coordinate whose bytes do not match its
recorded checksum is rejected outright, which is exactly what happens if a repository serves a swapped or
compromised artifact. *[Pinning & bills of materials](/tool/pinning/)* covers how to record pins, how
`-Djenesis.dependency.pin=strict` requires them, and how to refresh a frozen closure deliberately. A hardened
supply chain layers the checks above on top of a fully pinned, strict build.

### Why strict pinning matters

Only the resolved **artifacts** carry a checksum; the `pom.xml` files read during resolution are *not* pinned,
because some servers apply harmless whitespace or line-ending changes that would produce spurious mismatches.
That leaves one gap: a tampered POM could try to introduce a dependency the jar checksums do not cover.
**Strict pinning closes it.** Any dependency a POM newly adds arrives as a coordinate with no pin, which
strict mode rejects, so a manipulated POM cannot quietly pull in an unverified artifact. This is why strict
pinning is recommended for builds in unsecured environments and for releases.

<div class="tip">
  Four runnable projects cover this chapter:
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-12-sbom">demo-12</a> emits an SBOM,
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-13-compliance">demo-13</a> gates a build on a
  permissive-only licence policy,
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-14-vulnerabilities">demo-14</a> catches
  Log4Shell in a pinned <code>log4j-core</code>, and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-42-supply-chain-security">demo-42</a> proves
  the pinning guarantees by getting them wrong on purpose. See <a href="/tool/demos/">Demos</a>.
</div>
