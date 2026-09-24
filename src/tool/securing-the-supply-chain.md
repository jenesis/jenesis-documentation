---
order: 12
title: Securing the supply chain
description: The reasoning behind Jenesis's supply-chain features - which attack each one answers, where each one stops, and how pinning, signatures, isolation and the compliance checks compose into a defensible build.
---

A build runs code written by people you have never met: every dependency you ship, and every tool that
compiles, checks and packages it. Any of them can be compromised, through a hijacked release, a swapped
artifact or a tool that alters what it writes. This chapter looks at those attacks, which mechanism answers
each one, where each one stops, and how they combine into a build you can defend. Along the way it shows how
to declare who signed a dependency, so that a jar is checked against its publisher as well as its checksum.

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

`build.jenesis` requires `jdk.compiler` and `java.xml`, two modules every JDK ships, and nothing else. There
is no third-party library anywhere in the engine. It ships as plain Java source under `build/jenesis/` in your own repository
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
| Were the bytes we vetted the ones upstream released? | `@jenesis.signature`, naming a key or an identity | every download, opt-in |
| What did we ship, and is it permitted or known-vulnerable? | SBOM, licence and vulnerability checks | every build |
| What can a dependency reach when it executes? | container isolation | opt-in |

The first two are *[Pinning](/tool/pinning/)*: a pin records an exact version and the `SHA-256` of the jar in
your own sources, every build re-hashes what it downloads, and a mismatch fails. Strict mode additionally
refuses any third-party coordinate without a checksum. That also blunts a tampered POM, since a dependency it
introduces arrives unpinned and is rejected - though signature verification addresses the POM directly.

The fourth is the *[supply-chain features](/tool/supply-chain/)* chapter, and the fifth is
*[Build performance & isolation](/tool/build-performance-and-isolation/)*, which confines what test code and
an artifact's `main` can reach. Pinning guarantees *what* runs; isolation limits what it can do.

That leaves the third question, which no hash can answer. A pin has to be written first, by a run with
nothing committed to check against. That run records whatever the repository serves at that moment, and
from then on those bytes are the definition of correct, so an artifact swapped before it goes unnoticed.
What follows is the mechanism that checks those bytes against their publisher.

## Provenance: who produced the bytes

A checksum proves an artifact has not changed since you recorded it - not that what you recorded was genuine.
An artifact swapped before your first `pin` is frozen as an accepted pin just the same.

`@jenesis.signature` says who produced it, as an **OpenPGP key** or as a **Sigstore identity** nobody keeps a
key for at all. Naming a key, the
declaration is the fingerprint that signs a dependency's artifacts. Right after a download, Jenesis fetches
the detached signature published beside it, forks `gpgv`, and compares the **primary** key fingerprint against
your declarations:

```java
/**
 * @jenesis.pin org.junit.jupiter/junit-jupiter 5.11.3 SHA-256/ac7578ef...
 * @jenesis.signature OpenPGP/FF6E2C001948C5F2F38B0CC385911F425EC61B51 org.junit.jupiter/* org.opentest4j/*
 */
```

The fingerprint comes first because one key normally signs many artifacts, and a Maven token may end in `/*`
to cover a whole groupId. **Nothing writes these lines.** A fingerprint is obtained out of band, checked
against the project's published `KEYS` and added by hand - a tool that filled it in from what it downloaded
would only record its own guess. The tag sits on `module-info.java`, as `@jenesis.bom` does; a `pom.xml` has
no place for a key.

One vetted list can serve many modules, as a local file of `<algorithm>/<fingerprint>=<token>...` lines:

```java
/**
 * @jenesis.signature signature-vendor.properties
 */
```

```properties
# build.jenesis/signature-vendor.properties
OpenPGP/FF6E2C001948C5F2F38B0CC385911F425EC61B51 = org.apiguardian/* org.junit.jupiter/* org.opentest4j/*
OpenPGP/BE685132AFD2740D9095F9040CC0B712FEE75827 = org.assertj/*
```

The fingerprint is the properties key rather than the coordinate, so one coordinate can sit under two keys
through a rotation. The file is found in `-Djenesis.project.signatures`, which defaults to the configuration
folders.

<div class="warning">
  A fingerprint is only ever read from your own sources, and a list only ever from disk: there is no form that
  resolves one from a repository, because a list you had to download would itself need verifying - the problem
  the mechanism exists to solve. Obtain a list the way you would obtain a key: out of band, from a place the
  project controls, such as its website, its source repository or its maintainers' GitHub accounts. Review it
  once, then commit it.
</div>

A coordinate's **POM is verified with its artifact** and must carry the same signer. POMs are read during
resolution but never pinned, because some servers re-serialise them and a byte checksum would mismatch for no
reason - so resolve from a repository that serves the published bytes.

