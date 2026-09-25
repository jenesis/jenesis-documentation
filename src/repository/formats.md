---
order: 5
title: Connecting your build tools
description: The URL and the credential each package client uses against Jenesis Repository - Maven and Gradle, npm, PyPI, container images, Go and the rest - and how to switch a format off.
---

Every client talks to a repository of its own type, in its own protocol, and presents the same kind of
credential: a key issued under **Access → Credentials**. This chapter lists the type, the URL and the credential
form for each client. The examples use `repo.example.com`, the `default` tenant, a repository named `<repo>`
created with the type in the table, and a key in `$KEY`.

A repository's URL is `/repository/<tenant>/<repo>/`, and a repository of one format leaves that format's name
out of the paths after it. Maven and the Jenesis module layout are the two that keep theirs - `maven/`, and
`module/` beside `artifact/` - which is what lets the `java` type hold both in one repository. Container images
are addressed under `/v2/` instead, with the tenant and the repository as the first two parts of the image name.
A repository is created before a client uses it; [Repositories](/repository/repositories/) shows how.

## How a client presents its key

A key travels in whichever form a client can send, and the server accepts all three:

| Form | Used by |
| --- | --- |
| `Authorization: Basic` with the key as the **password** | Maven, Gradle, pip, Docker, Helm, NuGet restore, apt, dnf and most others - the user name is not checked, so any value will do. |
| `Authorization: Bearer <key>` | npm, Cargo, Hugging Face, a Jenesis build, and any client with a token setting. |
| `Jenesis-Repository-Key: <key>` | `curl` and scripts. |

A request without a key is answered `401` with a challenge, which is what Maven and Docker wait for before they
send the credentials they hold. A key that lacks the right is answered `403`.

## The clients

Each client below is listed with the repository type it needs, the address to point it at, and where its key goes.

### Java and the JVM

**Maven** · type `maven` or `java`\
URL: `https://repo.example.com/repository/default/<repo>/maven/`\
Key: a `settings.xml` server entry, the key as password

**Gradle, Maven layout** · type `maven` or `java`\
URL: `https://repo.example.com/repository/default/<repo>/maven/`\
Key: `credentials { password = key }`

**Gradle, Ivy layout** · type `ivy`\
URL: `https://repo.example.com/repository/default/<repo>/`\
Key: `credentials { password = key }`

**Jenesis modules** · type `jenesis` or `java`\
URL: `-Djenesis.module.uri=https://repo.example.com/repository/default/<repo>/`\
Key: `-Djenesis.module.token=$KEY`

### Language package managers

**npm** · type `npm`\
URL: `https://repo.example.com/repository/default/<repo>/`\
Key: `_authToken` in `.npmrc`

**PyPI** · type `pypi`\
Upload: `https://repo.example.com/repository/default/<repo>/`\
Install: `https://repo.example.com/repository/default/<repo>/simple/`\
Key: twine `-u __token__ -p $KEY`; pip `https://__token__:$KEY@…`

**Go** · type `go`\
URL: `GOPROXY=https://jenesis:$KEY@repo.example.com/repository/default/<repo>`\
Key: in the URL

**Cargo** · type `cargo`\
URL: `sparse+https://repo.example.com/repository/default/<repo>/<name>/`\
Key: a token in `credentials.toml`

**NuGet** · type `nuget`\
URL: `https://repo.example.com/repository/default/<repo>/v3/index.json`\
Key: the key as API key to push; `nuget.config` credentials to restore

**RubyGems** · type `rubygems`\
URL: `https://repo.example.com/repository/default/<repo>`\
Key: `GEM_HOST_API_KEY` to push; the key as password in the source URL to install

**Composer** · type `composer`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `http-basic` in `auth.json`

**Swift** · type `swift`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `registries.json` plus `~/.netrc`

**CocoaPods** · type `cocoapods`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `~/.netrc`

### Native code, data and models

**Conan** · type `conan`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `conan remote login`, the key as password

**Conda** · type `conda`\
URL: `https://repo.example.com/repository/default/<repo>/<channel>`\
Key: the key as password in the channel URL

**Hugging Face** · type `huggingface`\
URL: `HF_ENDPOINT=https://repo.example.com/repository/default/<repo>/hf`\
Key: `HF_TOKEN=$KEY`

### Operating-system packages

**Debian** · type `debian`\
URL: `https://repo.example.com/repository/default/<repo>`\
Key: apt `auth.conf`

