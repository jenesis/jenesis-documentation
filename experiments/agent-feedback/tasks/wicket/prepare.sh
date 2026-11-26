#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions of task.env.
# Every change here is made to the project itself, so the Maven arm and the Jenesis arm get the same project.
set -euo pipefail

drop_module() { # drop_module <module>: takes one <module> line out of the root pom; its folder is in REMOVE
  grep -q "<module>$1</module>" pom.xml || { echo "prepare: pom.xml lists no module $1" >&2; exit 1; }
  sed -i "\|<module>$1</module>|d" pom.xml
  ! grep -q "<module>$1</module>" pom.xml
  [ ! -e "$1" ] || { echo "prepare: $1 is still there, REMOVE of task.env must delete it" >&2; exit 1; }
}

# Modules neither the bug nor its tests need, which one of the two tools cannot build as the other does:
#   wicket-examples (a war), archetypes/quickstart (a maven-archetype), wicket-user-guide (asciidoctor),
#   wicket-coverage (a JaCoCo aggregate): Maven plugins do all their work, Jenesis builds nothing of them;
#   testing/wicket-js-tests: no Java tests, a frontend plugin runs its JavaScript ones;
#   wicket-benchmarks: its benchmark list comes from an annotation processor named in a compiler plugin block;
#   wicket-velocity: `requires velocity.engine.core`, a module name Jenesis does not resolve;
#   testing/wicket-common-tests: depends on wicket-velocity;
#   wicket-migration: its OpenRewrite test finds its recipe jars by file name on the class path.
for module in wicket-examples archetypes/quickstart wicket-user-guide wicket-coverage testing/wicket-js-tests \
    wicket-benchmarks wicket-velocity testing/wicket-common-tests wicket-migration; do
  drop_module "$module"
done

# The JavaScript and CSS minifier of wicket-core and wicket-extensions: work only Maven would do, and it fails a
# second run that was not cleaned, as it minifies its own output in target/classes again.
for pom in wicket-core/pom.xml wicket-extensions/pom.xml; do
  python3 - "$pom" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
block = re.compile(r"\n[ \t]*<build>\s*<plugins>\s*<plugin>\s*<groupId>org\.primefaces\.extensions</groupId>\s*"
                   r"<artifactId>resources-optimizer-maven-plugin</artifactId>\s*</plugin>\s*</plugins>\s*</build>")
text, count = block.subn("", text)
if count != 1:
    sys.exit("prepare: %s holds %d resources-optimizer build blocks, expected 1" % (path, count))
open(path, "w", encoding="utf-8").write(text)
PY
  ! grep -q resources-optimizer "$pom"
done

# Checks and generated files of Maven plugins that Jenesis has no part in: the enforcer rules, the LICENSE, NOTICE
# and DEPENDENCIES files maven-remote-resources-plugin writes into every module, the japicmp comparison.
python3 - pom.xml <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = "\t\t<project.build.outputTimestamp>"
added = ("\t\t<enforcer.skip>true</enforcer.skip>\n"
         "\t\t<remoteresources.skip>true</remoteresources.skip>\n"
         "\t\t<japicmp.skip>true</japicmp.skip>\n")
if text.count(anchor) != 1 or "enforcer.skip" in text:
    sys.exit("prepare: pom.xml changed shape")
open(path, "w", encoding="utf-8").write(text.replace(anchor, added + anchor))
PY
grep -q '<enforcer.skip>true</enforcer.skip>' pom.xml
grep -q '<remoteresources.skip>true</remoteresources.skip>' pom.xml
grep -q '<japicmp.skip>true</japicmp.skip>' pom.xml
