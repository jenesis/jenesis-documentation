#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions of task.env.
# Every change here is made to the project itself, so the Maven arm and the Jenesis arm get the same project.
set -euo pipefail

drop_module() { # drop_module <pom> <module>: takes one <module> line out of a pom
  grep -q "<module>$2</module>" "$1" || { echo "prepare: $1 lists no module $2" >&2; exit 1; }
  sed -i "\|<module>$2</module>|d" "$1"
  ! grep -q "<module>$2</module>" "$1"
}

# Modules that need a Maven plugin's output, and the modules that depend on them (their folders are in REMOVE):
# jakarta/* are jars the Eclipse transformer plugin fills; velocity, tiles and config-browser compile against them;
# the apps are wars (and boot-hello an antrun/shade build); assembly packs the distribution.
drop_module pom.xml jakarta
drop_module pom.xml apps
drop_module pom.xml assembly
drop_module plugins/pom.xml velocity
drop_module plugins/pom.xml tiles
drop_module plugins/pom.xml config-browser
drop_module plugins/pom.xml cdi
drop_module plugins/pom.xml jasperreports7
for gone in jakarta apps assembly plugins/velocity plugins/tiles plugins/config-browser plugins/cdi plugins/jasperreports7; do
  [ ! -e "$gone" ] || { echo "prepare: $gone is still there, REMOVE of task.env must delete it" >&2; exit 1; }
done

# A JavaScript linter run by a Maven plugin in core: work only Maven would do.
python3 - core/pom.xml <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
block = re.compile(r"\n[ \t]*<plugin>\s*<groupId>com\.cj\.jshintmojo</groupId>.*?</plugin>", re.S)
text, count = block.subn("", text)
if count != 1:
    sys.exit("prepare: core/pom.xml holds %d jshint plugin blocks, expected 1" % count)
open(path, "w", encoding="utf-8").write(text)
PY
! grep -q jshint core/pom.xml

# The two test dependencies the tests of the bean-validation plugin use (spring-test's servlet mocks).
python3 - plugins/bean-validation/pom.xml <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = """            <artifactId>jakarta.activation-api</artifactId>
            <scope>test</scope>
        </dependency>
"""
added = """        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-web</artifactId>
            <scope>test</scope>
        </dependency>
"""
if text.count(anchor) != 1 or "spring-test" in text:
    sys.exit("prepare: plugins/bean-validation/pom.xml changed shape")
open(path, "w", encoding="utf-8").write(text.replace(anchor, anchor + added))
PY
grep -q '<artifactId>spring-test</artifactId>' plugins/bean-validation/pom.xml
grep -q '<artifactId>spring-web</artifactId>' plugins/bean-validation/pom.xml