**RPM** · type `rpm`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `password=` in the `.repo` file

**Alpine** · type `apk`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: in the repository URL

**Homebrew bottles** · type `homebrew`\
URL: `HOMEBREW_BOTTLE_DOMAIN=https://repo.example.com/repository/default/<repo>/<name>`\
Key: a bearer token

**winget** · type `winget`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`, as a `Microsoft.Rest` source\
Key: a bearer token

### Containers and infrastructure

**Containers** · type `oci`\
Image: `repo.example.com/default/<repo>/<image>` - the registry answers at `/v2/`\
Key: `docker login`, the key as password

**Helm** · type `helm`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: `helm repo add … --username jenesis --password $KEY`

**Terraform and OpenTofu** · type `terraform`\
URL: `https://repo.example.com/repository/default/<repo>/<name>`\
Key: a `credentials` block in the CLI configuration

### Anything else

**Raw files** · type `raw`\
URL: `https://repo.example.com/repository/default/<repo>/<path>`\
Key: any of the three forms

Where a URL carries `<name>`, the format keeps separate spaces inside the one repository - a Cargo registry, a
Helm chart repository, a Conda channel, a Swift registry - and the name is yours to choose. Publishing under a new
name creates that space; the repository itself has to exist first. The Terraform discovery document at
`/.well-known/terraform.json` names one registry path for the whole host, `terraform.prefix`, which is
`/repository/default/terraform/registry` - a `terraform` repository named `terraform` - unless you set it.

## Maven and Gradle

Maven publishes with `mvn deploy` and resolves through `<repositories>` or a `<mirror>`, all at the one URL;
[Getting started](/repository/getting-started/) shows the `settings.xml` entry. Gradle uses the same URL with a
`maven { url … ; credentials { username = "jenesis"; password = key } }` block, or an `ivy` repository's URL when
a build publishes Ivy descriptors.

The repository stores what you upload, POMs and `maven-metadata.xml` included, and serves them back verbatim.

**In a `java` repository, every modular jar is a published module too.** When a jar published through Maven
carries a `module-info` or an `Automatic-Module-Name`, a `java` repository also serves it by module name under
`module/` - `jenesis.module.uri` is the repository's own URL, `/repository/default/<repo>/` - so a Jenesis build
that `requires` that module resolves it from the same repository with no second upload. A `maven` repository
serves the Maven layout alone; creating it again with the type `java` makes it a `java` repository, with every
URL it answered still answering.

## Containers

The registry answers at the host root, because the container protocol fixes it at `/v2/`. An image's name begins
with the tenant and the `oci` repository it lives in, so an image `my-app` in a repository named `images` is
`default/images/my-app`:

```bash
docker login repo.example.com -u jenesis -p "$KEY"
docker tag my-app repo.example.com/default/images/my-app:1.0
docker push repo.example.com/default/images/my-app:1.0
docker pull repo.example.com/default/images/my-app:1.0
```

The registry's catalog, `GET /v2/_catalog`, lists every image in the tenant's `oci` repositories by the name a
client pulls it by - `default/images/my-app` - and pages with a `Link` header.

Image layers are stored by their digest, so a layer shared by many images - or identical to a file stored by
another format - is kept once.

## Raw files

For artifacts that belong to no ecosystem - installers, archives, datasets - a `raw` repository is a plain file
store. One named `files` holds paths directly under its URL:

```bash
curl -H "Jenesis-Repository-Key: $KEY" -T installer.msi \
  https://repo.example.com/repository/default/files/tools/installer-1.2.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/default/files/tools/installer-1.2.msi -o installer.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/default/files/tools/     # lists the folder
```

## Switching a format off

Every format is on until you switch it off. `JENREG_<FORMAT>=false` keeps one from starting, exactly as if it
were not installed: no repository can be created with its type, a repository that holds it answers `404`, and
nothing is imported for it. The names are the types in the table above - `maven`, `npm`, `pypi`, `oci`, `go`,
`cargo`, `nuget`, `rubygems`, `helm`, and so on - and **Settings → Modules** switches them from the console,
taking effect on the next restart. A combined type such as `java` is offered only while every format it holds is
on.

<div class="note">
  Some clients refuse to send a credential over plain HTTP - the Go command among them - so a deployment that
  serves real clients runs behind TLS. <a href="/repository/deploying/">Running in production</a> covers it.
</div>
