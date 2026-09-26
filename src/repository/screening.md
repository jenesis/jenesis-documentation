---
order: 7
title: Screening what comes in
description: The gate every artifact passes before it is served - its verdicts, the advisory and malware feeds, signatures and policy rules - and a repository's screening pages - Quarantine, Refused, Vulnerabilities, Findings and Signers.
---

Every artifact passes a **gate** before the repository serves it - whether a client published it or the
repository fetched it from upstream. The gate reaches one of three verdicts:

| Verdict | What happens |
| --- | --- |
| **Allow** | The artifact is stored and served. |
| **Quarantine** | The artifact is stored but withheld: clients get `404` for it until someone releases it from the review queue. |
| **Reject** | The artifact is refused and nothing is stored. The client gets an error, and the refusal is recorded. |

This chapter covers what the gate checks, how to tune it, and the **Screening** pages every repository has in the
console.

## What the gate checks

| Check | Default | Settings |
| --- | --- | --- |
| **Known vulnerabilities** - advisories at or above a severity band | Reject at `CRITICAL` | `vulnerability-threshold`, `vulnerability-action` |
| **Malicious packages** - packages a curated feed marks malicious | Reject | `malware-action` |
| **The deny list** - coordinates you forbid outright | Reject | `deny-list`, `deny-list-action` |
| **Signatures** - an untrusted signer, a signature that does not match its bytes, a coordinate whose signer changed | Quarantine an untrusted or changed signer, reject a broken signature | `signature-untrusted`, `signature-invalid`, `signature-signer-changed` |
| **Provenance** - build attestations that name the wrong builder or source | Quarantine, once you name what to expect | `provenance-admission-*` |
| **Your own rules** - expressions over what the gate knows | None | `policy-rules` |
| **Release immutability** - republishing a release version with different bytes | Refused with `409` | `allow-redeploy` |

Every setting here is under **Settings → Settings**, in the **Compliance** group, and takes effect at once
unless it says it needs a restart.

## Switching the feeds on

The vulnerability and malware checks need something to check against, and **no feed is asked anything until you
say so**. Three feeds ship with the image, each off by default:

| Feed | Setting | What it answers |
| --- | --- | --- |
| OSV (osv.dev) | `osv` | Known vulnerabilities across every ecosystem |
| GitHub Advisory Database | `github` | Known vulnerabilities, with GitHub's reviewed severities |
| OpenSSF malicious packages | `openssf` | Packages published with malicious intent |

Switch them on during **Setup**, or set them in **Settings → Settings** and restart. Each feed has an endpoint
setting beside it (`osv-endpoint`, `github-endpoint`, `openssf-endpoint`) for a mirror or a proxy.

<div class="warning">
  A feed fails closed. While it is on and cannot be reached, a publish it would have screened is held for review
  rather than admitted unscreened - so switch a feed on only where the deployment can reach it, and read a held
  artifact's reason before taking it for a verdict on the content.
</div>

Beyond checking each publish, the repository **re-scans everything it already holds** against the feeds on a
schedule - hourly by default (`scheduled-scan`, `scan-interval-millis`) - so an advisory published after an
artifact was accepted still reaches it.

## Rules of your own

`policy-rules` takes one rule per line, each a verdict and an expression. The expression sees the artifact's
ecosystem, coordinate, version, licences, advisories and their severity:

```text
reject #severityRank >= 4
quarantine #ecosystem == "npm" and #advisoryCount > 0
quarantine !#licenses.?[#this matches "(?i).*agpl.*"].empty
```

Expressions are sandboxed - no method calls and no type references - and an empty setting switches the rules off.

## Quarantine

**Quarantine** is the review queue: every artifact the gate is holding, with its verdict, the reasons, and what
placed the hold. An editor answers each one:

- **release** publishes it into the repository, and clients can fetch it from then on;
- **discard** drops it for good, after confirming - it cannot be released afterwards.

The queue pages through a backlog of any size. A hold placed by a module that has since been removed is still
listed, marked as not installed, and can still be released.

## Refused

**Refused** lists what the gate turned away outright, most recent first: the coordinate, the verdict, the reasons
and when. A refusal stores nothing, so there is nothing to release - this page is the record of a denied publish,
and often the only one.

## Vulnerabilities

**Vulnerabilities** lists the advisories that apply to what the repository holds, from the last scan, and says
when that scan ran. **Rescan against the advisory feeds** starts a fresh one in the background; the page shows it running and refreshes
itself until it finishes. With no feed switched on, the page says so and links to the settings that change it.

## Findings

**Findings** is the ledger every check writes into: one row per thing found about a package version - an
advisory, a malicious-package record, a signature problem - filterable by coordinate, kind, source, category and
severity. An editor can **Confirm** a finding or **Dismiss** it, and the decision is kept beside the finding for
the next person who reads it.

## Signers

**Signers** lists who signed the versions the gate accepted - each signer's key or identity and, for a keyless
signature, the issuer that certified it. Opening a signer lists everything it signed in this repository: the
reach of a key you are about to stop trusting.
Which signers are trusted is set in **Settings**: `signature-trusted-keys` for OpenPGP keys,
`signature-trusted-certificates` for certificate chains, and `signature-trusted-signers` to pin a namespace to one
signer.

<div class="tip">
  The gate decides on the way in, and the scheduled scan keeps deciding afterwards. When a later scan finds a
  problem with something already served, it lands in <strong>Vulnerabilities</strong> and
  <strong>Findings</strong>, where it can be reviewed like anything the gate held on arrival.
</div>
