#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions of task.env.
# Every change here is made to the project itself, so the Maven arm and the Jenesis arm get the same project.
set -euo pipefail

for gone in byte-buddy byte-buddy-benchmark byte-buddy-android byte-buddy-android-test byte-buddy-maven-plugin \
    byte-buddy-gradle-plugin byte-buddy-fuzz; do
  [ ! -e "$gone" ] || { echo "prepare: $gone is still there, REMOVE of task.env must delete it" >&2; exit 1; }
done

python3 - <<'PY'
import re, sys, xml.dom.minidom

def edit(path, pattern, expected, replacement=""):
    text = open(path, encoding="utf-8").read()
    text, count = re.subn(pattern, replacement, text, flags=re.S)
    if count != expected:
        sys.exit("prepare: %s matched %d times in %s, expected %d" % (pattern[:60], count, path, expected))
    open(path, "w", encoding="utf-8").write(text)

# The reactor keeps the parent, byte-buddy-dep and byte-buddy-agent, which byte-buddy-dep's tests require. The
# shaded byte-buddy jar, the benchmarks, the Android modules, the Maven and Gradle plugins (built against the shaded
# jar) and the fuzzing harnesses (a profile of their own) leave it; their folders are in REMOVE.
original = """    <modules>
        <module>byte-buddy</module>
        <module>byte-buddy-dep</module>
        <module>byte-buddy-benchmark</module>
        <module>byte-buddy-agent</module>
        <module>byte-buddy-android</module>
        <module>byte-buddy-android-test</module>
        <module>byte-buddy-maven-plugin</module>
        <module>byte-buddy-gradle-plugin</module>
    </modules>
"""
reactor = """    <modules>
        <module>byte-buddy-dep</module>
        <module>byte-buddy-agent</module>
    </modules>
"""
text = open("pom.xml", encoding="utf-8").read()
if text.count(original) != 1:
    sys.exit("prepare: pom.xml lists other modules than expected")
open("pom.xml", "w", encoding="utf-8").write(text.replace(original, reactor))

# Byte Buddy compiles to Java 5 byte code by default and, through a profile per JDK that its version activates
# (java25-compatibility here), to Java 8 on newer JDKs; Jenesis compiles for the JDK it runs on. The levels become
# the JDK's own, 25, and the profiles that would lower them go, the Java 6 one with its module list.
edit("pom.xml", r"\n[ \t]*<!-- Runs the build with compatibility for Java \d+ JVMs\. -->\s*<profile>\s*"
     r"<id>java\d+-compatibility</id>.*?</profile>", 21)
for level in ("sourcecode.main.version", "sourcecode.test.version", "bytecode.main.version", "bytecode.test.version"):
    edit("pom.xml", r"\n {8}<%s>1\.[56]</%s>" % (re.escape(level), re.escape(level)), 1,
         "\n        <%s>25</%s>" % (level, level))
# -Xlint:all on 343 sources at level 25 prints hundreds of warnings Jenesis does not ask javac for.
edit("pom.xml", r"\n[ \t]*<compilerArgument>-Xlint:all,-options,-processing</compilerArgument>", 1)

# The licence-header formatter the parent binds to the package phase rewrites sources: work only Maven would do.
edit("pom.xml", r"\n[ \t]*<!-- Add license headers to all files\. -->\s*<plugin>\s*<groupId>com\.mycila</groupId>.*?</plugin>", 1)

# Both modules copy LICENSE and NOTICE from the project root into META-INF, a resource outside the module.
for pom in ("byte-buddy-dep/pom.xml", "byte-buddy-agent/pom.xml"):
    edit(pom, r"\n[ \t]*<resource>\s*<directory>\.\.</directory>.*?</resource>", 1)

# byte-buddy-dep rewrites its own compiled classes with the released Byte Buddy Maven plugin (equals/hashCode,
# cached returns, access-controller dispatch): a Maven plugin's work Jenesis does not do. The multi-release profile's
# execution is inactive and stays.
edit("byte-buddy-dep/pom.xml",
     r"\n[ \t]*<!-- Create hashCode/equals method and cache some expensive properties\. -->\s*<plugin>\s*"
     r"<groupId>net\.bytebuddy</groupId>\s*<artifactId>byte-buddy-maven-plugin</artifactId>\s*"
     r"<version>[^<]*</version>\s*<executions>\s*<execution>\s*<phase>compile</phase>.*?</executions>\s*</plugin>", 1)

