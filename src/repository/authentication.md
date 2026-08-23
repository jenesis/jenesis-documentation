---
order: 7
title: Authentication & access
description: How a deployment decides who may read and publish - the bootstrap key that gets you the first credential, issuing and revoking keys, running open on a trusted network, a public read-only mirror, and signing in to the console.
---

A fresh Jenesis Repository **enforces** authentication: every request is checked against a per-credential
key, and a request that carries none is refused. Before you expose a server to anyone else, you choose how
it identifies callers. There are three deployment shapes: a key-gated server, which starts from a bootstrap
key; an open server on a trusted network; and a public read-only mirror. The chapter then covers the keys
themselves - their grants, and how to issue and revoke them. Signing in to the web console is a separate
matter, covered at the end.

## Three ways to deploy

### Key-gated, starting from a bootstrap key

A real deployment keeps enforcement on and issues each client a key of its own. The first key is the one
problem: every route that can mint a key requires one already. `jenreg.bootstrap-key` solves that - a key you
choose, which the server provisions at boot with every right on every repository of its tenant, and which
you then use to issue the keys you actually want.

A key is a self-describing string, `jenk_<tenant>.<secret><checksum>`, and the bootstrap key has to be
well-formed because the server reads the tenant out of it. Generate one with a few lines of Python (the
checksum is the CRC32 of everything before it, base64url-encoded without padding):

```bash
python3 - <<'EOF'
import base64, os, zlib
body = "jenk_default." + base64.urlsafe_b64encode(os.urandom(24)).rstrip(b"=").decode()
crc = zlib.crc32(body.encode()) & 0xffffffff
print(body + base64.urlsafe_b64encode(crc.to_bytes(4, "big")).rstrip(b"=").decode())
EOF
```

Start the server with it, once:

```bash
JENREG_BOOTSTRAP_KEY=jenk_default.… JENREG_FILESYSTEM_ROOT=/var/lib/jenesis-repository \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

A malformed value refuses to boot rather than being ignored, and the server logs a `SECURITY` line for as
long as the setting is present: the bootstrap key never expires, is re-provisioned on every boot, and grants
everything. Use it to issue real credentials (below), then unset it and restart - its entry stays in the
store until you revoke it like any other key.

### Open, on a trusted network

For a laptop, a CI network, or any deployment that lives behind its own perimeter, you can skip keys
altogether:

```bash
JENREG_AUTH=false
```

Every request is then served anonymously: anyone who can reach the port can read, publish and delete. The
choice is never silent. The server logs a warning at boot and raises the `jenreg.auth.open` advisory, which
`GET /api/posture` reports and the console shows on its Security posture panel.

### A public read-only mirror

For a repository that anyone may read but nobody may change - an open-source project's artifacts, a
browsable archive - keep enforcement on, grant keyless callers read access, and remove writing altogether:

```bash
JENREG_AUTH=true                             # the default
JENREG_ANONYMOUS_RIGHTS=repository:read
JENREG_READ_ONLY=true
```

`jenreg.anonymous-rights` names exactly what a caller without a key may do. It is blank by default, so an
enforcing server stays closed until you say otherwise. The value is a comma-separated list in the grant
grammar below: `repository:read` on every repository, `<repository>=repository:read` for one named
repository, `<surface>:*` for every verb on a surface, or `*` for everything. Granting writes anonymously
is allowed and warned about at boot.

`jenreg.read-only` refuses **every** write with `403` - a publish, an import, a proxy fetch caching an
artifact - at the store itself, so no credential and no internal path gets around it. A common pattern pairs
one firewalled read-write instance that publishes into a shared bucket with public read-only instances that
serve from it.

## Keys, grants and roles

With enforcement on, a client identifies itself with a key. A `GET` or `HEAD` needs the `repository:read`
right on the requested path; any other method needs `repository:write`. A request without a key is answered
`401`; one whose key lacks the right is answered `403`. Where the route does not already name the
repository, `Jenesis-Repository-Name` does.

The key travels in whichever header the client can send:

| Header | Who sends it that way |
|---|---|
| `Jenesis-Repository-Key: jenk_…` | The server's own header - `curl`, scripts, the console panels, Maven's `<httpHeaders>`. It wins when present. |
| `Authorization: Bearer jenk_…` (or the bare key) | A Jenesis build, whose `jenesis.maven.token` / `jenesis.module.token` go out as the `Authorization` header; Gradle's `HttpHeaderCredentials`; any bearer-token client. |
| `Authorization: Basic …` with the key as the password | `docker login -u anyone -p jenk_…` - the user name is ignored. |

Only a well-formed key is ever read out of `Authorization`; anything else in that header is treated as no
key at all, never as a credential. A request for an artifact that presents no key is answered `401` with a
`WWW-Authenticate: Basic` challenge, which is what Maven (on a read) and a Docker client wait for before
sending the credential they hold; the `/api/` paths answer a bare `401`, so a browser is never shown a
sign-in dialog.

```bash
curl -H "Jenesis-Repository-Key: jenk_default.…" \
     -T app-1.0.jar http://repo.example.com/repository/maven/com/example/app/1.0/app-1.0.jar

