---
order: 7
title: Authentication & access
description: How a deployment decides who may read and publish - running open on a trusted network, serving a public read-only mirror, the key credential the server enforces by default, and signing in to the console.
---

A fresh Jenesis Repository **enforces** authentication: every request is checked against a per-credential
key, and a request that carries none is refused. Before you expose a server to anyone else, you choose how
it identifies callers. There are three deployment shapes, and this chapter takes them in the order you are
likely to meet them: an open server on a trusted network, a public read-only mirror, and a key-gated server.
Signing in to the web console is a separate matter, covered at the end.

## Three ways to deploy

### Open, on a trusted network

For a laptop, a CI network, or any deployment that lives behind its own perimeter, switch enforcement off:

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

### Key-gated access

With enforcement on, a client identifies itself with a key in the `Jenesis-Repository-Key` header. A `GET`
or `HEAD` needs the `repository:read` right on the requested path; any other method needs
`repository:write`. Where the route does not already name the repository, `Jenesis-Repository-Name` does.

```bash
curl -H "Jenesis-Repository-Key: jenk_default.…" \
     -T app-1.0.jar http://repo.example.com/repository/maven/com/example/app/1.0/app-1.0.jar
```

A key is a self-describing string:

```
jenk_<tenant>.<secret><checksum>
```

The `jenk_` prefix and the trailing checksum let a secret scanner recognise a leaked key and let the server
reject a malformed one without a store lookup. The owner travels in the key, so a request is attributed
without a directory read, and only the key's SHA-256 hash is ever stored.

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

A key expires 90 days after it is created unless given a shorter lifetime, can be restricted to a
source-address allowlist, and is checked against its stored grants on every request, so a narrowed or
revoked key stops working at once.

<div class="warning">
  The server ships no command or screen that creates a key. Key-gated access applies to keys that are
  already present in the store's <code>auth/</code> objects; a new deployment that needs credentials for
  its clients runs open on a trusted network or as a read-only mirror, as above.
</div>

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
