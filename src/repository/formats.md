---
order: 5
title: Connecting your build tools
description: The URL and the credential each package client uses against Jenesis Repository - Maven and Gradle, npm, PyPI, container images, Go and the rest - and how to switch a format off.
---

Every client talks to a repository of its own type, in its own protocol, and presents the same kind of
credential: a key issued under **Access → Credentials**. This chapter lists the type, the URL and the credential
form for each client. The examples use `repo.example.com`, the `releases` tenant, a repository named `<repo>`
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

Each client needs a repository of its type and is pointed at an address inside it. The addresses start with the
repository's own URL, written `$REPO` below:

```bash
REPO=https://repo.example.com/repository/releases/<repo>
```

### Java and the JVM

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| Maven | `maven`, `java` | `$REPO/maven/` | a `settings.xml` server entry, the key as password |
| Gradle, Maven layout | `maven`, `java` | `$REPO/maven/` | `credentials { password = key }` |
| Gradle, Ivy layout | `ivy` | `$REPO/` | `credentials { password = key }` |
| Jenesis modules | `jenesis`, `java` | `jenesis.module.uri=$REPO/` | `jenesis.module.token=$KEY` |

### Language package managers

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| npm | `npm` | `$REPO/` | `_authToken` in `.npmrc` |
| PyPI | `pypi` | upload to `$REPO/`, install from `$REPO/simple/` | twine `-u __token__ -p $KEY`; pip `https://__token__:$KEY@…` |
| Go | `go` | `GOPROXY=$REPO` | in the URL: `https://jenesis:$KEY@repo.example.com/…` |
| Cargo | `cargo` | `sparse+$REPO/<name>/` | a token in `credentials.toml` |
| NuGet | `nuget` | `$REPO/v3/index.json` | the key as API key to push; `nuget.config` credentials to restore |
| RubyGems | `rubygems` | `$REPO` | `GEM_HOST_API_KEY` to push; the key as password in the source URL to install |
| Composer | `composer` | `$REPO/<name>` | `http-basic` in `auth.json` |
| Swift | `swift` | `$REPO/<name>` | `registries.json` plus `~/.netrc` |
| CocoaPods | `cocoapods` | `$REPO/<name>` | `~/.netrc` |

### Native code, data and models

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| Conan | `conan` | `$REPO/<name>` | `conan remote login`, the key as password |
| Conda | `conda` | `$REPO/<channel>` | the key as password in the channel URL |
| Hugging Face | `huggingface` | `HF_ENDPOINT=$REPO/hf` | `HF_TOKEN=$KEY` |

### Operating-system packages

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| Debian | `debian` | `$REPO` | apt `auth.conf` |
| RPM | `rpm` | `$REPO/<name>` | `password=` in the `.repo` file |
| Alpine | `apk` | `$REPO/<name>` | in the repository URL |
| Homebrew bottles | `homebrew` | `HOMEBREW_BOTTLE_DOMAIN=$REPO/<name>` | a bearer token |
| winget | `winget` | `$REPO/<name>` as a `Microsoft.Rest` source | a bearer token |

### Containers and infrastructure

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| Containers | `oci` | `repo.example.com/releases/<repo>/<image>` - the registry answers at `/v2/` | `docker login`, the key as password |
| Helm | `helm` | `$REPO/<name>` | `helm repo add … --username jenesis --password $KEY` |
| Terraform, OpenTofu | `terraform` | `$REPO/<name>` | a `credentials` block in the CLI configuration |

### Anything else

| Client | Type | Point it at | Key |
| --- | --- | --- | --- |
| Raw files | `raw` | `$REPO/<path>` | any of the three forms |

Where a URL carries `<name>`, the format keeps separate spaces inside the one repository - a Cargo registry, a
Helm chart repository, a Conda channel, a Swift registry - and the name is yours to choose. Publishing under a new
name creates that space; the repository itself has to exist first. The Terraform discovery document at
`/.well-known/terraform.json` names one registry path for the whole host, `terraform.prefix`, which is
`/repository/releases/terraform/registry` - a `terraform` repository named `terraform` - unless you set it.

## Maven, Gradle and Jenesis

A repository holds one format, so each tool needs a repository of the type it speaks. Maven, Gradle and a Jenesis
build all read the Maven layout from a `maven` or `java` repository at `/repository/releases/<repo>/maven/`; a Gradle
build that publishes Ivy descriptors needs an `ivy` repository, and a Jenesis build that resolves modules by name a
`jenesis` or `java` repository. What a client uploads - POMs and `maven-metadata.xml` included - is stored and
served back verbatim. A key goes wherever the tool keeps credentials outside the project, so it is never
committed with the build.

### Maven

The key is the password of a server entry in `~/.m2/settings.xml`; the user name is not checked:

```xml
<settings>
  <servers>
    <server>
      <id>jenesis</id>
      <username>jenesis</username>
      <password>jenk_releases.…</password>
    </server>
  </servers>
</settings>
```

The project names the repository by that id, to publish with `mvn deploy` and to resolve from:

```xml
<project>
  <distributionManagement>
    <repository>
      <id>jenesis</id>
      <url>https://repo.example.com/repository/releases/<repo>/maven/</url>
    </repository>
  </distributionManagement>

  <repositories>
    <repository>
      <id>jenesis</id>
      <url>https://repo.example.com/repository/releases/<repo>/maven/</url>
    </repository>
  </repositories>
</project>
```

