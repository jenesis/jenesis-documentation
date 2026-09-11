---
order: 12
title: Securing the supply chain
description: The reasoning behind Jenesis's supply-chain features - which attack each one answers, where each one stops, and how pinning, signatures, isolation and the compliance checks compose into a defensible build.
---

*[Supply-chain features](/tool/supply-chain/)* describes what each feature does. This chapter is the reasoning
around them: which attack each one answers, where each one stops, and what a build looks like when they are
combined. It also documents `@jenesis.signature`, the one mechanism that has no other home.

## What an attacker needs

A build is an attractive target because it runs code with your rights and produces something other people
install. Two surfaces carry that risk:

- **What you ship.** The jars in your artifact's closure. A compromised release, a hijacked publishing account
  or a typo-squatted coordinate arrives as an ordinary dependency and runs wherever your artifact runs.
- **What builds it.** Compilers, linters, formatters, test engines. These never ship, but they execute on your
  machine and write the bytes you publish, so a compromised one can alter output that looks untouched.

The second surface is usually the larger one: a build resolves far more tools than a distribution ships
libraries. It is also where Jenesis differs most from the usual arrangement.

## The tool is not a dependency

`build.jenesis` requires `jdk.compiler` and `java.xml` and nothing else - there is no third-party library
anywhere in the engine. It ships as plain Java source under `build/jenesis/` in your own repository
(see *[Getting started](/tool/getting-started/)*), so the build tool arrives the way your application code
does: by review, in a diff, under version control.

That removes a class of risk rather than mitigating it: there is no plugin resolution before a build starts,
and no plugin closure to pin. External tools a build genuinely needs - a Kotlin compiler, PMD, a formatter -
resolve as ordinary dependencies in their own group and are pinned like any other.

## Four questions

Each mechanism answers one question, and none answers another's:

| Question | Answered by | Runs |
| --- | --- | --- |
| May we use a dependency we cannot verify at all? | strict pinning | every build |
| Are these the exact bytes we vetted? | pin checksums | every build |
| Were the bytes we vetted the ones upstream released? | `@jenesis.signature` | `pin` only |
| What did we ship, and is it permitted or known-vulnerable? | SBOM, licence and vulnerability checks | every build |
| What can a dependency reach when it executes? | container isolation | opt-in |

The first two are *[Pinning](/tool/pinning/)*: a pin records an exact version and the `SHA-256` of the jar in
your own sources, every build re-hashes what it downloads, and a mismatch fails. Strict mode additionally
refuses any third-party coordinate without a checksum. That also blunts a tampered POM, since a dependency it
introduces arrives unpinned and is rejected - though signature verification addresses the POM directly.

The fourth is the *[supply-chain features](/tool/supply-chain/)* chapter, and the fifth is
*[Build performance & isolation](/tool/build-performance-and-isolation/)*, which confines what test code and
an artifact's `main` can reach. Pinning guarantees *what* runs; isolation limits what it can do.

That leaves the third question, which no hash can answer.

## <span id="provenance">Provenance: who produced the bytes</span>

A checksum is computed from whatever the repository served, so it proves an artifact has not changed since you
recorded it - not that what you recorded was genuine. An artifact swapped before your first `pin` is frozen as
an accepted pin just the same.

`@jenesis.signature` records the OpenPGP key that signed a dependency's artifact. The `pin` step fetches the
detached signature published beside the artifact, forks a local `gpg` to check it, and compares the **primary**
key fingerprint against your declarations before writing a checksum.

```java
/**
 * @jenesis.pin org.junit.jupiter/junit-jupiter 5.11.3 SHA-256/ac7578ef...
 * @jenesis.signature OpenPGP/FF6E2C001948C5F2F38B0CC385911F425EC61B51 org.junit.jupiter/* org.opentest4j/*
 */
```