# byte-buddy-agent writes an OSGi and agent manifest with the bundle plugin, packs it with the jar plugin and adds a
# module-info.class with modulemaker: packaging work Jenesis does not do.
edit("byte-buddy-agent/pom.xml",
     r"\n[ \t]*<!-- Create manifest file which is required for creating an OSGi bundle\. -->\s*<plugin>.*?</plugin>", 1)
edit("byte-buddy-agent/pom.xml",
     r"\n[ \t]*<!-- Specify OSGi packaging and agent manifest headers\. -->\s*<plugin>.*?</plugin>", 1)
edit("byte-buddy-agent/pom.xml",
     r"\n[ \t]*<!-- Create a module-info\.class file\. -->\s*<plugin>.*?</plugin>", 1)

# byte-buddy-dep's tests read class files compiled for old Java versions. Eighteen profiles decide between compiling
# them from src/test/java-<version> (activated by -Djava-<version>-precompile) and, by default, taking the class files
# checked in under src/test/precompiled-<version> as test resources. The default becomes the build itself: the
# precompiled folders are plain test resources, the profiles go, and the source folders only they compiled are in
# REMOVE.
edit("byte-buddy-dep/pom.xml",
     r"\n[ \t]*(?:<!-- Precompilation configuration[^>]*-->\s*)?<profile>\s*<id>java-[0-9a-z-]+?-(?:no-)?precompile</id>"
     r".*?</profile>", 18)
precompiled = ("4", "4-jsr14", "6", "7", "8", "8-parameters", "11", "16", "17")
edit("byte-buddy-dep/pom.xml", r"(<build>\s*<resources>.*?</resources>\n)", 1,
     r"\1        <testResources>\n            <testResource>\n                <directory>src/test/resources</directory>\n"
     r"            </testResource>\n"
     + "".join(r"            <testResource>\n                <directory>src/test/precompiled-%s</directory>\n"
               r"            </testResource>\n" % version for version in precompiled)
     + r"        </testResources>\n")

for pom in ("pom.xml", "byte-buddy-dep/pom.xml", "byte-buddy-agent/pom.xml"):
    xml.dom.minidom.parse(pom)
PY

absent() { # absent <pattern> <file>...: fails when a removed block is still there
  if grep -q "$@"; then echo "prepare: $1 is still in ${*:2}" >&2; exit 1; fi
}
[ "$(sed -n '0,/<\/modules>/p' pom.xml | grep -c '<module>')" = 2 ]
sed -n '0,/<\/modules>/p' pom.xml | grep -q '<module>byte-buddy-dep</module>'
sed -n '0,/<\/modules>/p' pom.xml | grep -q '<module>byte-buddy-agent</module>'
absent com.mycila pom.xml
absent '<directory>\.\.</directory>' byte-buddy-dep/pom.xml byte-buddy-agent/pom.xml
absent '<goal>transform</goal>' byte-buddy-dep/pom.xml
absent 'maven-bundle-plugin\|modulemaker-maven-plugin\|maven-jar-plugin' byte-buddy-agent/pom.xml
absent 'precompile</id>' byte-buddy-dep/pom.xml
[ "$(grep -c '<directory>src/test/precompiled-' byte-buddy-dep/pom.xml)" = 9 ]
for version in 4 4-jsr14 6 7 8 8-parameters 11 16 17; do
  [ -d "byte-buddy-dep/src/test/precompiled-$version" ] || { echo "prepare: no precompiled-$version" >&2; exit 1; }
  [ ! -e "byte-buddy-dep/src/test/java-$version" ] || { echo "prepare: REMOVE must delete java-$version" >&2; exit 1; }
done
absent 'compatibility</id>' pom.xml
[ "$(grep -c '^        <\(source\|byte\)code\.\(main\|test\)\.version>25<' pom.xml)" = 4 ]