The line carries **no version**, and that is the point: one key signs every release it signs, where a checksum
covers one file and every version bump is a fresh, unvetted trust event.
`-Djenesis.dependency.signature` chooses how much is checked and defaults to `none`. `declared` verifies every
coordinate a line covers; `strict` also rejects one that no line covers, or that publishes no signature.
`-Djenesis.print.signatures` names each dependency checked and the key that signed it, and each one nothing
covers - which is how you get from `declared` to `strict`. A coordinate signed by another key fails, naming
both fingerprints; a genuine rotation is accepted by adding the new fingerprint beside the old, so no window
exists in which nothing verifies.

### A coordinate that publishes no signature

Under `strict` a coordinate with no signature fails, and one such dependency otherwise costs you the whole
mode - which is the mode worth having, since the rest of the closure goes back to being taken on trust. An
`unsigned/` declaration says that this one was looked at, and its value says what to do if a signature turns
up after all:

| Value | An artifact that publishes no signature |
| --- | --- |
| `unsigned/missing` | is accepted, and **fails once a signature appears**, naming the fingerprint seen |
| `unsigned/ignored` | is accepted, signed or not, and never looked at |

`unsigned/missing` is the one to reach for: an upstream that starts signing is discovered on the next build
rather than quietly left unverified, and the failure tells you which fingerprint to put in its place. Both
are ordinary declarations - as narrow as the tokens they name, and sitting in the diff where a reviewer reads
them.

### A signing key that has since expired

Keys expire; the releases they signed do not change. An old artifact is commonly signed by a key that lapsed
years later, and where the keyservers publish no extended expiry there is nothing to update - so treating
every expired key as a failure would mean deleting the declaration, which verifies nothing at all.
`-Djenesis.openpgp.expiry` says what an expired signing key means:

| Value | An expired signing key |
| --- | --- |
| `ignored` | is accepted, whenever it signed |
| `signing` | is accepted for what it signed **before** it expired - the default |
| `current` | is always rejected, however old the signature |

The default reads the signature's date against the key's expiry, both of which `gpgv` reports while it
verifies, so nothing extra is fetched. A signature made *after* the key expired fails under `signing`, and so
does one whose expiry `gpgv` does not report - an expiry that cannot be established is refused rather than
assumed. Revocation is never affected: a revoked key fails under every value, because revocation says the key
should not have been trusted where expiry only says it is no longer current.
`-Djenesis.print.signatures` marks such a coordinate `[EXPIRED]` rather than `[VERIFIED]`, with both dates,
so the ones resting on an unmaintained key can be reviewed rather than passing silently.

<div class="note">
  A fingerprint carries no expiry, and neither does the <code>.asc</code>. The fingerprint hashes the public
  key, while the expiry is an assertion in the key's self-signature - so extending a key's expiry leaves your
  <code>@jenesis.signature</code> line untouched, and the expiry has to come from the keyring at the moment of
  verification.
</div>

Verification is part of the dependency step, so it covers every resolution a build performs - a module's own
closure, and equally the linter, formatter, compiler or test launcher a build module resolves for itself.
Switching it on re-runs that step alone, and fetched `.asc` files are cached beside the jars. It is
deliberately no part of `pin`, which records versions and checksums and never reads or writes a signature
line: a pin refresh re-blesses whatever the repository serves today, and the signature is the one check that
still has something to say while the checksums are being rewritten.

Verification forks `gpgv`, so **it has to be installed and on the `PATH`** of the machine that runs it; a
build that has not enabled verification needs none of this. Forking is the point - a Java OpenPGP library
would have to be resolved from the repository being verified, and a verifier downloaded on trust verifies
nothing. `-Djenesis.openpgp.command` names another binary: a plain name is looked up on the `PATH`, a value
with a path separator is used as a path.

`gpgv` is the verify-only half of GnuPG. It reads a keyring file and nothing else - no home directory, no
agent, no trust database, no import step - and **Jenesis builds that keyring** from the fingerprints your
declarations name, which is why `NO_PUBKEY` means *no line covers this signer* rather than *your keyring is
incomplete*.

### Where the keys come from

Each declared fingerprint is resolved through the repository registered under the algorithm the line names,
so `OpenPGP/<hex>` asks the repository registered as `OpenPGP`. By default that is an HKP client over
`-Djenesis.openpgp.uri`, which names key server roots, comma-separated and asked in order:

    jenesis.openpgp.uri = https://keyserver.ubuntu.com/, https://keys.openpgp.org/

A bare `@` in that list splices back what `OPENPGP_REPOSITORY_URI` names, or the two defaults when it names
nothing, and `@<name>` splices whatever `jenesis.<name>` or the environment variable `<name>` holds - so a
machine names its internal key server once and every project reads `jenesis.openpgp.uri = @corp, @`.