The fingerprint comes first because one key normally signs many artifacts, and the tokens that follow use the
same grammar as every other `@jenesis` tag. A Maven token may end in `/*` to cover every artifact of one
groupId. `pin` never writes a wildcard itself - widening trust across a group is a decision you make by hand -
but once written, it adds no per-artifact line beneath it. A `pom.xml` carries the same declarations in a
project-level `<!--jenesis.signature ... -->` comment.

One vetted list can serve many modules. A declaration that names a lone
`signature-<name>.properties` reads `<algorithm>/<fingerprint>=<token>...` lines from a local file, found in
the configuration folder or wherever `-Djenesis.project.signatures` points:

```properties
# build.jenesis/signature-vendor.properties
OpenPGP/FF6E2C001948C5F2F38B0CC385911F425EC61B51 = org.apiguardian/* org.junit.jupiter/* org.opentest4j/*
OpenPGP/BE685132AFD2740D9095F9040CC0B712FEE75827 = org.assertj/*
```

`pin` keeps the reference and never expands it, and adds no line for a coordinate the list already covers. The
fingerprint is the properties key rather than the coordinate, so the same coordinate can appear under two keys
during a rotation.

<div class="warning">
  A list is only ever read from disk. There is no form that resolves one from a repository, because a list you
  had to download would itself need verifying - which is the problem the mechanism exists to solve. Obtain a
  list the way you would obtain a key: out of band, reviewed once, then committed.
</div>

A coordinate's **POM is verified with its artifact**, and must carry the same signer. POMs are read during
resolution but never pinned, because some servers re-serialise them and a byte checksum would mismatch for no
reason. A signature closes that gap directly, rather than leaving strict pinning to catch what a tampered POM
adds. The cost is that a repository which re-serialises POMs invalidates their signatures, so resolve from one
that serves the published bytes.

The line carries **no version**, and that is the point. One key signs every release it signs, so vetting a key
once covers every future release from that key, where a checksum covers exactly one file and every version bump
is a fresh, unvetted trust event. `-Djenesis.dependency.signature` chooses how much of the closure each `pin` run
checks and defaults to `none`: `unpinned` takes only coordinates that resolved without a checksum, `all`
every one, and `strict` additionally rejects an artifact publishing no signature. Verification is opt-in, so
a declaration alone does not switch it on - set the property in `jenesis.properties` as you would any other
project default.

An undeclared coordinate has its signer **recorded** for you to check before committing. A coordinate signed by
some other key **fails**, naming both fingerprints: a signature can be cryptographically perfect and still be
the wrong signer. A genuine key rotation is accepted by addition - list the new fingerprint alongside the old -
so no window exists in which nothing verifies.

<div class="note">
  Verification runs during <code>pin</code>, never during a build. Nothing is ever fetched on your behalf: a
  key gpg does not hold is reported as <code>NO_PUBKEY</code> and <code>pin</code> stops, because obtaining a
  key and checking it against the project's published location is the judgement the whole mechanism rests on.
  An ordinary build then enforces the pin with no gpg, no keys and no keyserver.
</div>

### Getting hold of a key

`pin` names the key it needs and stops. Find it somewhere the **project controls**: a fingerprint read from the
signature itself, or from whatever a keyserver returns, tells you which key signed - never whether it should
have. Best source first:

| Source | Look for |
| --- | --- |
| The project's own site, over HTTPS | a `KEYS` file; Apache publishes `downloads.apache.org/<project>/KEYS` |
| Its source repository | a committed `KEYS` file, or the release documentation |
| GitHub | `https://github.com/<user>.gpg` serves that account's public keys |
| A signed release tag | `git verify-tag v1.2.3` names the signing key |
| Web Key Directory | `gpg --locate-keys someone@example.org`, served from the project's own domain |

A keyserver is fine for fetching bytes and worthless as evidence, since anyone can upload a key under any name.
Inspect before importing, then compare against the source above:

```bash
gpg --list-packets some-artifact.jar.asc   # which key signed this
gpg --show-keys --with-fingerprint key.asc # what a key file contains, without importing it
gpg --import key.asc                       # only once the fingerprint matches
```

<div class="warning">
  <code>gpg --recv-keys</code> followed by <code>gpg --fingerprint</code> proves nothing: it reports the
  fingerprint of whatever was just downloaded, which is the thing you set out to check. The comparison has to
  be against a channel an attacker does not control.
</div>

## Where each one stops

Stating the limits plainly matters more than the guarantees:

- **A checksum** is trust-on-first-use without a signature beside it.
- **A signature** proves that the holder of a key asserted these bytes. It does not prove the artifact is
  benign, that it matches its published source, or that the key was not stolen.
- **An SBOM** describes what you shipped; it gates nothing.
- **A vulnerability scan** knows only what OSV has published, so it is silent on an advisory filed tomorrow and
  on one that was never filed.
- **A licence check** reads declarations, which can be wrong or absent.
- **Isolation** limits what code can reach, not whether it should be there.
- **`pin` itself** runs after a full build, because a dependency can be introduced by any step and the closure
  is only complete at the end. Tools have executed by the time their signatures are checked, so run `pin` on a
  clean checkout when that matters.

## A defensible posture

Nothing here needs a build script, and the layers are independent, so adopt them in the order that pays:

1. **Pin everything**, then build under `-Djenesis.dependency.pin=strict` in CI, so no unverified coordinate
   can enter unnoticed.
2. **Declare a key per upstream project** and let `pin` verify it, so the first acceptance of an artifact is a
   decision rather than a download.
3. **Refresh deliberately.** `-Djenesis.dependency.pin=ignore` re-blesses whatever the repository serves today,
   so run it on a trusted machine and review the diff. It also leaves every coordinate unpinned as it resolves,
   which means the operation that re-blesses the most is the one that verifies the most.
4. **Turn on the checks you will act on** - a licence policy, a vulnerability threshold - and keep the SBOM you
   already get.
5. **Containerise** the builds you do not trust.

What remains is the trust you extend deliberately: your JDK, the repository you resolve from at pin time, the
keys you vetted, and the gpg that checks them. Naming that list is the useful outcome; a build whose trusted set
cannot be written down has not been secured, only described.

## <span id="signing-key">The Jenesis signing key</span>

Jenesis artifacts published to Maven Central are signed with this key. Declare its **primary** fingerprint -
not the signing subkey, which is what `gpg --verify` prints first:

```
OpenPGP/B4AC8CDC141AF0AE468D16921DA784CCB5C46DD5
```

```java
/**
 * @jenesis.signature OpenPGP/B4AC8CDC141AF0AE468D16921DA784CCB5C46DD5 build.jenesis/*
 */
```

The same key is published as [`/KEYS`](/KEYS) on this site, as a `KEYS` file in each Jenesis repository, and
by the maintainer's GitHub account at [github.com/raphw.gpg](https://github.com/raphw.gpg). Import it, then
confirm the fingerprint matches the one above:

```bash
curl -O https://jenesis.build/KEYS
gpg --import KEYS
gpg --fingerprint B4AC8CDC141AF0AE468D16921DA784CCB5C46DD5
```

The block below carries two keys: the current signing key, RSA 4096 created on 7 November 2019, and the DSA key
that preceded it, revoked on 8 November 2019 and included so the succession can be checked.

```
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
+ua1Dys=
=66HO
-----END PGP PUBLIC KEY BLOCK-----
```

<div class="tip">
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-46-supply-chain-security">demo-46</a>
  proves three of these guarantees by getting each wrong on purpose: an unpinned dependency rejected by strict
  pinning, a wrong checksum rejected always, and a dependency signed by a key other than the declared one. It
  generates its own key and artifact, so it runs offline.
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-45-docker-isolation">demo-45</a> shows the
  isolation half. See <a href="/tool/demos/">Demos</a>.
</div>
