---
order: 11
title: The console
description: The web console - a separate application over the same store - how to start it, sign in, browse artifacts, download a listing, and read the server's logs, consistency and security posture.
---

Jenesis Repository ships a web console for browsing what the repository holds and for reading how the server
is doing. It is a separate application from the server, not a page the server serves: it reads the same
store the server writes to, and it calls the server's HTTP endpoints for logs and the consistency check.
This chapter shows how to run it, sign in, and use each panel.

## Starting it

The console listens on port 8081 (`PORT`). Point it at the same store as the server - the same
`JENREG_STORE` backend and the same `JENREG_FILESYSTEM_ROOT` or cloud settings - and it shows what the server
serves. From a clone, run it as a second process beside the server with the console's entry point:

```bash
SPRING_PROFILES_ACTIVE=dev JENREG_UI_SECURE_COOKIE=false \
JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle \
       -Djenesis.execute.mainClass=build.jenesis.repository.bundle.Console \
       build/jenesis/Execute.java
```

The locally built image runs the console the same way, with the entry point and port passed as environment
variables:

```bash
docker run -e MAINCLASS=build.jenesis.repository.bundle.Console -e PORT=8081 -p 8081:8081 \
  -v jenesis-data:/data jenesis-repository
```

Then open `http://localhost:8081/`, which redirects to `/console`. [Getting started](/repository/getting-started/)
walks through the server side of the same setup.

<div class="note">
  The <strong>Logs</strong> and <strong>Consistency</strong> panels call the server's <code>/api/logs</code> and
  <code>/api/consistency</code> at the console's own origin. For them to work, serve the console and the server
  behind one host name, with a reverse proxy routing <code>/api/</code> to the server. Every other panel reads
  the store directly and works without it.
</div>

## Signing in

Every page except sign-in requires a session. Sign-in is OAuth2: a GitHub OAuth app, a single OpenID Connect
provider (Google, Keycloak, Okta, Entra ID, Auth0, …), or both, each configured with a few `jenreg.ui.*`
settings listed in [Authentication & access](/repository/authentication/). The sign-in page shows one button
per configured provider; with none configured it shows a notice instead of failing.

Every signed-in person is a **user** and may read everything the console shows. Only an **admin** may perform
a mutating action, and nobody is an admin until their provider-qualified id - `github/<id>` or `oidc/<subject>`
- is listed in `jenreg.ui.admins`. Listing `*` makes every signed-in user an admin, which the server reports
as the `jenreg.console.wildcard` advisory.

For a local run, the `dev` Spring profile replaces OAuth2 with a form login and two built-in accounts:
`admin`/`admin` (an admin) and `viewer`/`viewer` (a user). On plain `http`, also set
`JENREG_UI_SECURE_COOKIE=false`, or the session cookie is never sent back.

<div class="warning">
  The <code>dev</code> profile is for a laptop. Its built-in accounts are an authentication bypass anywhere
  else, and the server raises the <code>jenreg.profile.dev</code> advisory while the profile is active.
</div>

Console sign-in is separate from the keys that gate the server's artifact API: a console session grants no
rights on the wire, and the two panels that read the server's API ask you for a key.

## The console page

`/console` shows the installed panels in one page, with a header that carries **Sign out**, the theme switch,
and a read-only banner when the deployment runs with `jenreg.read-only=true`. Six panels ship with the
console:

| Panel | What it shows |
|---|---|
| **Browse** | The repository's artifacts as a folder tree, with a link to the full browse page. |
| **SPI catalog** | Every module on the deployment's module path that provides a capability - formats, stores, importers, fetchers - so you can read a deployment's abilities off one list. |
| **Metrics overview** | Current values, health states and background-task status reported by installed modules. It is empty until a module that reports them is installed. |
| **Logs** | A tail of the server's recent log entries, with level and text filters and auto-follow. |
| **Consistency** | The per-node report of a multi-node deployment, or a single-node notice. |
| **Security posture** | The server's configuration advisories, severity first, each with its fix. |

## Browsing artifacts

`/browse` is a breadcrumbed file browser over the repository's published paths. It works the same for every
format because it reads the repository's own listing rather than knowing about Maven or OCI layouts:

- It shows the **request paths** artifacts are published under - `maven/org/apache/commons/…`,
  `oci/…`, `raw/…` - not the content-addressed storage underneath, so what you see is what a client requests.
- Each row is a **folder** or an **artifact**; artifacts show their stored size. A folder's children are
  listed only when you open it, one level at a time, so a large repository browses as quickly as a small one.
  A folder with more than 1 000 children is cut off with a notice.
- No artifact is ever opened to render a row, and the browse never reaches outside the published tree: a
  `path` that tries `..` is cleaned, and an artifact the server currently withholds is omitted, so the browse
  and a plain `GET` always agree.

## Downloading a listing

**Download asset listing** on the browse page streams every published artifact as `assets.ndjson` - one JSON
object per line with `path`, `size` and `sha256`, read from the publication records without opening a blob.
It is the console's counterpart of the server's `GET /api/assets`, which adds the format, coordinate and
version per entry; see [Migration & import](/repository/migration-import/).

## Reading the server's logs and consistency

The **Logs** panel tails `GET /api/logs` and the **Consistency** panel reads `GET /api/consistency`. Both
endpoints show deployment-wide state, so the server gates them to a key with a deployment-wide `*` grant; each
panel has a field to paste one, and sends it as the `Jenesis-Repository-Key` header. On a server running with
authentication off, leave the field empty. Before a key is entered, or against an empty log ring, a panel
shows an empty state rather than an error. [Observability](/repository/observability/) describes both
endpoints and their fields.

## Theme and accessibility

The theme switch in the header offers **Auto**, **Light** and **Dark**; Auto follows the operating system,
and the choice is remembered per browser. Every page starts with a skip-to-content link for keyboard users,
and every interactive element shows a visible focus ring.