Both defaults are asked because neither is complete: a key published only on one is common enough to break a
build that names just the other. Ubuntu is asked first because keys.openpgp.org serves a key with its user
IDs stripped unless the owner has verified an address, and `gpgv` refuses a key that has none.

What is fetched is held in `-Djenesis.openpgp.local`, one file per fingerprint, and a populated folder with
an empty `jenesis.openpgp.uri` is the offline form - vendored keys, no network. It is a cache, not something
to commit: a fingerprint the folder already holds is served from it and no key server is asked, so a key
checked into the repository would be the key as it was on the day it was fetched, on every machine and every
clone, and a revocation published afterwards would never arrive. What a project checks in is the fingerprint;
deleting the folder, or the one file, is what makes the next build fetch the key again. Both settings take
`OPENPGP_REPOSITORY_URI` and `OPENPGP_REPOSITORY_LOCAL` from the environment, and a containerised build
forwards them the way it forwards the Maven and module repository settings. A key source that is not an HKP
server - a corporate key store, a git tree, a service of your own - is a different repository registered
under the same name, not a different URL in that list.

<div class="note">
  Fetching a key by fingerprint is not trust in the server. The comparison that decides the build is against
  the fingerprint <em>your declaration</em> names, and <code>gpgv</code> reports the primary key's fingerprint
  for whatever it was given, so a server can withhold a key or serve junk - it cannot serve one that passes.
  What is never fetched is the <em>fingerprint</em>: that is the judgement the mechanism rests on, and it
  comes from the project's published location, reviewed once, then committed. With verification unset, a
  build enforces the pin with no verifier, no keys and no key server at all.
</div>

### Getting hold of a key

The build names the key it needs and stops. Find it somewhere the **project controls**: a fingerprint read
from the signature itself, or from whatever a keyserver returns, tells you which key signed - never whether it
should have. Best source first:

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

{% demos 27 %}

## An identity instead of a key

Everything above rests on a maintainer keeping a private key for years, and on you finding its fingerprint
through a channel an attacker does not control. **Sigstore** is often more convenient: a release is signed
by the identity that published it, such as a project's release workflow, with no long-lived key for anyone to
keep or look up. Maven Central accepts Sigstore signatures as an option beside OpenPGP, though few projects
publish them yet, while OpenPGP signatures are everywhere.

For a coordinate whose repository publishes a `.sigstore.json` beside the artifact, the declaration names that
identity:

```java
/**
 * @jenesis.signature Sigstore/github.com/sigstore/protobuf-specs dev.sigstore/*
 */
```

Read against the certificate that signed that release, the parts are:

```
Sigstore / github.com / sigstore / protobuf-specs
   |           |           |           `- repository
   |           |           `- owner
   |           `- issuer token.actions.githubusercontent.com
   `- the bundle beside the artifact carries the material; nothing is fetched to check it

accepts  https://github.com/sigstore/protobuf-specs/.github/workflows/java-release.yml@refs/tags/release/java/v0.5.2
```

**The path is a prefix, and it narrows a segment at a time.** `Sigstore/github.com/sigstore` covers every
repository of one owner, the line above covers one repository, and a workflow file may follow to cover a
single workflow. A prefix ends at a `/` or an `@`, so a declaration for `protobuf-spec` never covers
`protobuf-specs`.

**The tag a release was built from is never written.** The identity above ends in
`@refs/tags/release/java/v0.5.2`, and that is the part that moves with every version. Stopping before it is
what lets one line cover every future release, the way a fingerprint does - the property that makes a
declaration worth writing once.

**The host also names the issuer** that must have authenticated the identity - itself, unless
`-Djenesis.sigstore.issuers` says otherwise, which today it does only for
`github.com=token.actions.githubusercontent.com`. Comparing the issuer is what stops a certificate from
another provider carrying a `github.com` identity. A host is written without a scheme, since an OpenID
Connect issuer is an `https` URL and nothing else.

A coordinate signed by some other identity **fails**, naming both sides, exactly as a wrong key does. The
signature can be perfect and the log entry genuine - a release built in a fork is both - and only the
comparison against your declaration sees it.

### Where a bundle is checked against

A bundle carries its own certificate and log entry, but something has to say which certificate authority and
which log are the real ones. Jenesis **carries that trust root as source**: the published root of the public
Sigstore instance, vendored into your project with the rest of the tool and reviewed in the same diff. A
project that adds a declaration needs nothing else, and no build downloads a trust root.

`-Djenesis.sigstore.uri` names another, and is the only way another is read - for a private Sigstore instance,
or a root that has rotated since the one you vendored. A log that was added after your copy was published is
reported as unknown rather than accepted, and the message names that property as the way past it.

### What this costs, and what it does not need

