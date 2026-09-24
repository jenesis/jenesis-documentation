---
order: 5
title: Connecting your build tools
description: The URL and the credential each package client uses against Jenesis Repository - Maven and Gradle, npm, PyPI, container images, Go and the rest - and how to switch a format off.
---

Every client talks to the repository in its own protocol, at its own URL under `/repository/`, and presents
the same kind of credential: a key issued under **Access → Credentials**. This chapter lists the URL and the
credential form for each client. The examples use `repo.example.com` and a key in `$KEY`.

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

| Ecosystem | Point the client at | Credential |
| --- | --- | --- |
| Maven | `https://repo.example.com/repository/maven/` | `settings.xml` server entry, key as password |
| Gradle (Maven layout) | `https://repo.example.com/repository/maven/` | `credentials { password = key }` |
| Gradle (Ivy layout) | `https://repo.example.com/repository/ivy/` | `credentials { password = key }` |
| npm | `https://repo.example.com/repository/npm/` | `.npmrc` `_authToken` |
| PyPI | upload to `https://repo.example.com/repository/pypi/`, install from `…/pypi/simple/` | twine `-u __token__ -p $KEY`; pip `https://__token__:$KEY@…` |
| Containers | `repo.example.com` (the registry answers at `/v2/`) | `docker login`, key as password |
| Go | `GOPROXY=https://jenesis:$KEY@repo.example.com/repository/go` | in the URL |
| Cargo | `sparse+https://repo.example.com/repository/cargo/<name>/` | `credentials.toml` token |
| NuGet | `https://repo.example.com/repository/nuget/v3/index.json` | push with the key as API key; restore with `nuget.config` credentials |
| RubyGems | `https://repo.example.com/repository/rubygems` | `GEM_HOST_API_KEY` to push; key as password in the source URL to install |
| Helm | `https://repo.example.com/repository/helm/<name>` | `helm repo add … --username jenesis --password $KEY` |
| Composer | `https://repo.example.com/repository/composer/<name>` | `auth.json` `http-basic` |
| Conan | `https://repo.example.com/repository/conan/<name>` | `conan remote login`, key as password |
| Conda | `https://repo.example.com/repository/conda/<channel>` | key as password in the channel URL |
| Debian | `https://repo.example.com/repository/debian` | apt `auth.conf` |
| RPM | `https://repo.example.com/repository/rpm/<name>` | `.repo` file `password=` |
| Alpine | `https://repo.example.com/repository/apk/<name>` | in the repository URL |
| CocoaPods | `https://repo.example.com/repository/cocoapods/<name>` | `~/.netrc` |
| Swift | `https://repo.example.com/repository/swift/<name>` | `registries.json` plus `~/.netrc` |
| Terraform / OpenTofu | `https://repo.example.com/repository/terraform/<name>` | CLI configuration `credentials` block |
| Hugging Face | `HF_ENDPOINT=https://repo.example.com/repository/huggingface/hf` | `HF_TOKEN=$KEY` |
| Homebrew bottles | `HOMEBREW_BOTTLE_DOMAIN=https://repo.example.com/repository/homebrew/<name>` | bearer token |
| winget | `https://repo.example.com/repository/winget/<name>` as a `Microsoft.Rest` source | bearer token |
| Raw files | `https://repo.example.com/repository/raw/<path>` | any of the three forms |
| Jenesis modules | `-Djenesis.module.uri=https://repo.example.com/repository/module/` | `-Djenesis.module.token=$KEY` |

Where a URL carries `<name>`, the format keeps separate spaces inside the one repository - a Cargo registry, a
Helm chart repository, a Conda channel, a Swift registry - and the name is yours to choose. Publishing under a new name creates it.

## Maven and Gradle

Maven publishes with `mvn deploy` and resolves through `<repositories>` or a `<mirror>`, all at the one URL;
[Getting started](/repository/getting-started/) shows the `settings.xml` entry. Gradle uses the same URL with a
`maven { url … ; credentials { username = "jenesis"; password = key } }` block, or the Ivy layout at
`/repository/ivy/` when a build publishes Ivy descriptors.

The repository stores what you upload, POMs and `maven-metadata.xml` included, and serves them back verbatim.

**Every modular jar is a published module too.** When a jar published through Maven carries a
`module-info` or an `Automatic-Module-Name`, the repository also serves it by module name at
`/repository/module/`, so a Jenesis build that `requires` that module resolves it from the same server with no
second upload.

## Containers

The registry answers at the host root, because the container protocol fixes it at `/v2/`:

```bash
docker login repo.example.com -u jenesis -p "$KEY"
docker tag my-app repo.example.com/my-app:1.0
docker push repo.example.com/my-app:1.0
docker pull repo.example.com/my-app:1.0
```

Image layers are stored by their digest, so a layer shared by many images - or identical to a file stored by
another format - is kept once.

## Raw files

For artifacts that belong to no ecosystem - installers, archives, datasets - the raw format is a plain file
store:

```bash
curl -H "Jenesis-Repository-Key: $KEY" -T installer.msi \
  https://repo.example.com/repository/raw/tools/installer-1.2.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/raw/tools/installer-1.2.msi -o installer.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/raw/tools/     # lists the folder
```

## Switching a format off

Every format is on until you switch it off. `JENREG_<FORMAT>=false` keeps one from starting, exactly as if it
were not installed: its URLs answer `404` and nothing is imported for it. The names are the ones in the URLs -
`maven`, `npm`, `pypi`, `oci`, `go`, `cargo`, `nuget`, `rubygems`, `helm`, and so on - and **Settings → Modules**
switches them from the console, taking effect on the next restart.

<div class="note">
  Some clients refuse to send a credential over plain HTTP - the Go command among them - so a deployment that
  serves real clients runs behind TLS. <a href="/repository/deploying/">Running in production</a> covers it.
</div>
