---
order: 13
title: The command line
description: Operating Jenesis Repository from a terminal or a script with the jenrepo command - installing it, signing in, how its help follows the console, JSON output, watching long work, and what its exit codes mean.
---

Everything the console does can also be done from a terminal with **`jenrepo`**, the command-line client. It is
a client of the server's API: each command is a call to the same API the console and every script use, so a
command reaches exactly what the console reaches and needs no JSON written by hand. It suits an operator at a
terminal, a CI job, and a program driving the repository with no browser at all.

## Installing it

`jenrepo` is installed on the machine you work from, not on the server - the server image does not carry it. It
runs on Java 25 or newer, and a package manager installs it as a command of its own:

```bash
brew install jenesis/tap/jenrepo                                                              # Homebrew
scoop bucket add jenesis https://github.com/jenesis/scoop-bucket && scoop install jenrepo     # Scoop
mise use packslip:jenesis/jenesis-repository/jenrepo                                          # mise

jenrepo help
```

Each release of Jenesis Repository also carries the command as a single launcher jar, `jenrepo-<version>.jar`,
which runs anywhere Java 25 does with `java -jar`.

## Signing in

A session is the server's address and a key, stored once and used by every later command:

```bash
jenrepo login https://repo.example.com --key "$KEY"
jenrepo whoami
jenrepo logout
```

Without `--key`, `login` asks for the key without echoing it; left blank, the session is anonymous and reaches
what the deployment serves without a key. The session is kept under `~/.jenesis`, or under the folder
`JENREPO_CLI_HOME` names. The key is an ordinary one, issued under **Access → Credentials**, and the commands it
may run are the ones its grants allow - a **deploy** key publishes and reads, and managing the deployment takes a
key of the operator tenant with the manage rights, as [Access](/repository/access/) describes.

A command that names a repository names one of the key's tenant; another tenant's is written `<tenant>/<repo>`.

## Finding a command

`jenrepo help` lists every command under the same headings the console uses, in the console's order, so a page you
know in the console has its command under the same heading:

| Heading | Among its commands |
| --- | --- |
| **Session** | `login`, `logout`, `whoami` |
| **Contents** | `browse`, `search`, `assets`, `deploy`, `import`, `staging`, `index` |
| **Review** | `quarantine` |
| **Risk** | `vulnerabilities`, `findings`, `health` |
| **Provenance** | `signers`, `signature`, `origin` |
| **Lifecycle** | `retention`, `cleanup`, `pins`, `lifecycle`, `webhook`, `export`, `forget-ecosystem` |
| **Build cache** | `projects` |
| **Access** | `credentials`, `members`, `groups`, `roles`, `trusts`, `policy`, `audit`, `keylogin` |
| **Operations** | `metrics`, `posture`, `caches`, `walks`, `consistency`, `logs` |
| **Settings** | `settings`, `setup`, `tenants`, `repos`, `upstreams`, `limits`, `capabilities`, `spi`, `config`, `purge` |

`jenrepo help <command>` shows every form a command takes, and `jenrepo capabilities` says what this deployment
carries - which formats, modules and features - so a command for something it lacks is known in advance. A command
with no action reads, and changing something takes an action word:

```bash
jenrepo repos create libraries maven "Internal libraries" --set keep-last=20
jenrepo quarantine libraries                      # the review queue, with each held path
jenrepo quarantine release libraries <path>       # release one, by the path the queue lists
jenrepo repos settings libraries set routing "writable fallback https://repo1.maven.org/maven2/"
jenrepo projects create my_project --set project-size=10737418240
jenrepo walks run
```

`jenrepo skill` prints a briefing for a program that has not used the tool before: what it is, how a session
works, what the exit codes mean, and which commands delete what cannot be recovered.

## Output for scripts

Without options, a command prints one record per line in columns, with `-` where a value is absent. With
`--json`, what it prints on standard output is exactly one JSON value - the server's own answer, with every field
the API returns:

- a command that makes several calls prints an array of their answers;
- an answer that is not JSON, such as a PEM key or a CSV file, arrives as `{"contentType":…,"body":…}`;
- a change the server answers with no body prints `{"ok":true}`;
- an error is JSON too, `{"error":…,"remedy":…,"exit":N}`, and goes to standard error, as every message does.

## Watching long work

A command that starts work in the background - an import, an export, a rescan, a walk of the store - returns as
soon as the server has accepted it, and never holds the connection open. Add `--refresh` to watch it instead: the
command prints the state again on an interval until the work finishes, then exits with the code that outcome
deserves. The interval suits what is watched, or is given outright as `--refresh=10s`:

```bash
jenrepo export libraries --url https://other.example.com/repository/releases/libraries/ --token "$TOKEN"
jenrepo export status libraries d4e5f6… --refresh
```

Under `--json`, a watching command still prints one value - the last state.

## Exit codes

| Code | Means |
| --- | --- |
| `0` | It worked. |
| `1` | The server refused, or could not be reached - the message says which. |
| `2` | The command line was wrong: an unknown command or a missing argument. |
| `3` | This deployment does not offer what was asked: the module behind it is not installed, or is switched off. |

Code `3` is worth handling on its own. The server answers `404` both for a feature it does not carry and for a
thing that does not exist, so on a `404` the client asks the deployment which of the two happened and says so -
naming the setting that switches a feature back on where it is only switched off. Retrying does not change it.

<div class="warning">
  Two commands remove data that cannot be recovered: <code>quarantine discard</code>, which drops a held artifact,
  and <code>purge &lt;module&gt; --delete</code>, which reclaims the stored data of a removed module. The deletions
  that <code>repos delete</code>, <code>projects delete</code> and <code>tenants delete</code> make ask you to type
  the name first, unless <code>--yes</code> is given. <code>purge</code> without <code>--delete</code> and
  <code>cleanup plan</code> only report what would happen.
</div>