java -Djenesis.maven.uri=https://repo.example.com/repository/maven/ \
     -Djenesis.maven.token=jenk_default.… build/jenesis/Project.java
```

The `jenk_` prefix and the trailing checksum let a secret scanner recognise a leaked key and let the server
reject a malformed one without a store lookup. The tenant travels in the key, so a request is attributed
without a directory read, and only the key's SHA-256 hash is ever stored - a lost key is re-issued, never
recovered.

A key's rights are a map from **scope** to **rights**. A scope is a repository name (`*` for every
repository), optionally narrowed to a path prefix as `<repository>:<prefix>`, which covers a request only
when its path lies at or under the prefix on a segment boundary. A right is a `<surface>:<verb>` token over
the surfaces `repository`, `cache` and `manage`, each with `read` and `write`; `<surface>:*` grants both
verbs and a bare `*` grants everything. Three built-in roles bundle them:

| Role | Grants |
|---|---|
| `read-only` | `cache:read`, `repository:read` |
| `deploy` | the above plus `cache:write`, `repository:write` |
| `admin` | `*` |

A key expires 90 days after it is created unless given another lifetime (the deployment can set a
different default and a ceiling - see the settings below), can be restricted to a source-address
allowlist, and is checked against its stored grants on every request, so a narrowed or revoked key stops
working at once.

<div class="note">
  Maven itself has no bearer-token setting, so a Maven client presents the server's own header: in
  <code>settings.xml</code>, the server's <code>&lt;configuration&gt;&lt;httpHeaders&gt;</code> block with
  a <code>Jenesis-Repository-Key</code> property.
</div>
## Issuing and revoking keys

Keys are administered through `/api/credentials`. Issuing a key is administration, not publishing, so the
routes require the `manage:read` right (to list) or `manage:write` (to change) at deployment scope - the
bootstrap key and any key with `*` carry them; a `deploy` key cannot issue more keys.

Mint a key, optionally with a label and a lifetime. The secret comes back **once**:

```bash
curl -H "Jenesis-Repository-Key: $BOOTSTRAP" -H 'Content-Type: application/json' \
     -d '{"label":"ci-publisher"}' http://localhost:8080/api/credentials
```

```json
{"id":"deead028…","key":"jenk_default.PLy9vc…","expires":"2026-11-19T16:31:23Z"}
```

A new key has **no rights** until you grant some. Grant a scope and the tokens it gets - `*` for every
repository, or one repository's name:

```bash
curl -H "Jenesis-Repository-Key: $BOOTSTRAP" -H 'Content-Type: application/json' \
     -d '{"scope":"*","tokens":["repository:read","repository:write"]}' \
     http://localhost:8080/api/credentials/deead028…/grants
```

The whole surface, where `<id>` is the 64-character hash the mint returned and the listing shows:

| Request | Effect |
|---|---|
| `GET /api/credentials` | The tenant's credentials - id, label, created, expires, allowed addresses, grants - never a secret. One page per request: at most `limit` (500, the default and the maximum) in id order from `after`; when more remain, the `X-Next-Cursor` response header carries the `after` value of the next page. |
| `POST /api/credentials` | Mint. Body: `label`, `expires` (`P30D` from now, or an instant; blank = the 90-day default), `nonExpiring: true`. Answers `201` with `id`, `key`, `expires`. |
| `POST /api/credentials/<id>/grants` | Set the rights at one scope. Body: `scope`, `tokens` (a list). |
| `DELETE /api/credentials/<id>/grants/<scope>` | Remove the rights at one scope. |
| `PUT /api/credentials/<id>/expiry` | Change the expiry. Body: `expires` as above; blank clears it. |
| `PUT /api/credentials/<id>/allowed-ips` | Restrict the key to source addresses. Body: `addresses`, comma-separated CIDRs or addresses; blank clears it. |
| `POST /api/credentials/<id>/rotate` | Mint a successor that inherits the grants and allowlist, and expire the old key after an overlap. Body: `overlap` (default seven days). Answers `201` like a mint. |
| `DELETE /api/credentials/<id>` | Revoke. The key stops working at once. |

The console's **Credentials** panel does the everyday part of this - list, issue with a label, revoke - with
a managing key pasted into the page; grants and rotation are API calls.

## What a client can find out

`GET /api/capabilities` answers a small JSON map a client or console reads to adapt itself: `auth` (whether
the wire is credential-gated), `readOnly`, and `anonymousRights` (the keyless grant, if any).
`GET /api/posture` lists the security advisories the current configuration raises, from `jenreg.auth.open`
to `jenreg.ratelimit.unset`, each with the setting that would clear it. Both are reads: on an enforcing
server they need a key with read rights, or an anonymous read grant, and the posture report is scoped to the
whole deployment rather than to one repository.

## Signing in to the console

The web console is a separate application with its own sign-in. People authenticate through an identity
provider, not with repository keys, and the console has two roles: every signed-in user is a **user** who
can browse, and a user listed as an admin can also act on what the console exposes.

Two providers are supported and either or both may be configured; with neither, sign-in is disabled and the
console shows a notice instead of failing:

```bash
# GitHub OAuth app
JENREG_UI_GITHUB_CLIENT_ID=…
JENREG_UI_GITHUB_CLIENT_SECRET=…

