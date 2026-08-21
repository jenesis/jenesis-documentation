# Jenesis documentation

The published documentation site for the Jenesis product family (`src/` → jenesis.build). See README.md
for how to build, preview, and validate the site.
AGENTS.md is the working process for changing it: where each tool's source of truth lives, how a claim
is verified, the naming table, and the per-section notes.

## Editorial rules

- **Always write "Java Module System"; never "JPMS".** This applies everywhere reader-visible content
  lives: markdown chapters, `.njk` templates, and data files like `src/_data/demos.js` and the section
  taglines in `eleventy.config.js`. Capitalize the proper name ("the Java Module System", not "the Java
  module system"); generic back-references like "the module system" are fine.
- **Never present the Java Module System as a potential inconvenience, trade-off, or burden.** Its
  primary framing is: a Java-native build- and runtime-dependency descriptor that replaces the POM, with
  every further advantage of modularity coming for free. Avoid hedges like "where modularity helps" or
  "if you want modules"; accommodating non-modular code is openness to the existing ecosystem, never an
  escape hatch from modules.
- **Product names are strict.** repo.jenesis.build is "the Jenesis Module Index" (then "the module index");
  "Jenesis Repository" is only the artifact-repository product; `~/.jenesis` is "the local module repository";
  the GitHub project is "the `raphw/jenesis` repository"; the runner is "jpx" (lower case); "Jenesis Launcher"
  produces "a launcher jar" ("bundle" belongs to the build tool's `bundle.zip`).
- **Document only what ships today, verified against the tool's repository.** No "not yet", "planned",
  "coming soon", and no tier words ("free", "distribution", "enterprise"). If a route does not exist yet,
  describe the one that works and stay silent about the future.
- **The published docs never discuss this documentation project itself or how it is created.** No
  mentions of the site's tooling (Eleventy), the docs repo, authorship, or writing status (e.g.
  "already available", "coming soon", "this site"). Reader navigation is fine ("this chapter covers…",
  "What's in this section"); the docs as an artifact or project are not a topic. README.md is the only
  place that may describe the site and its build.
