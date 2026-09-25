---
order: 2
title: Getting started
description: Run Jenesis Repository from its Docker image, sign in to the console, create repositories, issue a key for your build tools, and publish and resolve your first artifacts with Maven and npm.
---

This chapter takes you from nothing to a running repository in a few minutes. You start the server from its
Docker image, sign in to the web console, create a repository for Maven and one for npm, issue a key for your
build tools, and publish and resolve an artifact with each. Everything later in this section builds on what is
here.

## Run the image

You need Docker, and nothing else. The server keeps everything it holds - artifacts, indexes, settings, keys -
in one folder, so give that folder a volume of its own and choose a key you will sign in with the first time:

```bash
ADMIN_KEY=$(openssl rand -hex 20)
echo "$ADMIN_KEY"       # keep this: it is how you sign in the first time

docker run -d --name jenesis -p 8080:8080 \
  -v jenesis-data:/data \
  -e JENREG_FILESYSTEM_ROOT=/data \
  -e JENREG_KEY_LOGIN=true \
  -e JENREG_UI_ADMIN_KEY="$ADMIN_KEY" \
  jenesisbuild/jenesis-repository
```

Three settings, each with one job:

| Setting | What it does |
| --- | --- |
| `JENREG_FILESYSTEM_ROOT` | Where the repository lives inside the container. It is required: without it the server refuses to start and names the setting, rather than inventing a folder that disappears with the container. |
| `JENREG_KEY_LOGIN` | Offers "Sign in with a key" on the console's sign-in page. |
| `JENREG_UI_ADMIN_KEY` | The key that signs you in as the deployment's administrator. |

The server listens on port 8080 and answers there for everything: the console, the repository's clients and the
API. It is ready when its health endpoint says so:

```bash
curl -s http://localhost:8080/actuator/health        # {"groups":[…],"status":"UP"}
```

<div class="warning">
  The administrator key grants everything, and the server says so in its log for as long as it is set. It is
  there to get you in; once you have signed people in through your identity provider, remove it and restart. The
  <a href="/repository/access/">Access</a> chapter shows how.
</div>

## Sign in

Open `http://localhost:8080` in a browser; the console lives under `/ui/`, and the address redirects there. The
sign-in page offers **Sign in with a key**; choose it and paste the key you kept.

The first sign-in with that key lands on **Setup**, a short guide through the decisions a new deployment
should make - which advisory feeds to consult, what the gate does with a vulnerable or malicious package,
retention. Every step is optional and every answer can be changed later. **Skip for now** takes you into the
console, and the guide stays reachable as **Settings → Setup**.

The console is laid out in two levels. Across the top are its sections - **Repositories**, **Build cache**,
**Access**, **Operations** and **Settings** - and down the left side are the pages of the section you are in.
[Finding your way around](/repository/console/) walks through them.

## Create the repositories

A repository holds one type of artifact, and it is created before anything is published into it - a publish
into a repository that does not exist is refused with `404`. Create two:

1. Open **Repositories → All repositories**.
2. Under **New repository**, enter the name `releases`, choose the type **maven**, and press **Create
   repository**.
3. Do the same with the name `npm` and the type **npm**.

Every URL names the tenant and then the repository: a new deployment serves the tenant `default`, so these two
answer at `/repository/default/releases/` and `/repository/default/npm/`. A script creates a repository with a
`PUT` of that URL naming the type - [Repositories](/repository/repositories/) shows how - and
[Connecting your build tools](/repository/formats/) lists the other types.

## Issue a key for your build tools

Build tools do not sign in; they present a key. Issue one in the console:

1. Open **Access → Credentials**.
2. Under **New credential**, give it a label such as `laptop` and press **Generate credential**.
3. The credential's page opens with the key shown **once** - copy it now. Only a hash of it is stored, so a key
   that is lost is re-issued, never recovered.
4. Under **Project grants**, enter `*` as the project, choose the role **deploy**, and press **Grant**.

A new key holds no rights until you grant some. `*` with **deploy** lets it read and publish everywhere; the
[Access](/repository/access/) chapter covers narrower grants, expiry and rotation.

The rest of this chapter uses the key as `$KEY`:

```bash
KEY=jenk_default.…
```

## Publish and resolve with Maven

A Maven repository keeps Maven's own `maven/` segment in its URLs, so `releases` answers Maven at
`/repository/default/releases/maven/`. Put the key in `~/.m2/settings.xml` as the password of a server entry - the
user name is not checked:

```xml
<settings>
  <servers>
    <server>
      <id>jenesis</id>
      <username>jenesis</username>
      <password>jenk_default.…</password>
    </server>
  </servers>
</settings>
```

Publish a jar, then resolve it back:

```bash
mvn deploy:deploy-file -Dfile=app.jar \
  -DgroupId=com.example -DartifactId=app -Dversion=1.0 -Dpackaging=jar \
  -DrepositoryId=jenesis -Durl=http://localhost:8080/repository/default/releases/maven/

mvn dependency:get -Dartifact=com.example:app:1.0 \
  -DremoteRepositories=jenesis::default::http://localhost:8080/repository/default/releases/maven/
```

In a project, the same URL goes into `<distributionManagement>` to publish and into `<repositories>` to
resolve, each with the `jenesis` id so Maven finds the credentials.

## Publish and resolve with npm

The `npm` repository is the registry at `/repository/default/npm/`. Point npm at it and give it the key as a
token:

```bash
npm config set registry http://localhost:8080/repository/default/npm/
npm config set //localhost:8080/repository/default/npm/:_authToken "$KEY"

npm publish                  # from a package's folder
npm install my-package       # from anywhere else
```

Every other client follows the same pattern - a repository of its type, its URL under
`/repository/default/`, and the key as a password or a token.
[Connecting your build tools](/repository/formats/) lists them all.

## See it in the console

Back in the console, **Repositories** lists `releases` and `npm`. Open `releases`: the overview shows its most
recent releases, and the pages on the left take you into it - **Browse & search** walks the stored files, and
**Quarantine**, **Vulnerabilities** and their neighbours show what the gate decided about each artifact on its way
in.

## Stopping, upgrading and backing up

The container holds nothing the volume does not, so it can be replaced at will:

```bash
docker rm -f jenesis
docker pull jenesisbuild/jenesis-repository
docker run -d --name jenesis -p 8080:8080 -v jenesis-data:/data …     # the same settings as before
```

Backing up the volume backs up the repository, and copying it moves the repository. The image is also published
with a version tag beside `latest`, and pinning one keeps an upgrade a deliberate act.

<div class="tip">
  A laptop trial ends here. To run it for a team - on object storage, behind TLS, with your identity provider -
  read <a href="/repository/deploying/">Running in production</a> next.
</div>
