# AGENTS.md

The published documentation for the Jenesis tools (`src/` → jenesis.build). This file is how a change to it is
made: where the facts come from, how a claim is verified, what the site says and does not say, and how a
change is checked before it lands. `README.md` describes the site's build and the chapter-writing
guidelines; it applies in full.

## Where the facts come from

Each section documents one tool, and every factual claim in it - a command, a flag, a property key, a default,
a URL shape, a file name, a behaviour - is checked against that tool's source before it is written. Not against
memory, not against another chapter, and not against a README, which can drift as well. Clone the tool
repositories next to this one; the paths below are relative to such a checkout.

| Section | Tool | Repository | Where to look | How to verify |
|---|---|---|---|---|
| `src/tool/` | Jenesis, the build tool | [jenesis/jenesis](https://github.com/jenesis/jenesis) | `sources/build/jenesis/**`, `demo/**` (one README per demo), `install.sh`, `jreleaser.yml`, `sdk/` | `grep -rn` over `sources/`; run a demo with `java build/jenesis/Project.java`; the tool's own `help` output |
| `src/jpx/` | jpx, the module runner | [jenesis/jenesis](https://github.com/jenesis/jenesis) | `sources/build/jenesis/Jpx.java`, `sources/build/jenesis/docker/`, `sdk/jpx/`, `demo/demo-65-jpx` | `java build/jenesis/Jpx.java <target>` from a project that carries `build/jenesis/` |
| `src/launcher/` | Jenesis Launcher | [jenesis/jenesis-launcher](https://github.com/jenesis/jenesis-launcher) | `sources/build/jenesis/launcher/**`; what the build writes into a jar is `sources/build/jenesis/step/Launcher.java` in jenesis/jenesis | `demo-05` and `demo-06` ship a `build/DemoLauncher.java` |
| `src/modules/` | the Jenesis Module Index | [jenesis/jenesis-modules](https://github.com/jenesis/jenesis-modules) | `worker/index.js` (the service), `sources/build/jenesis/crawler/**`, `data/**`, `.github/workflows/` (schedules) | `curl -sI https://repo.jenesis.build/...` - the live service answers |
| `src/repository/` | Jenesis Repository | [jenesis/jenesis-repository](https://github.com/jenesis/jenesis-repository) | `source/**`, `test/**`, `Dockerfile`, `source/bundle/module-info.java`, each module's `application.properties`, `RepositoryProperties.java` | `docker run jenesisbuild/jenesis-repository` (or a local build of it), then the console and the clients against it |

What is not in those repositories is not documented. A capability has to be findable in the tool's source
tree, on its current default branch, before a chapter describes it.

## The working loop for a change

1. **Read the chapter in full**, then read the code behind every sentence you will touch. For a larger review,
   one verification pass per section, each listing the claims it checked and where, has worked well.
2. **Run what can be run.** A command in the docs is a command you executed: a demo, the repository server
   started from source, a `curl` against the module index. Property semantics are checked in code rather than
   assumed. Every boolean key reads the same way: absent is the default, the key named with no value at all
   is `true`, `=true` and `=false` mean what they say, and any other value is refused.
3. **Write only what you confirmed.** Anything you could not confirm is left out, or reported to the maintainer
   as unverified - never written with a hedge. Numbers that go stale (statistics, version numbers) are rounded
   or omitted.
4. **A gap in a tool is not closed in the docs.** When the code cannot do what a chapter needs, describe what
   works today, plainly, and raise the gap with the maintainer. The docs never promise a route that does not
   exist.
5. **Check the whole site**, not only the chapter: a concept carries one name across sections (see Naming), a
   property documented in a chapter also appears in that section's reference table, `src/_data/demos.js`
   matches the `demo/` folder of jenesis/jenesis, and the landing page (`src/index.njk` and the taglines in
   `eleventy.config.js`) claims nothing a chapter contradicts.
6. `npm run check` builds the site and crawls it, validating every internal link and every `#fragment` on
   every page - not just the ones the landing page reaches. It must pass before a push; the deploy runs only
   when it does.

## What the site says

- **What ships today, verified.** Before describing an install channel, an image or an endpoint, read the
  tool's `jreleaser.yml`, `install.sh` and `Dockerfile`. When availability changes, the chapter changes; the
  site never says "not yet", "planned" or "coming soon".
- **User perspective only.** What a tool does and how to use it - never the class that does it, a method name,
  a source folder, or an internal interface as chapter structure. The exceptions are the public-API chapters
  (*Extending the build*, *Using jpx from Java*) and values a user sees, such as manifest attributes and
  property keys.
- **Plain description, no promotion.** A chapter states what a tool does and what it does not do, in the same
  tone. Comparisons with other tools are factual and fair; superlatives and claims that cannot be checked do
  not belong on the site.
- **Never the site itself.** No site tooling, no documentation repository, no authorship or writing status.
  Reader navigation ("this chapter covers", "the next chapter") is fine.
- **The Java Module System** is always written out and capitalised as the proper name - never the
  abbreviation, in chapters, templates and data files alike; generic back-references ("the module system")
  are fine. It is described as what it is for these tools: the Java-native build- and runtime-dependency
  descriptor. It is not framed as a cost or a trade-off, and support for non-modular code is described as
  openness to the existing ecosystem.

## Naming

| Thing | Write | Not |
|---|---|---|
| repo.jenesis.build and its data | **the Jenesis Module Index**, then "the module index" | catalogue (as a name), module repository, mirror of Maven Central, the worker |
| the artifact-repository product | **Jenesis Repository** | the registry, the artifact manager (as a name) |
| `~/.jenesis` | the local module repository (`~/.jenesis`) | the Jenesis repository |
| jenesis/jenesis on GitHub | the `jenesis/jenesis` repository | the Jenesis repository |
| the module runner | **jpx**, lower case even at a sentence start; section title "Jenesis jpx" | JPX, Jpx (the class is `Jpx.java`) |
| the executable-jar tool / its artifact | **Jenesis Launcher** / a launcher jar | bundle, bundler (the build tool's `bundle=true` owns "bundle") |
| `Project.java` | `Project.java`, the build | the launcher |
| build extensions | plugin; in Jenesis Repository, module or capability | plug-in |
| `build.jenesis/` | the configuration folder | configuration location, configuration directory |
| paths | class path, module path (two words in prose) | classpath (except the `classpath/` folder) |
| PIT | PIT (`pitest.properties`) | PiTest |

British spelling throughout (licence, behaviour, serialise, recognise); Java identifiers keep their own
spelling (`Serializable`). The house dash is a spaced hyphen (" - "); no em dashes.

## Voice and shape

Clear, direct and even-handed, for a reader who knows Java and is new to Jenesis. Lead every chapter and
section with what the reader can do, then how, then why; mechanism after use. Sentences around 20 words,
split past ~35, one dash-clause each; paragraphs under ~80 words; tables for option sets, lists for steps.
Never refer forward to a later chapter for something the current one needs. Chapters run 1,000-1,500 words;
reference pages may be longer.

Front matter is `order`, `title`, `description`; the menu, the previous/next links and the section index
derive from it. Callouts are `<div class="note|tip|warning">`. A section that a demo exercises ends with
`{% demos 18, 20 %}`, which renders one "Demo 18: Module alias" link per line from `demos.js`; every demo is
linked from at least one section. No diagrams, no screenshots.

**Every heading is an anchor, and its words are its id.** The build gives each `##` and `###` an `id` taken
from the heading's own text, lower case with one hyphen per run of anything else, so *Keeping a dependency
private* is `#keeping-a-dependency-private` and a reader who clicks the heading copies that link. Link to a
section by slugging its heading; nothing is written by hand and no heading carries a `<span id>`. Rewording a
heading therefore moves its anchor: change the wording and the links to it in the same pass. `npm run check`
catches a fragment with nothing behind it, so a stale link fails the build rather than the reader.

The one anchor still placed by hand is the advisory id (see Section notes), which sits on a table row rather
than a heading and must match the id the repository server emits, not the wording around it.

## Section notes

- **Tool.** Staged paths carry an `output/` segment and the module's build identity (`module`,
  `module-sources`), not its name. The demo lines that close a section come from the `demos` shortcode;
  every demo folder is in `demos.js` and vice versa. The reference tables follow `Project.java`,
  `BuildExecutor.Configuration` and the property reads in the step classes - a property added to the tool is
  added to the reference and mentioned where a reader would look for it.
- **jpx.** Its API is public (`build.jenesis.Jpx` in `build.jenesis:build.jenesis` on Maven Central) and every
  signature shown is checked against `Jpx.java`. A `--docker` run with a named image is not hardened and
  reuses the host JDK.
- **Launcher.** The build writes the descriptor keys `mainClass`, `mainModule` (modular only), `classpath`,
  `modulepath` (always, empty when nothing is modular) and, per module layer, `modulepath.<layer>` and
  `classpath.<layer>` (when non-empty), plus the manifest's `Main-Class` - nothing else; the other descriptor
  keys and manifest attributes are launcher capabilities for jars assembled by other means. A subfolder is
  named after the module its jar carries, or the URL-encoded coordinate for a jar that declares none; the
  application's own classes sit under `classes.jar/`.
- **Module index.** Every URL needs the trailing file segment (`/module/<name>/<name>.jar`); `/module/`,
  `/sources/` and `/documentation/` serve named modules only, `/artifact/` also automatic ones; an unknown
  version answers a best-effort 302 with `Jenesis-BestEffort: true`. The service is not a Maven
  `<repository>` URL.
- **Repository.** The section is written for someone running the published image
  (`jenesisbuild/jenesis-repository`) and follows the console: a chapter is organised by the console's sections
  and pages, and names them as the console does (**Access → Credentials**). Running from source gets one short
  chapter. The image is the launchable module `source/bundle`: repository, console and build cache in one process
  on port 8080. Settings are Spring Boot settings bound from `jenreg.*` (`JENREG_*`, `-D`, `bundle.properties`).
  Nothing is proxied until an upstream is named; keys are enforced by default, and the first console sign-in is
  the administrator key (`JENREG_KEY_LOGIN=true`, `JENREG_UI_ADMIN_KEY`). Verify a chapter by running the image
  and doing what it says, through the console and the clients. **The server links to the docs**: every security
  and consistency advisory carries `https://jenesis.build/repository/operations/#<advisory id>`, so each id in
  `SecurityPosture.java`, `TenantPosture.java` and `NodeDivergenceAdvisor.java` needs a matching
  `<span id="…">` anchor in the advisory table of `src/repository/operations.md`. Adding an advisory means
  adding its row and anchor.

## Landing page and shared files

`eleventy.config.js` holds the section titles and taglines, `src/index.njk` the landing cards,
`src/_data/release.js` the repositories whose latest release each tile shows. A tagline claims only what the
section's chapters verify. Logos and lockups under `src/assets/` are brand assets; the site renders the logos
only.

## Changing a tool from here

Sometimes the right fix is in a tool: a README that diverges from its code, a link a tool emits to a page that
must exist, a demo that pins an outdated version. Such a change goes into the tool's own repository, is built
and tested there (`java build/jenesis/Project.java`), and the docs are updated in the same pass. The tools pin
the build tool as the `.jenesis/upstream` git submodule; moving a pin is a checkout of the new commit in the
submodule, a build, and a commit of the submodule pointer.
