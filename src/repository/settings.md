---
order: 12
title: Settings
description: Configuring a running deployment - the levels a setting is stored at, the first-boot wizard, the settings catalogue, a repository's and a project's own settings, upstreams, modules, tenants and backing settings up - and how configuration reaches the server.
---

A deployment is configured in two ways. **Runtime settings** live in the store and are changed in the console,
through the API or with the command line; most take effect at once. **Startup settings** - where the store is, how
people sign in, whether keys are required - come from the environment the server starts in, and change only with a
restart. The **Settings** section is for the deployment's administrators.

## Four levels

A runtime setting can be stored at up to four levels, and the narrowest one that holds a value wins:

| Level | Holds | Changed on |
| --- | --- | --- |
| **Deployment** | The value every tenant inherits. | **Settings → Settings** |
| **Tenant** | One tenant's own value, over the deployment's. | **Settings → Tenant settings**, and **Repositories → Limits** for the tenant's limits |
| **Repository** | One repository's own value - its routing and its retention rules. | The repository's **Settings** page |
| **Project** | One build-cache project's own value - its size cap, its entry lifetime and its eviction order. | The project's page |

Each setting declares the narrowest level it may be set at. The storage quota and the rate limit are tenant
settings, so the deployment sets a value for every tenant and one tenant may set its own. The retention rules are
repository settings, so the deployment and a tenant each hold the default their repositories inherit, and a
repository may set its own. A repository's routing has no wider default: it is the repository's own, or it is not
set.

Unsetting a value makes the level inherit again. A duration rule such as `max-age` also takes `none`, which
switches the rule off at that level even where a wider level sets one.

Every setting also has a **tier**. An **essential** setting is asked by the wizard that creates what it configures;
a **standard** one is shown on the settings pages; an **advanced** one tunes what was already decided - a cadence, a
cap, a timeout - and is shown once **Show advanced settings** is switched on. Nothing else differs: every tier is as
editable as the others.

## First-run setup

**First-run setup** is the wizard of a new deployment, at `/ui/setup`. It asks only what a new deployment has to
decide; everything else keeps its default and stays on the settings pages.

Its first step replaces the starter key. It says whether the session is still on it, and names who administers the
deployment from now on, to be granted administration when the setup is applied. Where login keys are installed it
comes filled in with `keylogin/admin`: applying the setup then also issues that administrator a login key, shown
once on the screen you land on - only its hash is kept - and you sign in with it from then on. Name someone another
sign-in method signs in instead, such as `github/alice`, and no key is issued; leave it empty and nobody is granted.
Where GitHub sign-in is available, the step also offers to sign you in with GitHub, described below.

### Trying Jenesis with a demo

While the deployment holds no repository, the setup's first page also offers to load a demo, so that every screen
has something to show. It creates hosted Maven and npm repositories and proxies of Maven Central and the npm
registry, publishes a few small packages into the hosted ones - one of them on the deny list, so the review queue
holds it - reads a few old versions with known vulnerabilities through the proxies, and, once a registry has
answered, switches the OSV advisory feed on and asks for a vulnerability scan. The offer lists every repository,
setting and registry it touches and warns that it loads code with known vulnerabilities into the deployment; it
starts only after you type `I want to trial jenesis` into its confirmation. It runs in the background, and its page
shows each step as it lands and, at the end, what was made and what stayed empty - without internet access the
hosted repositories still load. Once any repository exists, the offer is gone.

### The steps

After the first step comes one step per group of the essential settings, each row with what it does and its current value. The
retention rules and full-text search are asked as the deployment's default, which every repository inherits:

| Step | Asks |
| --- | --- |
| **Compliance** | Which advisory and malware feeds to consult, the vulnerability threshold, and what happens to a vulnerable or malicious package. |
| **Console** | Whether a person may sign in with a key. |
| **Proxy** | How many days a version fresh from upstream is held for review. |
| **Retention** | The four retention rules repositories inherit. |
| **Search** | Whether repositories keep a full-text index. |

**Next** checks a step and moves on; **Back** returns without losing anything, since the values travel with the
page, and the list of steps above the wizard returns to any step. The last step is a review of every choice, the
defaults left alone included, and **Apply setup** saves every changed value at once - a refused value saves none,
and the wizard returns to the step that asked it. **Apply now**, on a settings step, keeps the defaults of the steps
not yet seen and goes to the review to confirm. Nothing is written before **Apply setup**.

Someone signing in with the starter key is sent here first, once per session, until `setup-wizard` is switched
off. **Use defaults** leaves it with nothing changed and opens the console's dashboard; the wizard is always one
click away as **Settings → First-run setup**. The command line shows the same steps with `jenrepo setup`, and
decides one with `jenrepo setup set <key> <value>`.

### Signing in with GitHub from the first step

The first step shows the callback address to register with GitHub - the console's address followed by
`/login/oauth2/code/github`. Register a new OAuth app on GitHub with it, paste the
app's client id and a client secret it generates, and press **Save and sign in with GitHub and make me
administrator**. The two values are saved as the settings `ui.github.client-id` and `ui.github.client-secret`, which
apply to the next sign-in without a restart, and the browser goes to GitHub. The identity GitHub returns is made the
deployment's administrator as it signs in. The offer is good once, for ten minutes, and only in the session that
made it.

A client secret is stored only encrypted, with the key given to the server as `JENREPO_SECRETS_KEY`. Where none is
set, the step says so and shows a freshly generated value to set it to before a restart; the Helm chart generates
one on install. Where a GitHub app is configured already, the step offers only the sign-in.

## The settings catalogue

