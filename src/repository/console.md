---
order: 3
title: Finding your way around
description: The console's two navigation levels - the sections across the top and the pages beside the content - the pages of a repository, and which pages each role sees.
---

The console is where you look after a deployment: what its repositories hold, what the gate decided, who may do
what, and how the server is configured. It runs inside the server, on the same port, so there is nothing else to
start - open the server's address in a browser and sign in. This chapter shows how it is laid out, so the
chapters that follow can say "open **Access → Credentials**" and you know where that is.

## Two levels

Every page has the same frame. The bar across the top holds the **sections** - the first choice you make - and
the list down the left side holds the **pages** of the section you are in. The page itself sits on the sheet in
the middle.

| Section | Pages |
| --- | --- |
| **Repositories** | All repositories, and each repository by name |
| **Build cache** | Projects |
| **Access** | Credentials, Members |
| **Operations** | Metrics, Security posture, Walks, and Deploy once it is switched on |
| **Settings** | Setup, Settings, Tenant settings, Modules, Installed providers, Instances |

A section is shown only when it holds a page you may open, and clicking it opens its first page. Nothing is
hidden behind a menu: what you may see is always in one of those two places.

## Inside a repository

Opening a repository changes the list on the left: it now names the repository, offers **All repositories** to
go back, and lists that repository's own pages under three headings.

| Heading | Pages |
| --- | --- |
| **Contents** | Overview, Browse & search, Staging, Import |
| **Screening** | Quarantine, Refused, Vulnerabilities, Findings, Signers |
| **Lifecycle** | Retention & cleanup, Pins |

Every repository has the same pages, so moving between two of them keeps you on the page you were reading. A
page whose feature a deployment does not carry - staging, or the vulnerability feeds - is simply not listed.

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
| **Editor** | Everything a viewer can, and change things: save a retention policy, pin a version, release or discard a held artifact, promote a staging upload. |
| **Admin** | Everything an editor can, and manage access: **Credentials**, **Members**, and manual uploads through **Deploy**. |
| **Super-administrator** | Everything, across the whole deployment: the **Operations** pages other than **Deploy**, and all of **Settings**. |

A page you may read but not change shows its data without the forms that would change it.

Signing in and holding a role are separate. Anyone your identity provider signs in reaches the console, but
someone who holds no role sees a page saying so, with the identifier an administrator needs to grant them one.
[Access](/repository/access/) covers both halves.

<div class="note">
  The console renders what is already known and never waits. Where work runs in the background - a rescan, a
  cleanup preview, an import - the page says it is running and refreshes itself until it finishes, so you can
  keep reading while it does.
</div>
