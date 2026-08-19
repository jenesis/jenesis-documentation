---
order: 8
title: Authentication & access
description: Identifying every request and deciding what it may do - the authentication seam, the key credential model and its grants, OIDC token exchange and console sign-in, anonymous read, the deployment-wide read-only mode, and the settings that switch enforcement on.
---

Everything so far assumed an open repository - one that answers any request that reaches it. A deployment
that is reachable by anyone else needs the other thing: every request **identified**, and every operation
**checked** against what that identity may do. Authentication is a discovered capability like the rest, so
the server runs open until you enforce it, and the mechanism that enforces it is a module rather than a
different binary.

A fresh server **enforces**: every request is authorised against a per-credential key, and one that carries
none is refused. The machine-to-machine artifact API is keyed by a header, with no browser session, no CSRF
and no HTTP Basic in the way.

Running **open** is the opt-out, not the default - `jenesis.repository.auth=false` (env
`JENESIS_REPOSITORY_AUTH=false`) allows every request and identifies nobody.

<div class="warning">
  Opening the wire is never silent. <code>auth=false</code> raises the <code>jenesis.auth.open</code>
  security-posture advisory, logged once at boot and shown on the console and at
  <code>GET /api/posture</code>, so a deployment that is open says so wherever an operator looks. It is the
  right setting for a laptop; it is the wrong one for anything reachable.
</div>

## The capabilities

### The artifact space

The server serves **one artifact space**, named by `jenesis.repository.tenant` and
`jenesis.repository.repository` - both `default` unless you set them. Every request resolves to it: artifacts
under the `/repository/…` prefix, which is stripped so a format sees its own `/maven/`, `/raw/` … path, and
the OCI registry at `/v2/`, where the Docker protocol pins it.

The two names look like more than they are. Objects are stored under a `<tenant>/<repository>/…` scope
(introduced in [Storage](/repository/storage/)), so a space is addressed the same way whether a deployment
serves one or routes to many - which is why the settings carry a tenant even when there is only ever one, and
why data stays where it was left if a deployment's routing is later replaced.

### The authentication seam

Enforcement runs one **credential model** - a key on a request, checked against stored grants - behind a
composition seam. Two things plug into that seam:

- **Token exchange** - a discovered mechanism that trades a workload's identity token for a short-lived key,
  so a CI job never stores a static secret. With none installed, the exchange endpoint reports the feature is
  not installed rather than failing closed.
- **Console sign-in** - OAuth2 / OIDC login for people, layered over the same baseline chain and resolving to
  the same key model, rather than a second identity system beside it.

So the always-present mechanism is **key authentication**; the others are capabilities a deployment adds. The
sections below take each in turn.

## Implementations

### Key authentication

An enforcing request carries its credential in the **`Jenesis-Repository-Key`** header (and, where the route
does not already name it, the target repository in `Jenesis-Repository-Name`). A GET or HEAD needs
`repository:read`; any other method needs `repository:write`.

A key is minted in a **scannable, self-describing** form:

```
jenk_<tenant>.<secret><checksum>
```

- the **`jenk_` prefix** and the trailing **CRC checksum** let a secret scanner recognise a leaked Jenesis key
  and validate it offline, and let the server reject a malformed or truncated key with **no store lookup**;
- the **owner travels in the key**, so a request is attributed without a directory read;
- only the key's **SHA-256 hash is ever stored** - never the secret itself.

#### Grants: scopes and rights

A credential's rights are stored as a map of **scope → rights**:

- A **scope** is a repository name (`*` matches every repository), optionally narrowed to a path prefix as
  `<repo>:<prefix>` - a prefix grant covers a request only when its path lies **at or under** the prefix on a
  segment boundary. So one key can hold repository-wide and path-scoped rights at once.
- A **right** is a `<surface>:<verb>` token. The built-in surfaces are `repository`, `cache` and `manage`,
  each with a `read` and a `write` verb. A `<surface>:*` token grants every verb on that surface, and a bare
  `*` grants everything - an owner key.

| Right | Allows |
|-------|--------|
| `repository:read` / `repository:write` | resolve from / publish to a repository |
| `cache:read` / `cache:write` | read / populate the pull-through cache |
| `manage:read` / `manage:write` | view / change management surfaces |

Because a right names its surface, **one key can carry any mix** - repository, cache and management rights
together - which is how a single credential authorises a combined deployment. A grant check reads the stored
objects on **every request**, so revoking or narrowing a grant takes effect at once, and an **expired key is
rejected before its grants are even read**.

#### Lifetime, rotation, and containment

A minted key **expires by default** - 90 days unless a shorter one is requested - and a deployment or tenant
policy can set both a **default lifetime** and a **hard ceiling** no key may outlive. A key can be **rotated**:
a successor inherits the same label, grants and allowlist with a fresh lifetime, and the old key keeps working
for a short **overlap** (a week by default) so callers swap over with no downtime.

Two containment controls narrow a key further:

- a **source-IP allowlist** (CIDRs) refuses a key used from an unlisted address, so a stolen key is useless off
  its network - with `X-Forwarded-For` honoured only from a trusted proxy, so a client cannot spoof its own
  address;
- a leaked key can be **revoked immediately** by its raw value (the tenant and checksum are read straight off
  the key), and the credential-usage capability stamps each key's **last-use time, address and count** (batched
  off-request) so an unused or misused key is visible.

<div class="note">
  Provisioning, rotating, listing and revoking credentials - and editing roles, trusts and per-tenant policy -
  are done through the console or admin API of a deployment that installs the management capability. A plain
  free server enforces the same stored grants; it just has no built-in surface to edit them.
</div>

### Roles and memberships