# One OpenID Connect issuer (Google, Keycloak, Okta, Entra ID, Auth0, …); endpoints are discovered
JENREG_UI_OIDC_ISSUER_URI=https://login.example.com/realms/main
JENREG_UI_OIDC_CLIENT_ID=…
JENREG_UI_OIDC_CLIENT_SECRET=…
JENREG_UI_OIDC_NAME="Company SSO"          # labels the sign-in button
```

Admins are named by provider-qualified id in `JENREG_UI_ADMINS`, comma-separated: `github/<id>` for a
GitHub user, `oidc/<sub>` for an OIDC subject. The list is empty by default, so an unconfigured console
grants admin to nobody. A `*` entry makes every signed-in user an admin, which raises the
`jenreg.console.wildcard` advisory.

The session cookie is sent only over HTTPS. For a local run over plain http, where the cookie has to survive
the OAuth redirect without TLS, set `JENREG_UI_SECURE_COOKIE=false`.

<div class="tip">
  For local work, start the console with <code>SPRING_PROFILES_ACTIVE=dev</code>. The profile replaces the
  provider sign-in with a form login and two built-in accounts, <code>admin</code>/<code>admin</code> and
  <code>viewer</code>/<code>viewer</code>, so both roles can be tried without an identity provider. It
  raises the <code>jenreg.profile.dev</code> advisory and is never for a reachable deployment.
</div>

## Settings

Server-side settings, read at startup from the environment, a `-D` system property or
`application.properties`:

| Key | Default | Effect |
|---|---|---|
| `jenreg.auth` | `true` | Enforce the key credential. `false` serves every request anonymously and raises `jenreg.auth.open`. |
| `jenreg.bootstrap-key` | *(blank)* | A well-formed key provisioned at boot with `*` on every repository of its tenant; logged as a `SECURITY` line while set. Unset it once real keys exist. |
| `jenreg.credential-default-lifetime` | *(blank)* | The lifetime of a key minted without an explicit expiry, as an ISO-8601 duration; blank is 90 days. |
| `jenreg.credential-max-lifetime` | *(blank)* | The longest any key may live; a longer request is pulled back to it. Blank leaves lifetimes uncapped. |
| `jenreg.anonymous-rights` | *(blank)* | Rights granted to a caller without a key, in the grant grammar; only meaningful with `jenreg.auth=true`. |
| `jenreg.read-only` | `false` | Refuse every write, external or internal, with `403`. Advertised at `GET /api/capabilities`. |
| `jenreg.tenant` / `jenreg.repository` | `default` | The names of the one artifact space this deployment serves; a key's tenant must match. |

Console settings, read by the console process:

| Key | Default | Effect |
|---|---|---|
| `jenreg.ui.admins` | *(blank)* | Comma-separated `github/<id>` / `oidc/<sub>` ids granted admin; `*` for everyone. |
| `jenreg.ui.github.client-id` / `.client-secret` | *(blank - disabled)* | GitHub OAuth app credentials. |
| `jenreg.ui.oidc.issuer-uri` / `.client-id` / `.client-secret` | *(blank - disabled)* | The OIDC issuer and client. |
| `jenreg.ui.oidc.name` | `Single sign-on` | The label on the OIDC sign-in button. |
| `JENREG_UI_SECURE_COOKIE` | `true` | Send the session cookie over HTTPS only. |
