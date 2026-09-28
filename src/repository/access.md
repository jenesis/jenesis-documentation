---
order: 10
title: Access
description: Who may use the repository - signing people in with a key, OpenID Connect, GitHub or LDAP; login keys; members, groups and roles; keys for build tools and their grants, expiry and rotation; keyless CI; and running open or as a public mirror.
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
| **A key** | on by default; `JENREPO_KEY_LOGIN=false` switches it off |
| **OpenID Connect** - Keycloak, Okta, Entra ID, Google, Auth0 and any other issuer | `JENREPO_UI_OIDC_ISSUER_URI`, `JENREPO_UI_OIDC_CLIENT_ID`, `JENREPO_UI_OIDC_CLIENT_SECRET`, and `JENREPO_UI_OIDC_NAME` to label the button |
| **GitHub** | `JENREPO_UI_GITHUB_CLIENT_ID` and `JENREPO_UI_GITHUB_CLIENT_SECRET`, from a GitHub OAuth app |
| **LDAP or Active Directory** | `JENREPO_UI_LDAP_URL`, with the settings below |

**Key sign-in** is the way into a new deployment. A start that finds nobody able to sign in prints a one-time key
in its log, as [Getting started](/repository/getting-started/) shows: it signs in as the deployment's
administrator for an hour, or until an administrator exists. A deployment provisioned from configuration can name
its own key instead, `JENREPO_UI_ADMIN_KEY`, which is re-provisioned on every start for as long as it is set; the
server then prints no key. Either is meant to get you started, not to stay - once people sign in through your
identity provider, remove `JENREPO_UI_ADMIN_KEY`, set `JENREPO_KEY_LOGIN=false` and restart.

**LDAP** binds as the person signing in, either directly from a pattern or by searching for them first:

```bash
JENREPO_UI_LDAP_URL=ldaps://ldap.example.com
JENREPO_UI_LDAP_USER_DN_PATTERN="uid={0},ou=people,dc=example,dc=com"
# or, to search: JENREPO_UI_LDAP_USER_SEARCH_BASE, _USER_SEARCH_FILTER (default "(uid={0})"), _BIND_DN, _BIND_PASSWORD
JENREPO_UI_LDAP_GROUP_SEARCH_BASE="ou=groups,dc=example,dc=com"
JENREPO_UI_LDAP_ADMIN_GROUP=repository-admins
```

A person's directory groups become their groups here, and members of the administrator group administer the
deployment. A plain `ldap://` URL is refused unless `JENREPO_UI_LDAP_START_TLS=true` upgrades it, or
`JENREPO_UI_LDAP_ALLOW_PLAINTEXT=true` says the connection is private.

## Login keys

A person can also sign in with a **login key** of their own - for a small deployment with no identity provider, or
for someone the provider does not know. **Settings → Login keys** issues one: a **principal**, which becomes the
identifier `keylogin/<principal>`, an optional name to show for it, the tenant it joins, and the role it holds
there. **Issue key** shows the key once, beginning `jkl_`; only a hash of it is stored. The person chooses **Sign in
with a key** and pastes it. **Revoke** stops the key at once and removes the membership it was issued with.

Issuing a login key is the deployment administrators' decision, since a key can join a person to any tenant. A
script does it with a key of the operator tenant that holds the manage rights:

```bash
jenrepo keylogin issue ada --tenant releases --login "Ada Lovelace" --role editor
jenrepo keylogin list
jenrepo keylogin revoke <id>
```

The same operations answer at `/api/keylogin`. Login keys work only while key sign-in is switched on.

<div class="note">
  Signing in and holding access are separate. Anyone your identity provider signs in reaches the console, but
  someone who holds no role sees a page saying so, showing the identifier an administrator needs to grant them one
  - such as <code>oidc/8f3c1a…</code> or <code>ldap/ada</code>.
</div>

## Administrators

The deployment's administrators hold every right in every part of it. `JENREPO_UI_ADMINS` names them by
provider-qualified identifier, comma-separated: `github/<id>`, `oidc/<subject>`, `ldap/<user>`. The setting
**seeds** them on every start rather than mirroring them - removing an identifier from it does not take that
person's rights away, which is done in the console like any other change. A `*` entry is refused at startup:
administration belongs to people you can name.

## Members

