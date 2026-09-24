---
order: 8
title: Retention, pins and cleanup
description: How long a repository keeps what it holds - the retention policy, previewing and running a cleanup, pinning the versions that must stay, and how the space is reclaimed.
---

A repository keeps every version it is given until you tell it otherwise. The **Lifecycle** pages of a repository
are where you do: **Retention & cleanup** sets a policy for which versions stay and applies it, and **Pins**
names the versions no policy may touch. Space is given back in a second step, by a collector that removes what
nothing refers to any more.

## Retention & cleanup

**Retention & cleanup** shows the repository's retention policy as four dials. A version is **kept only if it
satisfies every dial that is set**; a dial left empty imposes nothing, so an empty policy keeps everything.

| Dial | Keeps | Example |
| --- | --- | --- |
| **keep-last** | At most this many newest versions of each package; `0` imposes no cap. | `20` |
| **max-age** | Versions younger than this. | `P365D` |
| **prerelease-expiry** | Prereleases - `1.0-beta`, `2.0.0-rc.1` - younger than this. | `P14D` |
| **not-downloaded-for** | Versions downloaded within this window. | `P90D` |

Durations are ISO-8601: `P30D` is thirty days, `PT12H` twelve hours. **Save retention** stores the policy for
this repository; saving needs the editor role.

Below the policy, two buttons act on it:

- **Preview cleanup** works out which versions the policy would remove, without removing anything, and lists
  them - how many, and the first of them with the reason for each.
- **Run cleanup now** removes them.

Both run in the background, however large the repository is. The page shows what is running and refreshes itself,
and afterwards shows the outcome of the last preview and the last cleanup, with when each finished.

A cleanup also runs on its own: the deployment walks every repository's store daily at 03:00 UTC and applies each
repository's policy. **Operations → Walks** changes when.

<div class="note">
  <strong>not-downloaded-for</strong> needs downloads to be counted, which they are by default
  (<code>track-downloads</code>). Counts are gathered in memory and written in batches, every six hours by
  default (<code>download-flush-interval</code>), so a version's last download may be up to that far behind.
</div>

## Pins

A **pin** keeps a version whatever the retention policy says - the release in production, the version a customer
depends on. **Pins** lists the pinned versions of the repository and adds new ones: enter the ecosystem, the
coordinate and the version, and press **Pin a version**. **unpin** lifts a pin, after confirming; the version is
then treated like any other on the next cleanup.

The package page lists, for each version, whether it is pinned.

## How space is reclaimed

Removing a version removes the repository's reference to it, not necessarily its bytes: the store keeps each
distinct file once, however many versions or formats refer to it. The **collector** finds the files nothing
refers to any more and removes them. It runs on the weekly walk of the store, on Sundays at 03:00 UTC by default,
and a file becomes collectable only after a grace period, so an upload in progress is never mistaken for garbage.

When a repository holds data for an ecosystem no installed format can place - because a format was switched
off - the collector leaves that whole repository alone rather than guess. Its **Overview** lists such
**Absent formats**; bring the format back, or **Forget ecosystem** to retire those records and let the collector
proceed.

## Other things that expire

A few other things are kept for a limited time, each with its own setting under **Settings → Settings**:

| What | Kept for | Setting |
| --- | --- | --- |
| An open staging id nobody has touched | 30 days | `staging-ttl` |
| A finished import job, on the Import page | 7 days | `import-job-ttl` |
| The gate's decision log - the rows behind **Refused** | 180 days | `quarantine-log-retention` |

<div class="tip">
  <strong>Preview cleanup</strong> before a first run on a large repository: the preview shows exactly what a
  policy would remove, and nothing changes until you press <strong>Run cleanup now</strong>.
</div>