**Settings → Settings** lists every deployment-level setting, grouped by what it concerns - Compliance, Proxy,
Retention, Limits, Webhooks, Network, Caches and more. Each group shows its essential and standard settings; the
advanced ones join them when **Show advanced settings**, beside the filter, is switched on - except an advanced
setting given a value here, which is always shown. Each row shows:

- the setting's name, its key and the module it comes from;
- what it does, and its current value against its default;
- a **live** badge where a change applies at once, or **↻ restart** where it applies on the next start;
- **overridden** when it is set here rather than left to its default, with **Reset to default** beside its **Save**;
- **high-impact** where a change can start rejecting or admitting packages, which asks for confirmation.

The filter box above the list finds a setting by any word in its key, name or description, and switches on
**Show advanced settings** when only advanced settings match. A value saved here is stored with the repository and shared by every server of a multi-node
deployment.

A setting that picks one of a few values shows each by a readable name with a short description - the gate's
verdicts read **Allow**, **Hold for review** and **Reject** - while the API, the command line and the stored value
keep the constant (`ALLOW`, `QUARANTINE`, `REJECT`).

A setting also given in the environment is shown **pinned** and cannot be edited here, because the environment
wins - the page names what pinned it. Every change, on every page and at every level, is checked the same way before
it is stored, whether it comes from the console, the API or the command line, and is recorded in the audit trail.

A script reads and changes the same catalogue:

```bash
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/settings
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"HIGH"}' https://repo.example.com/api/settings/vulnerability-threshold
jenrepo settings set vulnerability-threshold HIGH
```

`?tenant=<name>` on the same calls, or `--tenant <name>` on the command line, reads or changes a tenant's value.

## A repository's settings

A repository's own settings are on its **Settings** page, under **Lifecycle** among its pages. Each row shows the
value in force - the repository's own, else its tenant's, else the deployment's - and **Reset to default** makes the
repository inherit again. Its routing is changed here, and shown on its **Overview**; the retention rules are also on
its **Retention & cleanup** page.

A repository can be given its settings as it is created, as [Repositories](/repository/repositories/) shows, and
changed later:

```bash
curl -X PUT -H "Jenesis-Repository-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"value":"20"}' 'https://repo.example.com/api/repository/settings/keep-last?repo=libraries'
jenrepo repos settings libraries set keep-last 20
jenrepo repos settings libraries clear keep-last
```

A build-cache project's settings work the same way, on the project's page, under
`/api/cache/projects/<name>/settings/<key>`, and with `jenrepo projects settings`.

## Upstreams

**Upstreams** holds where the deployment fetches from: the **format upstreams** each format fetches a miss from,
for the deployment and for one tenant over it, the **upstream credentials** to send a private upstream, and the
deployment's **repository routing**, which routes the repository of a name in every tenant.
[Proxying upstreams](/repository/proxying/) covers them.

## Backup & restore

**Backup & restore** downloads every stored setting as one JSON file and restores one. Keep a copy before a large
change: a restore replaces every stored deployment setting.

## Tenant settings

Some settings may differ per tenant - a stricter gate for one, a longer retention for another. **Tenant settings**
lists the ones that may, for the tenant you are working in, with the deployment's value beside any override, and
saves or reverts an override; a repository setting set here is the default for the tenant's repositories.
**Restore** replaces the tenant's overrides with a bundle exported earlier. The page is listed only where the
deployment serves several tenants.

## Modules

Every capability of the server - each format, each feed, each background job, each console page - is a module it
discovered at startup. **Modules** lists them with whether each is switched on, and **Enable** or **Disable**
changes that, exactly as `JENREPO_<MODULE>=false` would - at once for a module marked **live**, and otherwise on the
next restart.

When a module has been removed from a deployment but its data is still in the store, a section of its own below
the modules shows that data as orphaned, with how many objects and bytes it holds, and **Purge** removes it after
asking you to confirm. Nothing is ever removed because a module is merely absent - an image that is missing a module
by mistake looks the same - so data waits for its module to return until you purge it.

The same modules can be viewed **by contract**: every extension point the server has and, under each, the modules
that fill it - formats, stores, feeds, importers - with whether each is installed and switched on. It answers "is
that feature in this deployment, and is it on?" without reading a log.

## Tenants

**Tenants** lists the tenants of the deployment and opens one to work in. A deployment serves one tenant,
`releases`, unless `JENREPO_DEFAULT_TENANT` names another.

A script manages tenants the same way, with a key of the operator tenant that holds the manage rights:

```bash
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants              # list
curl -X PUT -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants/acme  # create
curl -X DELETE -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants/acme
jenrepo tenants create acme
```

Deleting a tenant removes everything it owns - its repositories and their artifacts, its credentials and its
members - and cannot be undone.

## How startup settings reach the server

The server is configured the way any Spring Boot application is. Every setting has a key under `jenrepo.`, and the
environment variable is the key upper-cased, with dots and dashes as underscores:

| Key | Environment variable |
| --- | --- |
| `jenrepo.filesystem.root` | `JENREPO_FILESYSTEM_ROOT` |
| `jenrepo.ui.oidc.issuer-uri` | `JENREPO_UI_OIDC_ISSUER_URI` |
| `jenrepo.key-login` | `JENREPO_KEY_LOGIN` |

Environment variables are the natural form for a container. A startup setting the server does not recognise -
usually one spelled wrong, or renamed by a release - is named in a warning in the log at startup, with the
closest setting it does recognise where one is close.

[The configuration reference](/repository/configuration-reference/) lists every setting, runtime and startup
alike.