**Access → Members** lists the people who hold a role in the deployment and gives others one. Enter the person's
provider-qualified identifier, optionally a login name to show beside it, choose **viewer**, **editor** or
**admin**, and press **Add / update user**. **Remove** takes the role away.

**Groups** grant rights to many people at once. **New group**, below the groups, creates one with its first grant:
a name, a scope - a repository, a build-cache project, or `*` for all of them - and rights such as
`repository:read,repository:write`. Each group is listed with what it grants and who is in it, and **Open** leads to
the group's own page, where grants are added and revoked, people are added and removed, and the group is deleted.
Everyone in a group holds what it grants, and loses it as they leave the group or the group loses the grant. People
signed in through LDAP arrive with their directory groups already.

## Credentials

**Access → Credentials** is where keys for build tools are issued and looked after. A key looks like
`jenk_releases.…`: a recognisable prefix, the deployment's tenant, a secret and a checksum.

**New credential** issues one: a label, an optional expiry, and **Generate credential**. The key is shown
**once**, on the credential's page, and only a hash of it is kept. That page then offers:

| Section | What it does |
| --- | --- |
| **Grants** | Grants the key a role on a scope: a repository or a build-cache project by name, or `*` for all. An optional path prefix narrows it to part of the repository, such as `maven/com/example`. |
| **Key expiry** | Changes when the key stops working, as a duration from now (`P30D`) or a date. |
| **Rotate key** | Issues a successor with the same grants and keeps the old key working for an overlap (`P7D` by default), so a pipeline can switch over without a gap. |
| **Source-IP allowlist** | Restricts the key to the addresses and ranges listed. |
| **Delete credential** | Revokes the key at once. |

Three roles are built in, and the **Roles** section adds your own as a name and a list of rights:

| Role | Rights |
| --- | --- |
| **read-only** | `repository:read`, `cache:read` |
| **deploy** | the above, and `repository:write`, `cache:write` |
| **admin** | everything |

The repository rights publish and resolve, and run the operations on one repository - its cleanup, retention,
pins, imports and staged releases. Everything else the API does - settings, keys, groups, tenants, walks - takes
`manage:read` or `manage:write` over `*`, and the parts that
concern the whole deployment rather than one tenant (its settings, upstreams, logs and tenants) also a key of the
operator tenant: the default tenant, unless `JENREPO_OPERATOR_TENANT` names another. So a **deploy** key in a CI
job can publish into every repository and still cannot change how the deployment is run.

A key issued without an expiry lives for 90 days. **Credential-lifetime policy** changes that default and can cap
how long any key may live.

A revoked or narrowed key stops working at once on the server that made the change, and on the other servers of a
multi-node deployment within the credential cache's lifetime - fifteen minutes by default (`auth.cache-ttl`).

A key belongs to the tenant it was issued in, and reaches that tenant's repositories alone. Every `/api` call acts
on the tenant the deployment serves the request for, as a download does - on a deployment serving one tenant, that
tenant. A deployment serving one
tenant refuses a key of any other with `403`, except a key of the operator tenant, which still manages the
deployment.

A key sent as the password of HTTP Basic is one a browser remembers for the host and attaches to anything it sends
there, including a form another site submits. So a write a browser marks as coming from another site - its
`Sec-Fetch-Site` header, or an `Origin` naming another host - is refused with `403` before anything else is decided.
Build tools send neither header, so nothing they do changes.

## Keyless CI

A CI platform that issues its jobs an identity token - GitHub Actions, GitLab and most others - can exchange it
for a short-lived key instead of storing one. **Keyless CI (OIDC trust)** on the Credentials page names which
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

- **Open, on a trusted network.** `JENREPO_AUTH=false` serves every request without a key - anyone who can reach
  the port can read and publish. The server says so in its log and in **Operations → Security posture** for as
  long as it runs that way.
- **A public, read-only mirror.** Keep keys on, let callers without one read, and refuse every write:

  ```bash
  JENREPO_ANONYMOUS_RIGHTS=repository:read
  JENREPO_READ_ONLY=true
  ```

  `JENREPO_READ_ONLY` refuses every write at the store itself - a publish, an import, a proxy fetch - so nothing
  gets around it. A common arrangement pairs one private read-write server with public read-only ones over the
  same bucket.