To send every download through the repository instead - when it [proxies](/repository/proxying/) Maven Central
or groups a proxy with your own releases - name it as a mirror in `settings.xml` rather than in each project:

```xml
<mirrors>
  <mirror>
    <id>jenesis</id>
    <mirrorOf>*</mirrorOf>
    <url>https://repo.example.com/repository/releases/<repo>/maven/</url>
  </mirror>
</mirrors>
```

### Gradle

A repository named `jenesis` with `PasswordCredentials` reads its user name and key from `jenesisUsername` and
`jenesisPassword`, which belong in `~/.gradle/gradle.properties`:

```properties
jenesisUsername=jenesis
jenesisPassword=jenk_releases.…
```

The build resolves from the repository and publishes to it with `./gradlew publish`:

```kotlin
// build.gradle.kts
plugins {
    `java-library`
    `maven-publish`
}

repositories {
    maven {
        name = "jenesis"
        url = uri("https://repo.example.com/repository/releases/<repo>/maven/")
        credentials(PasswordCredentials::class)
    }
}

publishing {
    publications {
        create<MavenPublication>("library") {
            from(components["java"])
        }
    }
    repositories {
        maven {
            name = "jenesis"
            url = uri("https://repo.example.com/repository/releases/<repo>/maven/")
            credentials(PasswordCredentials::class)
        }
    }
}
```

A build that publishes Ivy descriptors uses an `ivy` repository instead, at the repository's own URL. Gradle's
default Ivy layout is the one the repository accepts, so nothing more needs saying:

```kotlin
plugins {
    `java-library`
    `ivy-publish`
}

repositories {
    ivy {
        name = "jenesis"
        url = uri("https://repo.example.com/repository/releases/<ivy-repo>/")
        credentials(PasswordCredentials::class)
    }
}

publishing {
    publications {
        create<IvyPublication>("library") {
            from(components["java"])
        }
    }
    repositories {
        ivy {
            name = "jenesis"
            url = uri("https://repo.example.com/repository/releases/<ivy-repo>/")
            credentials(PasswordCredentials::class)
        }
    }
}
```

### Jenesis

A [Jenesis](/tool/) build resolves Maven coordinates from `jenesis.maven.uri` and modules by name from
`jenesis.module.uri`, and both can be the one `java` repository: its Maven layout under `maven/`, and every
modular jar published into it served by module name as well. A token is never read from a project's own
`jenesis.properties` - it would be committed with the build - so the address and the key both go in your
user-global `~/.jenesis/jenesis.properties`:

```properties
jenesis.maven.uri=https://repo.example.com/repository/releases/<repo>/maven/
jenesis.maven.token=jenk_releases.…
jenesis.module.uri=https://repo.example.com/repository/releases/<repo>/
jenesis.module.token=jenk_releases.…
```

or in the environment, which suits a CI job:

```bash
export MAVEN_REPOSITORY_URI=https://repo.example.com/repository/releases/<repo>/maven/
export MAVEN_REPOSITORY_TOKEN="$KEY"
export JENESIS_REPOSITORY_URI=https://repo.example.com/repository/releases/<repo>/
export JENESIS_REPOSITORY_TOKEN="$KEY"
java build/jenesis/Make.java
```

Either way a build that names only the repository resolves from it alone. Append `,@` to an address to fall back
to the public defaults for whatever the repository does not hold - `…/<repo>/maven/,@` - though a repository that
proxies them already answers for them.

**In a `java` repository, every modular jar is a published module too.** When a jar published through Maven
carries a `module-info` or an `Automatic-Module-Name`, a `java` repository also serves it by module name under
`module/`, and under `artifact/` beside the POM published with it. So a Jenesis build that `requires` that module
resolves it from the same repository with no second upload: `artifact/` gives its POM, and the Maven coordinate
that POM names gives its jar. A jar published under a classifier is served beside the module's own as
`<module>-<classifier>.jar`. A `maven` repository serves the Maven layout alone; creating it again with the type `java` makes it a
`java` repository, with every URL it answered still answering.

A Jenesis build puts its own modules into a `jenesis` repository with `release`, once `jenesis.release.uri`
names the repository's address and `jenesis.release.token` a key that may publish to it: one put of each
module's jar under its version, below `module/`. The repository moves the module's version-less
`<module>/<module>.jar` to the version released last, so that path is not an upload target, and neither is anything
else. A `java` repository refuses that put - Maven drives its
publication - so modules a build releases go to a `jenesis` repository, and modules published through Maven reach
module consumers from a `java` one. Both settings have environment variables of their own,
`JENESIS_RELEASE_URI` and `JENESIS_RELEASE_TOKEN`, so a CI job keeps the key it releases with apart from the key
it resolves with. *[Publishing](/tool/publishing/)* describes the release.

## Containers

The registry answers at the host root, because the container protocol fixes it at `/v2/`. An image's name begins
with the tenant and the `oci` repository it lives in, so an image `my-app` in a repository named `images` is
`default/images/my-app`:

```bash
docker login repo.example.com -u jenesis -p "$KEY"
docker tag my-app repo.example.com/releases/images/my-app:1.0
docker push repo.example.com/releases/images/my-app:1.0
docker pull repo.example.com/releases/images/my-app:1.0
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
  https://repo.example.com/repository/releases/files/tools/installer-1.2.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/releases/files/tools/installer-1.2.msi -o installer.msi
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/repository/releases/files/tools/     # lists the folder
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
