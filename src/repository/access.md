---
order: 10
title: Access
description: Who may use the repository - signing people in with a key, OpenID Connect, GitHub or LDAP; members, groups and roles; keys for build tools and their grants, expiry and rotation; keyless CI; and running open or as a public mirror.
---

Two kinds of caller use a repository. **People** sign in to the console, through an identity provider or with a
key, and act according to their role. **Build tools** never sign in: each request carries a key, and the key's
grants decide what it may read and publish. The **Access** section of the console looks after both - **Members**
for people and **Credentials** for keys.

## Signing people in

The sign-in page offers one button per mechanism the deployment has configured. Any combination may be switched
on:

| Mechanism | Switched on by |
| --- | --- |
| **A key** | on by default; `JENREG_KEY_LOGIN=false` switches it off |
| **OpenID Connect** - Keycloak, Okta, Entra ID, Google, Auth0 and any other issuer | `JENREG_UI_OIDC_ISSUER_URI`, `JENREG_UI_OIDC_CLIENT_ID`, `JENREG_UI_OIDC_CLIENT_SECRET`, and `JENREG_UI_OIDC_NAME` to label the button |
| **GitHub** | `JENREG_UI_GITHUB_CLIENT_ID` and `JENREG_UI_GITHUB_CLIENT_SECRET`, from a GitHub OAuth app |
| **LDAP or Active Directory** | `JENREG_UI_LDAP_URL`, with the settings below |

**Key sign-in** is the way into a new deployment. A start that finds nobody able to sign in prints a one-time key
in its log, as [Getting started](/repository/getting-started/) shows: it signs in as the deployment's
administrator for an hour, or until an administrator exists. A deployment provisioned from configuration can name
its own key instead, `JENREG_UI_ADMIN_KEY`, which is re-provisioned on every start for as long as it is set; the
server then prints no key. Either is meant to get you started, not to stay - once people sign in through your
identity provider, remove `JENREG_UI_ADMIN_KEY`, set `JENREG_KEY_LOGIN=false` and restart.

**LDAP** binds as the person signing in, either directly from a pattern or by searching for them first:

```bash
JENREG_UI_LDAP_URL=ldaps://ldap.example.com
JENREG_UI_LDAP_USER_DN_PATTERN="uid={0},ou=people,dc=example,dc=com"
# or, to search: JENREG_UI_LDAP_USER_SEARCH_BASE, _USER_SEARCH_FILTER (default "(uid={0})"), _BIND_DN, _BIND_PASSWORD
JENREG_UI_LDAP_GROUP_SEARCH_BASE="ou=groups,dc=example,dc=com"
JENREG_UI_LDAP_ADMIN_GROUP=repository-admins
```

A person's directory groups become their groups here, and members of the administrator group administer the
deployment. A plain `ldap://` URL is refused unless `JENREG_UI_LDAP_START_TLS=true` upgrades it, or
`JENREG_UI_LDAP_ALLOW_PLAINTEXT=true` says the connection is private.

<div class="note">
  Signing in and holding access are separate. Anyone your identity provider signs in reaches the console, but
  someone who holds no role sees a page saying so, showing the identifier an administrator needs to grant them one
  - such as <code>oidc/8f3c1a…</code> or <code>ldap/ada</code>.
</div>

## Administrators

The deployment's administrators hold every right in every part of it. `JENREG_UI_ADMINS` names them by
provider-qualified identifier, comma-separated: `github/<id>`, `oidc/<subject>`, `ldap/<user>`. The setting
**seeds** them on every start rather than mirroring them - removing an identifier from it does not take that
person's rights away, which is done in the console like any other change. A `*` entry is refused at startup:
administration belongs to people you can name.

## Members

**Access → Members** lists the people who hold a role in the deployment and gives others one. Enter the person's
provider-qualified identifier, optionally a login name to show beside it, choose **viewer**, **editor** or
**admin**, and press **Add / update user**. **Remove** takes the role away.

**Groups** grant rights to many people at once. A group is created by granting it something: give it a name,
a scope - a repository name, or `*` for all of them - and rights such as `repository:read,repository:write`, and
press **Grant to the group**. **Add to the group** puts a person in it. People signed in through LDAP arrive
with their directory groups already.

## Credentials

**Access → Credentials** is where keys for build tools are issued and looked after. A key looks like
`jenk_releases.…`: a recognisable prefix, the deployment's tenant, a secret and a checksum.

**New credential** issues one: a label, an optional expiry, and **Generate credential**. The key is shown
**once**, on the credential's page, and only a hash of it is kept. That page then offers:

| Section | What it does |
| --- | --- |
| **Project grants** | Grants the key a role on a repository - or on a build-cache project - by name, or `*` for all. An optional path prefix narrows it to part of the repository, such as `maven/com/example`. |
| **Key expiry** | Changes when the key stops working, as a duration from now (`P30D`) or a date. |
| **Rotate** | Issues a successor with the same grants and keeps the old key working for an overlap (`P7D` by default), so a pipeline can switch over without a gap. |
| **Source-IP allowlist** | Restricts the key to the addresses and ranges listed. |
| **Delete** | Revokes the key at once. |

Three roles are built in, and the **Roles** section adds your own as a name and a list of rights:

| Role | Rights |
| --- | --- |
| **read-only** | `repository:read`, `cache:read` |
| **deploy** | the above, and `repository:write`, `cache:write` |
| **admin** | everything |

The repository rights publish and resolve; they administer nothing. Everything else the API does - settings,
keys, groups, tenants, retention runs, walks - takes `manage:read` or `manage:write` over `*`, and the parts that
concern the whole deployment rather than one tenant (its settings, upstreams, logs and tenants) also a key of the
operator tenant: the default tenant, unless `JENREG_OPERATOR_TENANT` names another. So a **deploy** key in a CI
job can publish into every repository and still cannot change how the deployment is run.

A key issued without an expiry lives for 90 days. **Credential-lifetime policy** changes that default and can cap
how long any key may live.

A revoked or narrowed key stops working at once on the server that made the change, and on the other servers of a
multi-node deployment within the credential cache's lifetime - fifteen minutes by default (`auth.cache-ttl`).

## Keyless CI

A CI platform that issues its jobs an identity token - GitHub Actions, GitLab and most others - can exchange it
for a short-lived key instead of storing one. **OIDC trust (keyless CI)** on the Credentials page names which
tokens to accept:

| Field | Example |
| --- | --- |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience (optional) | `jenesis` |
| Subject glob (optional) | `repo:acme/app:*` - only this repository's workflows |
| Project and rights | `libraries`, `repository:read,repository:write` |
| Lifetime | `PT15M` |

The job posts its token to `/api/token` and receives a key valid for that lifetime, with its expiry:

```bash
KEY=$(curl -s -X POST -H "Authorization: Bearer $ID_TOKEN" https://repo.example.com/api/token | jq -r .key)
```

A token no trust matches is answered `401`.

## Open deployments

Two shapes skip keys, each on purpose:

- **Open, on a trusted network.** `JENREG_AUTH=false` serves every request without a key - anyone who can reach
  the port can read and publish. The server says so in its log and in **Operations → Security posture** for as
  long as it runs that way.
- **A public, read-only mirror.** Keep keys on, let callers without one read, and refuse every write:

  ```bash
  JENREG_ANONYMOUS_RIGHTS=repository:read
  JENREG_READ_ONLY=true
  ```

  `JENREG_READ_ONLY` refuses every write at the store itself - a publish, an import, a proxy fetch - so nothing
  gets around it. A common arrangement pairs one private read-write server with public read-only ones over the
  same bucket.
