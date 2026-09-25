---
order: 12
title: Settings
description: Configuring a running deployment from the console - the first-run guide, the settings catalogue, per-tenant overrides, modules, the installed providers, and backing settings up - and how configuration reaches the server.
---

A deployment is configured in two ways. **Runtime settings** live in the store and are changed in the console
under **Settings**; most take effect at once. **Startup settings** - where the store is, how people sign in,
whether keys are required - come from the environment the server starts in, and change only with a restart. The
**Settings** section is for the deployment's administrators.

## Setup

**Setup** is the first-run guide: a short list of the decisions a new deployment should make, each showing the
settings it concerns with their current values, so they can be answered in place.

1. **Stop using the starter credential** - whether the administrator key is still set, with links to grant a
   real administrator and to issue a real key.
2. **Advisory feeds** - which vulnerability and malware feeds to consult.
3. **Vulnerability handling** - the severity threshold, and what happens to an artifact that reaches it.
4. **Malware handling** - what happens to a package known to be malicious.
5. **Being told** - where to send webhook notifications.
6. **Withholding new releases** - how many days a version fresh from upstream is held for review.
7. **Retention and collection cadence** - what is kept, and how often the store is walked.
8. **This guide** - whether the guide opens on sign-in at all.

Someone signing in with the administrator key is sent here first, once per session, until `setup-wizard` is
switched off. **Skip for now** leaves it, and it is always one click away as **Settings → Setup**.

## The settings catalogue

**Settings → Settings** lists every runtime setting the deployment carries, grouped by what it concerns -
Compliance, Retention, Webhooks, Proxy, Operations and more. Each row shows:

- the setting's name, its key and the module it comes from;
- what it does, and its current value against its default;
- a **live** badge where a change applies at once, or **↻ restart** where it applies on the next start;
- **changed** when it differs from its default, with a **Revert** button beside it;
- **high-impact** where a change can start rejecting or admitting packages, which asks for confirmation.

The filter box above the list finds a setting by any word in its key, name or description. A value saved here is
stored with the repository and shared by every server of a multi-node deployment.

A setting also given in the environment is shown **pinned** and cannot be edited here, because the environment
wins - the page names what pinned it.

The same page carries three more sections:

- **Repository definitions** - the repositories that fetch from an upstream or group others, covered in
  [Proxying upstreams](/repository/proxying/).
- **Format upstreams** and **Upstream credentials** - where each format fetches a miss from, and the credentials
  to send a private upstream.
- **Backup & restore** - **Download** every stored setting as one JSON file, and **Import bundle** to restore
  one. Keep a copy before a large change.

## Tenant settings

Some settings may differ per tenant - a stricter gate for one, a longer retention for another. **Tenant settings**
lists the ones that may, for the tenant you are working in, with the deployment's value beside any override, and
saves or reverts an override. A single-tenant deployment has no reason to use it.

## Modules

Every capability of the server - each format, each feed, each background job, each console page - is a module it
discovered at startup. **Modules** lists them with whether each is switched on, and **Enable** or **Disable**
changes that on the next restart, exactly as `JENREG_<MODULE>=false` would.

When a module has been removed from a deployment but its data is still in the store, the page shows that data as
orphaned, with how many objects and bytes it holds, and **Purge orphaned data** removes it after asking you to
confirm. Nothing is ever removed because a module is merely absent - an image that is missing a module by mistake
looks the same - so data waits for its module to return until you purge it.

## Installed providers

**Installed providers** lists every extension point the server has and, under each, the modules that fill it -
formats, stores, feeds, importers - with whether each is installed and switched on. It answers "is that feature
in this deployment, and is it on?" without reading a log.

## Instances

**Instances** lists the tenants of the deployment, opens one to work in, and reclaims disk space across all of
them. A deployment serves one tenant, `releases`, unless `JENREG_DEFAULT_TENANT` names another.

A script manages tenants the same way, with a key of the operator tenant that holds the manage rights:

```bash
curl -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants              # list
curl -X PUT -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants/acme  # create
curl -X DELETE -H "Jenesis-Repository-Key: $KEY" https://repo.example.com/api/admin/tenants/acme
jenesis-repo tenants create acme
```

Deleting a tenant removes everything it owns - its repositories and their artifacts, its credentials, its audit
trail and its members - and cannot be undone.

## How startup settings reach the server

The server is configured the way any Spring Boot application is. Every setting has a key under `jenreg.`, and the
environment variable is the key upper-cased, with dots and dashes as underscores:

| Key | Environment variable |
| --- | --- |
| `jenreg.filesystem.root` | `JENREG_FILESYSTEM_ROOT` |
| `jenreg.ui.oidc.issuer-uri` | `JENREG_UI_OIDC_ISSUER_URI` |
| `jenreg.key-login` | `JENREG_KEY_LOGIN` |

Environment variables are the natural form for a container. A startup setting the server does not recognise -
usually one spelled wrong, or renamed by a release - is named in a warning in the log at startup, with the
closest setting it does recognise.

[The configuration reference](/repository/configuration-reference/) lists every setting, runtime and startup
alike.
