---
order: 12
title: The console
description: The web console the server serves - reaching it, signing in, the overview and the admin screens, browsing artifacts, downloading a listing, reading the server's logs and consistency, and issuing keys.
---

Jenesis Repository ships a web console for browsing what the repository holds and for reading how the server
is doing. It runs inside the server: the same process serves `/console` beside `/repository/`, reads the
same store, and answers the console's own calls to `/api/logs`, `/api/consistency` and `/api/credentials`
from the same origin. This chapter shows how to reach it, sign in, and use each screen.

## Reaching it

Start the server as in [Getting started](/repository/getting-started/) and open `http://localhost:8080/`,
which redirects to `/console`. There is nothing else to start and no second port: the console listens where
the server listens (`PORT`, 8080 by default). `jenreg.console=false` takes it out of the process entirely -
its screens, its sign-in and everything that hangs off them - and leaves the repository's own endpoints
alone, which is the shape for a node that serves clients only.

<div class="note">
  The <strong>Logs</strong>, <strong>Consistency</strong> and <strong>Credentials</strong> cards call the
  server's <code>/api/logs</code>, <code>/api/consistency</code> and <code>/api/credentials</code>. They are
  the same origin, so nothing needs routing - but a console session is not a repository key, and each of
  those cards asks you for one (below).
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

For a local run, the `dev` Spring profile adds a form login at `/login/dev` with two built-in accounts,
`admin`/`admin` (an admin) and `viewer`/`viewer` (a user); the sign-in page lists it beside any provider you
configured. On plain `http`, also set `JENREG_UI_SECURE_COOKIE=false`, or the session cookie is never sent
back.

<div class="warning">
  The <code>dev</code> profile is for a laptop. Its built-in accounts are an authentication bypass anywhere
  else, so the server refuses to start under the profile on anything but the loopback address, and raises the
  <code>jenreg.profile.dev</code> advisory while the profile is active.
</div>

Console sign-in is separate from the keys that gate the server's artifact API: a console session grants no
rights on the wire, and the three cards that call the server's API ask you for a key.

## The overview and the admin screens

`/console` is the **Overview**: the installed cards on one page, under a header that carries **Sign out**, the
theme switch, a badge with the number of open security-posture advisories, and a read-only banner when the
deployment runs with `jenreg.read-only=true`. Four cards ship with the console:

| Card | What it shows |
|---|---|
| **Browse** | The repository's artifacts as a folder tree, with a link to the full browse page. |
| **Logs** | A tail of the server's recent log entries, with level and text filters and auto-follow. |
| **Consistency** | The per-node report of a multi-node deployment, or a single-node notice. |
| **Credentials** | The keys the server authorises with: list them, issue one with a label, revoke one. |

A card that fails to render says so in its own place and leaves the others untouched.

Three further screens are for admins, reached from the **Administration** menu in the header:

| Screen | Path | What it shows |
|---|---|---|
| **Installed providers** | `/catalog` | Every extension point the deployment carries, and under each the modules on the module path that fill it - formats, stores, importers, fetchers - with whether each is installed and switched on. |
| **Security posture** | `/posture` | The server's configuration advisories, severity first, each with its fix. |
| **Metrics** | `/observability` | Current values, health states and background-task status reported by installed modules, with a line of description each. |

## Browsing artifacts

`/browse` is a breadcrumbed file browser over the repository's published paths. It works the same for every
format because it reads the repository's own listing rather than knowing about Maven or OCI layouts:

- It shows the **request paths** artifacts are published under - `maven/org/apache/commons/…`,
  `oci/…`, `raw/…` - not the content-addressed storage underneath, so what you see is what a client requests.
- Each row is a **folder** or an **artifact**; artifacts show their stored size. A folder's children are
  listed only when you open it, one level at a time, so a large repository browses as quickly as a small one.
  A folder is cut off with a notice once 1 000 children are listed, or once 50 000 have been examined to
  fill them - the second cap is what bounds a folder whose children are mostly withheld.
- No artifact is ever opened to render a row, and the browse never reaches outside the published tree: a
  `path` that tries `..` is cleaned, and an artifact the server currently withholds is omitted, so the browse
  and a plain `GET` always agree.

## Downloading a listing

**Download asset listing** on the browse page streams the published artifacts as `assets.ndjson` - one JSON
object per line with `path`, `size` and `sha256`, read from the publication records without opening a blob.
One download holds at most 10 000 entries (`/assets?limit=` asks for fewer); when more remain, its last line
is `{"cursor":"…"}`, and `/assets?cursor=…` continues from there, so a large repository is exported in
slices. It is the console's counterpart of the server's `GET /api/assets`, which adds the format, coordinate
and version per entry; see [Migration & import](/repository/migration-import/).

## Reading the server's logs and consistency

The **Logs** card tails `GET /api/logs` and the **Consistency** card reads `GET /api/consistency`. Both
endpoints show deployment-wide state, so the server gates them to a key with a deployment-wide `*` grant; each
card has a field to paste one, and sends it as the `Jenesis-Repository-Key` header. On a server running with
authentication off, leave the field empty. Neither card fetches anything until you press **Refresh**, so
it opens empty rather than erroring; refreshing without a key against an enforcing server reports
`error: status 401`. [Observability](/repository/observability/) describes both endpoints and their fields.

## Issuing keys

The **Credentials** card is the console's view of `/api/credentials`. Paste a key that carries
`manage:read` and the card lists the tenant's credentials with their labels, expiry, use and grants;
issuing and revoking need `manage:write`, which does not confer the read. The bootstrap key holds `*`, so
it covers both. **Issue a key** mints one with the label you typed and shows the secret **once**: only
its hash is stored, so copy it before you leave the page. **Revoke** removes a key at once. A freshly issued
key has no rights until it is granted some, which - like rotation and address allowlists - is an API call;
[Authentication & access](/repository/authentication/) covers the whole surface.

## Theme and accessibility

The theme switch in the header offers **Auto**, **Light** and **Dark**; Auto follows the operating system,
and the choice is remembered per browser. Every console page starts with a skip-to-content link for
keyboard users, and every interactive element shows a visible focus ring.
