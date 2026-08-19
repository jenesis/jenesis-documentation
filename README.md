# Jenesis documentation

![deploy](https://github.com/raphw/jenesis-documentation/actions/workflows/deploy.yml/badge.svg)

> ### [Jenesis](https://jenesis.build) - a modern Java build tool
> _Java-native config, plugin-free, with `module-info.java` treated as a feature, not an afterthought._

The documentation site for the Jenesis product family, published at **[jenesis.build](https://jenesis.build)**.

It is a static site built with [Eleventy](https://www.11ty.dev/): the landing page presents the tools, and each
tool has its own section with a left-hand menu of chapters. This repository holds **user** documentation only -
what somebody needs to use a tool. Contributor and internal material stays in each tool's own README.

## Working on it

```bash
npm install
npm run serve      # local preview with live reload
npm run build      # produce _site/
npm run validate   # check internal links, assets and fragments in _site/ (hyperlink)
npm run check      # build + validate (what CI runs)
```

Deployment is automatic: pushing to `main` builds the site, validates every internal link, and - only if that
passes - publishes to GitHub Pages. A broken link fails the deploy, so run `npm run check` before pushing.

## How the site is structured

- `src/index.njk` - the landing page (the project grid).
- `src/<section>/` - one folder per tool: `tool`, `jpx`, `launcher`, `modules`, `repository`. Each folder's
  `<section>.json` sets the shared layout and menu title.
- `src/_includes/` - the page shell (`base.njk`) and the documentation layout with the sidebar (`docs.njk`).
- `src/_data/` - `demos.js` (the demo index, kept in step with `raphw/jenesis`'s `demo/`) and `release.js`
  (which repository each landing-page tile takes its version from - the version itself is read from the
  GitHub API at page load, never committed, so a tile shows no version rather than a stale one).
- `src/assets/` - CSS (`pico.min.css`, `app.css`, `docs.css`), the logos and font, and the small theme and
  navigation scripts.

## Writing a chapter

A chapter is **one Markdown file** in a section folder with three lines of front matter:

```markdown
---
order: 3
title: Core concepts
description: Build steps, the build graph, and layouts.
---
```

`order` places it in the left menu; nothing else needs touching - the menu, the previous/next links and the
section index are derived from the files that exist.

## Documentation guidelines

These are the rules the existing chapters follow. They are what keeps the site readable, so a new chapter is
expected to hold to them.

**Write for a reader who knows nothing yet.** A section is educational, not a specification: it explains what
a feature is for before it explains how to use it. Assume only what earlier chapters established, and **never
refer forward** - if a chapter needs a concept, either it comes earlier or the concept belongs in this
chapter. Ordering the section is part of writing it.

**One page, a few minutes.** A chapter a reader will not finish is a chapter that does not work. Aim for
roughly 1,000-1,500 words; past about 2,000 the chapter is usually two chapters. Reference pages, which are
read by jumping rather than front to back, are the exception.

**Lead with the main idea, and put corner cases last.** Assume a reader stops after the first paragraph of
each section: that paragraph carries the point. Qualifications, platform quirks and failure modes come after
it, or in a callout at the end. The same holds for the page - the chapter's reason to exist is in its opening
lines.

**No walls of text.** Keep paragraphs under about 100 words and break a section with sub-headings, a table or
a list once it runs past ~300. Prefer a table over prose when the content is a set of options.

**Show, then explain.** Every feature gets a runnable example - the smallest one that works. Where a demo
exists in `raphw/jenesis`, link it at the end of the chapter so a reader can run the whole thing.

**User perspective only.** Describe what a tool does and how to use it, never how it is implemented
internally, and never the class that does it. Internals belong in the tool's README or its source.

**Never write about this site.** No mentions of Eleventy, the docs repository, authorship, or writing status
("coming soon", "already available", "this page"). Reader navigation ("this chapter covers…") is fine; the
documentation as a project is not a topic.

**Always write "Java Module System", never "JPMS"**, and capitalise it as the proper name. Generic
back-references ("the module system") are fine.

**Never frame the Java Module System as a trade-off or a burden.** It is a Java-native build- and
runtime-dependency descriptor that replaces the POM, with every further advantage of modularity coming for
free. Accommodating non-modular code is openness to the existing ecosystem, never an escape hatch from
modules.

## Visual elements

The site is deliberately plain: prose, code, tables, and three callouts. There are **no diagrams** - a reader
who wants the mechanism is better served by an example than by a picture of one - and no screenshots, which go
stale.

**Callouts** are a `<div>` with one of three classes, and each has a job:

```html
<div class="note">Context a reader needs but that would interrupt the sentence.</div>
<div class="tip">A shortcut, a recommendation, or the demos that exercise the chapter.</div>
<div class="warning">A trap: something that fails, is refused, or is not what it looks like.</div>
```

Use one where it earns its place - a chapter with a callout after every paragraph has none that stand out. A
closing `tip` linking the relevant demos is the convention at the end of a chapter.

**Code blocks** carry the language (` ```bash `, ` ```java `, ` ```properties `, ` ```xml `) and show the
smallest complete thing that runs. **Tables** carry option sets: a key, its default, and what it does.

## Colour scheme

The palette is the Jenesis brand kit, shared with the Jenesis Repository console (`app.css` is the same file in
both projects, so a change here belongs there too):

| Token | Value | Used for |
|---|---|---|
| `--app-brand-ink` | `#26221C` | Text and dark surfaces; the hover colour in light theme. |
| `--app-brand-amber` | `#C97E2C` | The accent - links and active states in dark theme, and the logo mark in both. |
| `--app-brand-cream` | `#F7F3EC` | Light surfaces, and the inverse of the brand colour. |
| `--app-brand-rust` | `#9A5A1B` | The accent in light theme, where amber would not reach AA contrast. |

Those feed Pico's `--pico-primary*` variables, so links, buttons and focus rings carry the brand without any
page setting a colour itself. Both themes are defined: light on `:root`, dark under `[data-theme="dark"]` and
under `prefers-color-scheme: dark`, so the site follows the OS unless a reader picks a theme.

The callouts reuse the semantic status palette rather than the brand - info blue for `note`, pass green for
`tip`, warn amber for `warning` - each with a light and a dark value chosen for AA contrast.

Headings and the product name use **Archivo ExtraBold** (`src/assets/fonts/`); everything else uses Pico's
default stack. Each section has a logo and a lockup in `src/assets/logos/` and `src/assets/lockups/`, in a
light and a dark variant that swap with the theme.

Never hard-code a colour, a font size or a spacing value in a page. Everything is a token on the scales in
`app.css`; if something is missing, add a token rather than a literal.

## License

Apache License 2.0.
