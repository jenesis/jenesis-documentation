# AGENTS.md

The published documentation for the Jenesis tools (`src/` → jenesis.build). This file is how a change to it is
made: where the facts come from, how a claim is verified, what the site says and does not say, and how a
change is checked before it lands. `CLAUDE.md` carries the short editorial rules and `README.md` the site's
build and the chapter-writing guidelines; both apply in full.

## Where the facts come from

Each section documents one tool, and every factual claim in it - a command, a flag, a property key, a default,
a URL shape, a file name, a behaviour - is checked against that tool's source before it is written. Not against
memory, not against another chapter, and not against a README, which can drift as well. Clone the tool
repositories next to this one; the paths below are relative to such a checkout.

| Section | Tool | Repository | Where to look | How to verify |
|---|---|---|---|---|
| `src/tool/` | Jenesis, the build tool | [raphw/jenesis](https://github.com/raphw/jenesis) | `sources/build/jenesis/**`, `demo/**` (one README per demo), `install.sh`, `jreleaser.yml`, `sdk/` | `grep -rn` over `sources/`; run a demo with `java build/jenesis/Project.java`; the tool's own `help` output |
| `src/jpx/` | jpx, the module runner | [raphw/jenesis](https://github.com/raphw/jenesis) | `sources/build/jenesis/Jpx.java`, `sources/build/jenesis/docker/`, `sdk/jpx/`, `demo/demo-46-jpx` | `java build/jenesis/Jpx.java <target>` from a project that carries `build/jenesis/` |
| `src/launcher/` | Jenesis Launcher | [raphw/jenesis-launcher](https://github.com/raphw/jenesis-launcher) | `sources/build/jenesis/launcher/**`; what the build writes into a jar is `sources/build/jenesis/step/Launcher.java` in raphw/jenesis | `demo-05` and `demo-06` ship a `build/DemoLauncher.java` |
| `src/modules/` | the Jenesis Module Index | [raphw/jenesis-modules](https://github.com/raphw/jenesis-modules) | `worker/index.js` (the service), `sources/build/jenesis/crawler/**`, `data/**`, `.github/workflows/` (schedules) | `curl -sI https://repo.jenesis.build/...` - the live service answers |
| `src/repository/` | Jenesis Repository | [raphw/jenesis-repository](https://github.com/raphw/jenesis-repository) | `source/**`, `test/**`, `Dockerfile`, `source/bundle/module-info.java`, each module's `application.properties`, `RepositoryProperties.java` | `java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java`, then `curl` against it |

What is not in those repositories is not documented. A capability has to be findable in the tool's source
tree, on its current default branch, before a chapter describes it.

## The working loop for a change

1. **Read the chapter in full**, then read the code behind every sentence you will touch. For a larger review,
   one verification pass per section, each listing the claims it checked and where, has worked well.
2. **Run what can be run.** A command in the docs is a command you executed: a demo, the repository server
   started from source, a `curl` against the module index. Property semantics are checked in code rather than
   assumed - some keys are read by presence (`jenesis.test.skip` skips even when set to `false`), others need
   an explicit `=true` (`jenesis.test.force`).
3. **Write only what you confirmed.** Anything you could not confirm is left out, or reported to the maintainer
   as unverified - never written with a hedge. Numbers that go stale (statistics, version numbers) are rounded
   or omitted.
4. **A gap in a tool is not closed in the docs.** When the code cannot do what a chapter needs, describe what
   works today, plainly, and raise the gap with the maintainer. The docs never promise a route that does not
   exist.
5. **Check the whole site**, not only the chapter: a concept carries one name across sections (see Naming), a
   property documented in a chapter also appears in that section's reference table, `src/_data/demos.js`
   matches the `demo/` folder of raphw/jenesis, and the landing page (`src/index.njk` and the taglines in
   `eleventy.config.js`) claims nothing a chapter contradicts.
6. `npm run check` builds the site and validates every internal link. It must pass before a push; the deploy
   runs only when it does.

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
- **The Java Module System** is described as what it is for these tools: the Java-native build- and
  runtime-dependency descriptor. It is not framed as a cost or a trade-off, and support for non-modular code is
  described as openness to the existing ecosystem.

## Naming

| Thing | Write | Not |
|---|---|---|
| repo.jenesis.build and its data | **the Jenesis Module Index**, then "the module index" | catalogue (as a name), module repository, mirror of Maven Central, the worker |
| the artifact-repository product | **Jenesis Repository** | the registry, the artifact manager (as a name) |
| `~/.jenesis` | the local module repository (`~/.jenesis`) | the Jenesis repository |
| raphw/jenesis on GitHub | the `raphw/jenesis` repository | the Jenesis repository |
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
derive from it. Callouts are `<div class="note|tip|warning">`; a closing `tip` links the demos that exercise
the chapter. No diagrams, no screenshots.

## Section notes

- **Tool.** Staged paths carry an `output/` segment and the module's build identity (`module`,
  `module-sources`), not its name. Demo links are `https://github.com/raphw/jenesis/tree/main/demo/<slug>`;
  every demo folder is in `demos.js` and vice versa. The reference tables follow `Project.java`,
  `BuildExecutor.Configuration` and the property reads in the step classes - a property added to the tool is
  added to the reference and mentioned where a reader would look for it.
- **jpx.** Its API is public (`build.jenesis.Jpx` in `build.jenesis:build.jenesis` on Maven Central) and every
  signature shown is checked against `Jpx.java`. A `--docker` run with a named image is not hardened and
  reuses the host JDK.
- **Launcher.** The build writes `mainClass`, `mainModule`, `classpath` and `Main-Class`, nothing else; the
  other descriptor keys and manifest attributes are launcher capabilities for jars assembled by other means.
  Subfolder names are URL-encoded coordinates; the application's own classes sit under `classes.jar/`.
- **Module index.** Every URL needs the trailing file segment (`/module/<name>/<name>.jar`); `/module/`,
  `/sources/` and `/documentation/` serve named modules only, `/artifact/` also automatic ones; an unknown
  version answers a best-effort 302 with `X-Jenesis-BestEffort: true`. The service is not a Maven
  `<repository>` URL.
- **Repository.** The launchable module is `source/bundle` (`AllInOne`; the console is `…bundle.Console` on
  port 8081, a separate process). Settings are Spring Boot settings bound from `jenreg.*` (`JENREG_*`, `-D`,
  `allinone.properties`, profiles). Nothing is proxied until `jenreg.proxy.<format>` is set; keys are enforced
  by default and the first one comes from `jenreg.bootstrap-key`; a key is read from `Jenesis-Repository-Key`
  or from `Authorization` (bearer, bare, or as a Basic password). **The server links to the docs**: every
  security and consistency advisory carries `https://jenesis.build/repository/observability/#<advisory id>`,
  so each id in `SecurityPosture.java` and `NodeDivergenceAdvisor.java` needs a matching `<span id="…">`
  anchor in `src/repository/observability.md`. Adding an advisory means adding its row and anchor.

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
