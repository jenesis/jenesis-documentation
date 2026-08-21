---
order: 3
title: Reports
description: Browsing what is modular - the coverage summary, the per-year and bleeding-edge "top modules" reports, and the ownership drift report.
---

The service in the [previous chapter](/modules/resolving/) answers one name at a time. Alongside it, the
Jenesis Module Index publishes a handful of **human-readable reports** so you can browse the whole picture
instead. They show how much of Maven Central is modular, which of the most-used libraries ship a module,
and where a module name is claimed by more than one publisher.

The reports live in the [`raphw/jenesis-modules`](https://github.com/raphw/jenesis-modules) repository
under `data/`, are regenerated **once a day**, and each states the date it was generated for. The front
door is the **module summary**, which links the top-modules reports; the drift report stands on its own.

## The module summary

[`SUMMARY.md`](https://github.com/raphw/jenesis-modules/blob/main/data/SUMMARY.md) is the coverage report
for all of Maven Central. Its opening **Totals** table is the headline. In a recent crawl it counted about
**18 million** artifacts scanned, of which about **1.65 million** are modular - roughly **360 000** named
and **1.3 million** automatic - spread across roughly **41 000** distinct module names and **5 300**
publishing groupIds.

Two terms recur throughout, and the split matters:

- A **named** module carries a real `module-info.class` - the publisher wrote a `module-info.java`.
- An **automatic** module only sets `Automatic-Module-Name` in its manifest - a name, but no module
  descriptor.

Below the totals, the summary breaks the index down further. It reports the resolved index size,
named-versus-automatic counts, and how often a declared `module-info` version agrees with the Maven
version. It then shows monthly publication activity, naming patterns, and top-N tables such as modules by
version count and groupIds by module count.

<div class="note">
  Unless a section is explicitly labelled <em>audit</em> or <em>history</em>, every number in the summary
  describes the <strong>canonical</strong> view - the resolved owner of each name. Shaded copies and other
  non-authoritative claims on a name do not inflate the counts.
</div>

## Top modules by year

Coverage across the whole index understates what you actually meet in practice, because most of Maven
Central is a long tail of artifacts almost nothing depends on. The **top-modules** reports fix that. Each
ranks the 1000 **most downloaded** artifacts of a given year and shows how many of them ship a module.
There is one report per year - [2019](https://github.com/raphw/jenesis-modules/blob/main/data/top/2019.md)
through [2025](https://github.com/raphw/jenesis-modules/blob/main/data/top/2025.md) - so you can watch
adoption move over time.

Each report opens with two summary tables, **by artifact** and **by groupId**, counted in three columns:

| Column | Covers |
| --- | --- |
| **All listed** | All 1000 ranked artifacts. |
| **Libraries** | Excludes rows that cannot reflect module adoption - Maven's own build tooling, POM-only parents and BOMs, and hand-listed placeholders. |
| **Maintained** | The libraries that also had a release in the report window, dropping the dormant and deserted ones. |

Then comes the per-artifact detail table, one row per ranked artifact:

| Column | Shows |
| --- | --- |
| Rank and coordinate | The artifact's position in the download ranking and its `groupId:artifactId`. |
| Module | The module name it carries, with a kind symbol (below). Blank when the latest version carries no module, even if an older one did. |
| Last publication | The date of the most recent release. |
| Ages | How old the artifact and its module are, in years. |
| Latest versions | The newest artifact version and the newest module version. |
| Releases | How many releases the artifact and the module have had. |

The symbols in that table:

| Symbol | Meaning |
| --- | --- |
| ⚙️ | An **automatic** module (manifest name only). |
| 🏷️ | A **named** module with no declared `module-info` version. |
| ✳️ | A **named** module that declares a `module-info` version. |
| ⚠️ | **Dormant** - no release in the report window, but one within the last three years. |
| 🚩 | **Deserted** - no release in the last three years. |
| ~~struck through~~ | A row excluded from the *Libraries* column (build tooling, a POM-only aggregator, or a placeholder). |

## The bleeding-edge report

[`BLEEDING.md`](https://github.com/raphw/jenesis-modules/blob/main/data/top/BLEEDING.md) is the same
report pointed at **now** rather than at a past year end. It takes the most recent popularity list and
assesses it against current data: the module columns describe each artifact's latest version as it stands
today, and the ⚠️ / 🚩 activity flags use rolling 12- and 36-month windows. Read the per-year reports for
the trend; read this one for where modularisation stands right now.

## The drift report

A module name is not owned by anyone on Maven Central. It is just a string a jar carries, and unrelated
artifacts routinely declare the same one. The
[**drift report**](https://github.com/raphw/jenesis-modules/blob/main/data/DRIFTERS.md) lists every module
name published by **more than one groupId** whose ownership has not been fully decided - that is,
whose `owners.tsv` does not mark every publisher as `allowed` or `rejected`.

It opens with a table counting the drifters by category:

| Category | What the collision looks like |
| --- | --- |
| `migration` | A groupId rename or relocation: the old coordinate went dormant and a newer one took over. |
| `fork` | A second, cross-organisation coordinate publishes the name while the original is still active. |
| `republisher` | The earliest publisher of the name is a repackager, and the natural owner also publishes it - so the resolved owner would change. |
| `shaded` | The natural owner already resolves; other coordinates merely bundle a copy under the same name. |
| `explicit-rules` | Names a hand-curated rule assigns to a fixed owner, regardless of the heuristic. |
| `tld-dropped`, `two-segments` | Names whose prefix is the owner's groupId with its first one or two segments dropped (`org.example.foo` publishing `example.foo`). |
| `unclassified` | Everything that fits none of the above. |

Each category then lists its modules with a per-groupId timeline: whether that groupId is `allowed`,
`rejected`, or still undecided, which one is the **current owner**, and each publisher's version range and
activity.

For an operator curating the index, this is the to-do list: each undecided name is settled by writing its
publishers into an ownership policy, as [Crawling it yourself](/modules/crawling/) shows. As a
**consumer**, read it the other way round. A name on this list has more than one party in play, so it is
exactly the kind of dependency worth pinning by its full coordinate.

<div class="warning">
  A module name alone is never an authoritative identifier. When a name appears in the drift report - or
  any time you resolve directly against the index files - pin the <code>(groupId, artifactId)</code> you
  expect rather than trusting the name on its own.
</div>
