---
order: 3
title: Finding your way around
description: The console's two navigation levels - the sections across the top and the pages beside the content - the pages of a repository, and which pages each role sees.
---

The console is where you look after a deployment: what its repositories hold, what the gate decided, who may do
what, and how the server is configured. It runs inside the server, on the same port, so there is nothing else to
start - open the server's address in a browser and sign in. An identity provider returns the browser to `/login/oauth2/code/github` or `/login/oauth2/code/oidc`, which is the
callback address to register with it. This chapter shows how it is laid out, so the
chapters that follow can say "open **Access → Credentials**" and you know where that is.

## Two levels

Every page has the same frame. The bar across the top holds the **sections** - the first choice you make - and
the list down the left side holds the **pages** of the section you are in. The page itself sits on the sheet in
the middle.

| Section | Pages |
| --- | --- |
| **Repositories** | All repositories, New repository, Limits |
| **Build cache** | Projects |
| **Access** | Credentials, Members |
| **Operations** | Metrics, Security posture, Caches, Walks |
| **Settings** | Settings, Upstreams, Tenant settings, Modules, Tenants, Backup & restore, First-run setup, Login keys |

**Tenants** is listed for whoever can choose between several: a super-administrator, and a member of more than one
tenant.

**All repositories** is one table across the page, with a filter above it that narrows the rows to the names,
formats and descriptions matching what you type. **New repository** - listed for whoever may create one, and linked
from the page's description too - opens the wizard.

A section is shown only when it holds a page you may open, and clicking it opens its first page. Nothing is
hidden behind a menu: what you may see is always in one of those two places.

## Inside a repository

Opening a repository changes the list on the left: it now names the repository, offers **All repositories** to
go back, and lists that repository's own pages: first its contents under the repository's name, then the rest
under four headings.

| Heading | Pages |
| --- | --- |
| *(the repository's name)* | Overview, Browse & search, Staging, Import, and Deploy once it is switched on |
| **Review** | Quarantine, Refused |
| **Risk** | Vulnerabilities, Findings, Licenses, Maintainer health |
| **Provenance** | Signers |
| **Lifecycle** | Retention & cleanup, Pins, Deprecations & yanks, Settings, Export |

Every repository has the same pages, so moving between two of them keeps you on the page you were reading. A
page whose feature a deployment does not carry - staging, or the vulnerability feeds - is simply not listed.

Each of these pages opens the same way: the trail back through **Repositories** to the repository, ending in the
page's own title, set large. What the repository is - the format it holds and the address a client reaches it at -
is said once, on its **Overview**. A coordinate on any page links to that coordinate's own page, headed by the
coordinate, which lists its versions newest first: each with its count of files, the folder they share and the
files by name under it, a **Pin**, and **Deprecate or yank**, which opens that version on the repository's
**Deprecations & yanks** page.

## Wizards

Three things are created through a wizard rather than a single form: the deployment itself on its first boot
(**Settings → First-run setup**), a repository (**New repository**) and a build-cache project (**New project**).
Each asks what the thing is, then the settings it should have from the start, one group per step, and ends on a
review of every choice. **Next** and **Back** move between the steps without losing anything, and nothing is
written until the last button - so a wizard left half-way leaves nothing behind. [Settings](/repository/settings/)
says which settings each one asks.

## Buttons

A button's look says what kind of thing it does before you press it; its label says what:

| Look | Means |
| --- | --- |
| **Filled** | The page's main action, such as **Create repository** or **Save**. |
| **Plain outline** | An everyday action that changes little, such as **Preview cleanup** or **Revert**. |
| **Amber outline** | An action with a consequence that can be undone, such as releasing a held artifact, promoting a staged upload or running a cleanup now. It asks before it acts. |
| **Red outline** | An action that loses something, such as deleting a repository or discarding a held artifact. It asks before it acts, and a deletion asks you to type the name of what is deleted. |

Where a row of a list has several actions, they sit together at its end, with the red one last and set apart.

## The header

Beside the sections, the header carries four more things:

- **The security posture count** - a warning badge with the number of configuration advisories the deployment
  currently raises, shown to administrators of the deployment. It links to **Operations → Security posture**.
- **The theme switch** - the half-filled circle flips between light and dark, and follows your operating
  system's preference until you choose. The choice is remembered per browser.
- **Your name** - the name you signed in with. Clicking it signs you out.
- **A notice strip** - above everything, when the deployment has something to say wherever you are, such as
  running read-only.

On a narrow screen the sections move into the list on the left, which folds away behind a **Menu** button.

## Who sees what

What you may see and do follows your role in the deployment. There are three roles, plus the deployment's own
administrators:

| Role | Can |
| --- | --- |
| **Viewer** | Read every repository page and the build cache's projects. |
| **Editor** | Everything a viewer can, and change things: create a repository, save a retention policy, pin a version, release or discard a held artifact, promote a staging upload. |
| **Admin** | Everything an editor can, and manage access: **Credentials**, **Members** and groups, the tenant's storage quota and rate limit on **Limits**, taking a repository out through **Export**, and manual uploads through **Deploy**. |
| **Super-administrator** | Everything, across the whole deployment: the **Operations** pages and all of **Settings**. |

A page you may read but not change shows its data without the forms that would change it.

Signing in and holding a role are separate. Anyone your identity provider signs in reaches the console, but
someone who holds no role sees a page saying so, with the identifier an administrator needs to grant them one.
[Access](/repository/access/) covers both halves.

<div class="note">
  The console renders what is already known and never waits. Where work runs in the background - a rescan, a
  cleanup preview, an import - the page says it is running and refreshes itself until it finishes, so you can
  keep reading while it does.
</div>