Verification happens in the same step and under the same `-Djenesis.dependency.signature` modes as a key:
`declared` checks every coordinate a line covers, `strict` additionally rejects one that no line covers or that
publishes nothing to check. Under `strict` a coordinate's **POM must carry a bundle from the same identity**,
closing the same gap the key form closes.

A coordinate covered only by an identity needs **no `gpg`, no keyring and no key server**: the check is JDK
cryptography in process, over a bundle the repository publishes. The certificate in that bundle is expired by
the time you read it, which is the design rather than a lapse - verification asks whether it was valid at the
moment the log recorded the signature, not whether it is valid today.

Both forms may cover one coordinate, and each is then verified against whatever that coordinate publishes, so
a project moving from one to the other declares both and neither is weakened. Which to use is decided by what
a repository publishes: a detached `.asc` is near-universal on Maven Central, while bundles are still the
exception, so an identity is an additional answer where one exists rather than a replacement.

{% demos 28 %}

## The one build a pin cannot protect

A pinned project is easy to reason about: the pins sit in your own sources, reviewed like any other change,
and every later build enforces them - whatever the repository serves must hash to what the pin says, or the
build fails, with no keys, no gpg and no network beyond the bytes themselves.

That holds for every build except the one that *writes* the pins. Initialising a project, or updating a
dependency, is the moment with nothing committed to check against: the resolver takes what the repository
serves, the pin records it, and whatever arrived becomes the definition of correct.

A checksum has nothing to say there - it is the thing being written. The signature does: the publisher's key,
applied to those bytes, checked against a fingerprint you vetted once. That is why verification runs during
resolution rather than during the rewrite. A key is also cheap to keep, because it does not move with the
version: a routine bump costs nothing, and a version signed by somebody else is precisely what you are told.

So the strongest posture is not a stricter everyday build - an ordinary build already enforces the pins. It is
to make the pin-writing run the careful one, on a machine and against a repository you trust:

```bash
java -Djenesis.dependency.pin=ignore \
     -Djenesis.dependency.signature=strict \
     build/jenesis/Make.java pin
```

Both flags are needed and neither is a default: `@jenesis.signature` lines verify nothing on their own, and
`jenesis.dependency.signature` stays `none` until something sets it, which is what keeps every ordinary build
free of gpg.

That machine needs two things Jenesis cannot supply: a JDK, and a `gpg` on the `PATH` that you trust -
fetching either from the network would defeat the exercise. `pin` runs after a full build, so the resolution
that feeds the rewrite is the verified one, and `strict` refuses any coordinate no key vouches for. Review
the diff, commit it, and the pins carry that verdict to everyone who trusts your repository.

Getting there is the fiddly part, and `-Djenesis.print.signatures` under `declared` makes it tractable: it
names every coordinate no declaration covers, which is exactly the list `strict` would refuse.

{% demos 48 %}

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
- **A declaration** only covers what it names. A coordinate no line mentions is verified by nobody under
  `declared`; only `strict` turns that silence into a failure.
- **`pin` itself** runs after a full build, because a dependency can be introduced by any step and the closure
  is only complete at the end, so a pin rewrite is not the moment anything is checked.

{% demos 26 %}

## A defensible posture

Nothing here needs a build script, and the layers are independent, so adopt them in the order that pays:

1. **Pin everything**, then build under `-Djenesis.dependency.pin=strict` in CI, so no unverified coordinate
   can enter unnoticed.
2. **Declare a key per upstream project** and build with `-Djenesis.dependency.signature=declared`, so the
   first acceptance of an artifact is a decision rather than a download. Move to `strict` once every external
   coordinate is covered.
3. **Refresh deliberately.** `-Djenesis.dependency.pin=ignore` re-blesses whatever the repository serves today,
   so run it on a trusted machine, with `-Djenesis.dependency.signature=strict`, and review the diff - see
   *[The one build a pin cannot protect](#the-one-build-a-pin-cannot-protect)*, which is the whole argument for why this run, rather
   than every run, is the one to harden.
4. **Turn on the checks you will act on** - a licence policy, a vulnerability threshold - and keep the SBOM you
   already get.
5. **Containerise** the builds you do not trust.

What remains is the trust you extend deliberately: your JDK, the repository you resolve from, the keys you
vetted, and the gpg that checks them. Naming that list is the useful outcome; a build whose trusted set
cannot be written down has not been secured, only described.

## The Jenesis signing key
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

[`/KEYS`](/KEYS) holds the RSA 4096 primary created on 7 November 2019, with the signing subkey that
released until September 2026 and the one that signs releases from now on. A copy exported before the newer
subkey existed verifies nothing signed with it, and reports an issuer it has never heard of - which is what
a refresh from any of the three sources above fixes. The primary fingerprint does not change, so nothing that
names it has to.