Raw `<surface>:<verb>` tokens are precise but unfriendly, so a **role** bundles them under a name. Three
built-in roles form a hierarchy a console can offer directly:

| Role | Bundles |
|------|---------|
| `read-only` | `cache:read`, `repository:read` |
| `deploy` | adds `cache:write`, `repository:write` |
| `admin` | `*` - everything |

A tenant can define **custom roles** (and override a built-in name), so membership in a role is how you grant a
person or a CI identity a coherent set of rights without spelling out tokens.

### OIDC token exchange

A CI job already holds an identity token from its platform. **Token exchange** trades that token for a
short-lived Jenesis key, so the pipeline stores **no static secret at all**. Install the OIDC module
(`source/oidc`) and the exchange is live - there is nothing more to configure, because *which* issuers are
honoured is **per-tenant trust data**, not deployment configuration.

Each tenant keeps a set of named **trusts**. A presented token is admitted only when it matches one:

- its **issuer** must name a configured trust - a forged or foreign token matches nothing;
- its signature is verified by that issuer's published **JWKS** (via standard OIDC discovery, with key rotation
  and caching handled by the vetted Spring/Nimbus decoder - not hand-rolled crypto);
- the trust's **audience** and **subject** (a glob, blank for any) must match.

On a match, a fresh key is minted carrying the trust's **scope and rights**, expiring after the trust's **TTL**
(an hour by default). A trust therefore reads as: *a token from this issuer, for this audience and subject, is
worth this much, for this long.*

<div class="tip">
  This is the recommended way to let CI publish. The build's OIDC token is exchanged at job start for a key
  scoped to exactly the repository it may write, and it expires on its own - nothing to store in the pipeline,
  nothing to rotate, nothing to leak.
</div>

### Console sign-in

The mechanisms above authenticate **machines**. **People** sign in to the
[console](/repository/console/) over OAuth2 / OIDC, through the same authentication seam and resolving to the
same credential model - so a person's console rights and a token's API rights are one grant system rather
than two.

<div class="note">
  For a <strong>local run</strong>, the <code>dev</code> profile
  (<code>SPRING_PROFILES_ACTIVE=dev</code>) swaps in a built-in <code>admin</code>/<code>admin</code> form
  login so you can open the console without an identity provider - see
  <a href="/repository/getting-started/">Getting started</a>. It is for local use only.
</div>

Whichever mechanism denies a request, the server records the failure by **mechanism** and outcome, exposed as
a metric so a dashboard can watch authentication health across all of them at once.

## Letting a keyless caller read

An enforcing deployment refuses a request that carries no credential. Where a repository is meant to be
readable by anyone - a public mirror, an open-source project's own artifacts - one setting grants a keyless
caller a named set of rights:

```properties
jenesis.repository.anonymous-rights=repository:read
```

It is **strictly opt-in and blank by default**, so an enforcing deployment stays closed until somebody says
otherwise, and what is granted is spelled out rather than implied - anonymous read is a different decision
from anonymous write, and each is named.

<div class="note">
  This is not the same as leaving the wire open. An open deployment (<code>auth=false</code>) allows every
  request and identifies nobody; an enforcing deployment with anonymous rights still authenticates every
  caller that <em>does</em> present a key, and grants the unauthenticated ones exactly the listed rights.
</div>

## Read-only mode

Authentication decides *who* may write; a second, deployment-wide switch removes writing altogether.
**Read-only mode** (`jenesis.repository.read-only=true`, env `JENESIS_REPOSITORY_READ_ONLY`, off by default)
refuses **every** write with `403` - a hosted publish, an import, every mutating admin action - while browse,
download, search and all read APIs work normally.

The refusal is enforced at one low-level choke point: a decorator wraps the storage seam itself, so an
*internal* write - a pull-through proxy caching an upstream artifact, an import replaying assets - is refused
before any bytes are stored, and the write-producing background jobs are disabled. There is no path around
it, whatever credentials a request carries.

Two deployments want this:

- **A browsable-but-immutable demo or archive** - the contents are the point; changing them is not.
- **A public read-only mirror.** Pair one firewalled read-write instance that publishes into a shared store
  with public read-only instances serving reads from it - the public face cannot be made to write, not even
  through its own proxy caching.

A client or console does not have to probe for the mode: the server advertises it, together with whether the
wire is credential-gated, at a capability endpoint - `GET /api/capabilities` answers a small JSON map
(`readOnly`, `auth`) a distribution extends as it adds capabilities - and the
[console](/repository/console/) shows a read-only banner when the mode is on.

## Settings

Authentication and tenancy are pinned from above the store - an environment variable or a
`-Djenesis.repository.<key>=…` system property - since they decide how the wire is gated before any tenant
configuration is read.

| Key | Default | Meaning |
|-----|---------|---------|
| `auth` | `true` | Enforce the credential model. `false` leaves the server **open** - every request allowed - and raises a security-posture advisory. |
| `read-only` | `false` | Refuse every write - external or internal - with `403`, while all reads work normally. Advertised at `GET /api/capabilities`. |
| `tenant` | `default` | The tenant half of the one artifact space this deployment serves. |
| `repository` | `default` | The repository half of that space. |

Beyond these, the finer-grained controls are **per-tenant data** held in the store - credential lifetime
**policy** (default and ceiling), OIDC **trusts**, custom **roles**, and a tenant's **quota** and
**[rate limit](/repository/rate-limiting-usage/)**.

Installing the OIDC module enables token exchange; a server without it runs enforcing and key-only, which is
a complete and safe deployment on its own. Where the module is installed it stays configuration-switchable -
`jenesis.repository.oidc=false` turns the exchange off exactly as removing the module would, and
`jenesis.repository.token-exchange` selects among implementations by name, per
[Feature toggles & implementation selection](/repository/configuration-reference/).
