---
order: 5
title: Formats
description: The four layouts the server speaks - Maven, the Jenesis module layout, OCI/Docker and raw files - their URLs, what each accepts and serves, and the settings that switch them.
---

A **format** is what lets a particular client talk to the repository: Maven and Gradle speak the Maven
layout, a Jenesis build resolves module names through the module layout, `docker` speaks the OCI registry
protocol, and `curl` can store plain files. Jenesis Repository ships four formats. Each is a discovered
module on the server's module path, so a deployment speaks exactly the formats it carries, and every one of
them stores its artifacts in the same content-addressed store.

| Format | Id | Served at | Clients |
|---|---|---|---|
| Maven layout | `maven` | `/repository/maven/` | Maven, Gradle, a Jenesis `pom.xml` build |
| Module layout | `jenesis` | `/repository/module/` and `/repository/artifact/` | A Jenesis modular build, `curl` |
| OCI registry | `oci` | `/v2/` | `docker`, `podman`, any OCI client |
| Raw files | `raw` | `/repository/raw/` | `curl`, scripts, anything that can `PUT` |

## The Maven layout

`/repository/maven/` is a drop-in Maven repository URL for publishing and resolving. A `PUT` stores the
uploaded file content-addressed and links its path; a `GET` serves it back. Point a `<distributionManagement>` entry
at the URL and `mvn deploy` publishes to it; a `<repository>` entry with the same URL resolves from it:

```xml
<distributionManagement>
  <repository>
    <id>jenesis</id>
    <url>http://localhost:8080/repository/maven/</url>
  </repository>
</distributionManagement>
```

The server stores what you upload and nothing more: it does not generate a POM for a jar, so publish the POM
alongside the jar as a normal Maven deploy does. A published `maven-metadata.xml` is stored and served back
**verbatim**. If you would rather have the server derive the version list from the artifacts it holds, opt
in with `jenreg.maven-metadata-compute=true`: the document is then kept as a stored listing that every
upload under the coordinate updates, and a read serves it as it is.

With an upstream configured (see *[Proxying](/repository/proxying/)*), the same URL also serves everything
from Maven Central, so one `<mirror>` entry covers your own artifacts and the public ones.

### Every modular jar is a published module too

When a jar published to the Maven layout carries a `module-info` or an `Automatic-Module-Name`, the server
reads the module name from the stored bytes and **cross-publishes** the jar into the module layout. A Jenesis
build that declares `requires <that module>` then resolves it from the same server with no second upload.
The bridge runs one way: a module published directly to the module layout stays there.

## The module layout

The module layout resolves artifacts **by Java module name**, under the `/module/` and `/artifact/` shapes
the [Jenesis Module Index](/modules/) also serves:

```
GET /repository/module/<name>/<version>/<name>.jar     a specific version
GET /repository/module/<name>/<name>.jar               the latest version
```

A Jenesis build reaches it through `jenesis.module.uri`, exactly as it reaches the public index - so a
private server and the public index are interchangeable from the build's point of view. The `<version>`
segment is the Maven version the jar was published under, not one read from its `module-info`.

A `PUT` under `/repository/module/` or `/repository/artifact/` stores a file at that path; most modules
arrive through the Maven cross-publish above instead, which links the two `/module/` shapes shown.

## The OCI registry

The OCI format implements the Distribution API at `/v2/`, at the host root because the Docker protocol pins
it there. `docker push` and `docker pull` talk to the server directly:

```bash
docker tag my-app repo.example.com/my-app:1.0
docker push repo.example.com/my-app:1.0
docker pull repo.example.com/my-app:1.0
```

It supports monolithic and chunked blob uploads, manifests addressed by tag or by digest (the media type is
kept beside the manifest so a pull returns it verbatim), `HEAD` existence checks, `tags/list`, and
`_catalog`. Both listings are stored documents a tag push keeps current, paged in memory for a client's
`n` and `last`, so listing a registry of many images costs one read. An OCI blob is addressed by its
`sha256:` digest, which is the very key the store uses, so image layers dedupe against everything else the
repository holds. With an upstream registry configured, the same
endpoint is a pull-through mirror (see *[Proxying](/repository/proxying/)*).

## Raw files

The raw format is a plain file store under `/repository/raw/` for artifacts that belong to no ecosystem -
installers, archives, datasets, signed binaries:

```bash
curl -T installer.msi http://localhost:8080/repository/raw/tools/installer-1.2.msi
curl    http://localhost:8080/repository/raw/tools/installer-1.2.msi -o installer.msi
curl    http://localhost:8080/repository/raw/tools/          # lists the directory
curl -X DELETE http://localhost:8080/repository/raw/tools/installer-1.2.msi
```

`PUT` stores a file content-addressed, `GET` serves it, `GET` on a trailing slash lists the directory, and
`DELETE` removes the path. The bytes share the store with every other format, so a raw upload that matches a
jar or an image layer costs no extra space.

## Settings

Every format is on until you switch it off. `jenreg.<id>=false` (as an environment variable,
`JENREG_MAVEN=false`, `JENREG_JENESIS=false`, `JENREG_OCI=false`, `JENREG_RAW=false`) keeps a format from
activating, exactly as if its module were absent: its paths answer `404` and its importer is skipped.

| Key | Default | Effect |
|---|---|---|
| `jenreg.maven` / `jenreg.jenesis` / `jenreg.oci` / `jenreg.raw` | `true` | Switch a format off with `false`. |
| `jenreg.maven-metadata-compute` | `false` | Derive `maven-metadata.xml` from stored versions instead of serving the uploaded file. |
| `jenreg.proxy.maven` / `jenreg.proxy.oci` / `jenreg.proxy.raw` | *(unset)* | The upstream a format pulls through from; the module layout does not proxy. See *[Proxying](/repository/proxying/)*. |

A server with every format switched off is still a valid server - it answers `404` to every artifact
request until a format is on to claim it.
