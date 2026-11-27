#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions of task.env.
# Every change here is made to the project itself, so the Maven arm and the Jenesis arm get the same project.
set -euo pipefail

for gone in afterburner afterburner-tests android-record guice guice7 jakarta-xmlbind jaxb mrbean no-ctor-deser osgi \
    spi-subtypes blackbird/benchmarks; do
  [ ! -e "$gone" ] || { echo "prepare: $gone is still there, REMOVE of task.env must delete it" >&2; exit 1; }
done

python3 - <<'PY'
import re, sys, os

def edit(path, pattern, expected, replacement=""):
    text = open(path, encoding="utf-8").read()
    text, count = re.subn(pattern, replacement, text, flags=re.S)
    if count != expected:
        sys.exit("prepare: %s matched %d times in %s, expected %d" % (pattern[:70], count, path, expected))
    open(path, "w", encoding="utf-8").write(text)

# The reactor is the parent and the three Blackbird modules. They were listed in a profile that JDK 25 activates;
# they move into <modules>, and the modules the bug does not reach leave it (their folders are in REMOVE).
edit("pom.xml", r"\n  <modules>\n.*?\n  </modules>\n", 1,
     "\n  <modules>\n    <module>blackbird</module>\n    <module>blackbird-tests</module>\n"
     "    <module>blackbird-jpms-tests</module>\n  </modules>\n")
edit("pom.xml", r"\n[ \t]*<!-- Blackbird's code generators use the ClassFile API.*?-->\s*<profile>\s*<id>blackbird-jdk25</id>.*?</profile>", 1)

# Every module left compiles at release 25, as Jenesis compiles for the JDK it runs on.
edit("pom.xml", r"<maven\.compiler\.release>17</maven\.compiler\.release>", 1,
     "<maven.compiler.release>25</maven.compiler.release>")
edit("pom.xml", r"<javac\.src\.version>17</javac\.src\.version>", 1, "<javac.src.version>25</javac.src.version>")
edit("pom.xml", r"<javac\.target\.version>17</javac\.target\.version>", 1,
     "<javac.target.version>25</javac.target.version>")
# The parent attaches JaCoCo's agent to every test JVM and writes a coverage report, which Jenesis does not do.
edit("pom.xml", r"(<version\.bytebuddy>1\.18\.15</version\.bytebuddy>)", 1, r"\1\n    <jacoco.skip>true</jacoco.skip>")

# The 3.4.0-SNAPSHOTs of the Jackson parents, jackson-core, jackson-annotations and jackson-databind come from
# the snapshot repository this pom names. Once fetched they stay what was fetched: no build, online or not,
# asks the repository for a newer one, so that every run of both arms uses the same jars.
edit("pom.xml", r"(<id>central-snapshots</id>.*?<snapshots><enabled>true</enabled>)(</snapshots>)", 1,
     r"\1<updatePolicy>never</updatePolicy>\2")

# PackageVersion.java is generated from a template by the replacer plugin: the generated file becomes a source.
edit("pom.xml", r"\n[ \t]*<build>\s*<pluginManagement>\s*<plugins>\s*<plugin>\s*<!-- Inherited from oss-base\. Generate PackageVersion\.java\.-->.*?</build>\n", 1, "\n")
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<!-- Inherited from oss-base\. Generate PackageVersion\.java\.-->.*?</plugin>\n", 1, "\n")
template = "blackbird/src/main/java/tools/jackson/module/blackbird/PackageVersion.java.in"
text = open(template, encoding="utf-8").read()
for key, value in {"@package@": "tools.jackson.module.blackbird", "@projectversion@": "3.4.0-SNAPSHOT",
                   "@projectgroupid@": "tools.jackson.module", "@projectartifactid@": "jackson-module-blackbird"}.items():
    if text.count(key) != 1:
        sys.exit("prepare: %s changed shape" % template)
    text = text.replace(key, value)
open(template[:-3], "w", encoding="utf-8").write(text)
os.remove(template)

# Blackbird is a multi-release jar whose two ClassFile API generators compile at release 25 into
# META-INF/versions/25 by a second compiler execution. They join the other sources, which compile at 25 too, and
# the executions and plugin settings that arrange the multi-release layout go, as do Blackbird's own OSGi settings and
# the SBOM and Gradle-metadata plugins. The parent's bnd manifest stays, as the parent's jar configuration reads it.
edit("blackbird/pom.xml", r"\n[ \t]*<!-- Multi-release layout\..*?-->\s*<plugin>\s*<groupId>org\.codehaus\.mojo</groupId>\s*<artifactId>build-helper-maven-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-compiler-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-resources-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-jar-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<groupId>org\.apache\.felix</groupId>\s*<artifactId>maven-bundle-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-javadoc-plugin</artifactId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<!-- 29-Apr-2025, tatu: SBOM generation \[JSTEP-14\] -->\s*<plugin>\s*<groupId>org\.cyclonedx</groupId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<!-- 05-Jul-2020, tatu: Add generation of Gradle Module Metadata -->.*?<plugin>\s*<groupId>org\.gradlex</groupId>.*?</plugin>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<!-- A multi-release jar:.*?-->\s*<maven\.compiler\.testRelease>25</maven\.compiler\.testRelease>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<!-- Only the module class is API, as in module-info\. -->\s*<osgi\.export>.*?</osgi\.import>", 1)
edit("blackbird/pom.xml", r"\n[ \t]*<packageVersion\.dir>.*?</packageVersion\.package>", 1)
for name in ("BeanReaderGenerator.java", "BeanWriterGenerator.java"):
    os.rename("blackbird/src/main/java25/tools/jackson/module/blackbird/codegen/" + name,
              "blackbird/src/main/java/tools/jackson/module/blackbird/codegen/" + name)
import shutil
if any(files for _, _, files in os.walk("blackbird/src/main/java25")):
    sys.exit("prepare: blackbird/src/main/java25 holds more than the two generators")
shutil.rmtree("blackbird/src/main/java25")

# Blackbird's own tests declare a test module-info.java that names Blackbird's module, which surefire patches into
# the main module; Jenesis cannot build that idiom. The descriptor and the patch go, and the tests run on the class
# path in both tools, as blackbird-tests already does.
os.remove("blackbird/src/test/java/module-info.java")
edit("blackbird/pom.xml", r"\n[ \t]*<!-- The test descriptor \(src/test/java/module-info\.java\) names.*?-->\s*<argLine>@\{argLine\} --patch-module [^<]*</argLine>", 1,
     "\n          <useModulePath>false</useModulePath>")

# Tests of what Maven's packaging plugins put into the jar: JdkCompatibilityTest runs the packaged multi-release jar
# in child JVMs of older JDKs (none are configured, and Maven's test phase skips it for want of the jar), and one test
# of PackagingTest reads the OSGi exports of the jar. Neither tool produces that jar any longer.
os.remove("blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/JdkCompatibilityTest.java")
edit("blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/PackagingTest.java",
     r"\n[ \t]*// OSGi exports match the module descriptor\.\s*@Test\s*public void bundleExportsOnlyTheModulePackage\(\).*?\n    }\n", 1)
# Another reads the release profile of the root pom.xml from the folder the tests run in, the module's for Maven and
# the project's for Jenesis: it is about how a release is built, and goes for both.
edit("blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/PackagingTest.java",
     r"\n[ \t]*// A release built on JDK < 25 would leave Blackbird out\..*?public void releaseProfileRequiresJdk25\(\).*?\n    }\n", 1)
PY

grep -q '<module>blackbird-jpms-tests</module>' pom.xml
! grep -q '<module>afterburner</module>' pom.xml
! grep -q 'blackbird-jdk25' pom.xml
grep -q '<updatePolicy>never</updatePolicy>' pom.xml
! grep -q 'replacer' pom.xml blackbird/pom.xml
! grep -q 'java25\|multiRelease\|cyclonedx\|gradlex' blackbird/pom.xml
[ -f blackbird/src/main/java/tools/jackson/module/blackbird/PackageVersion.java ]
[ -f blackbird/src/main/java/tools/jackson/module/blackbird/codegen/BeanReaderGenerator.java ]
[ ! -e blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/JdkCompatibilityTest.java ]
! grep -q 'releaseProfileRequiresJdk25' blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/PackagingTest.java
! grep -q 'bundleExportsOnlyTheModulePackage' blackbird-tests/src/test/java/tools/jackson/module/blackbird/jdk/PackagingTest.java
[ ! -e blackbird/src/test/java/module-info.java ]
! grep -q 'patch-module' blackbird/pom.xml
grep -q '<useModulePath>false</useModulePath>' blackbird/pom.xml
grep -q '<jacoco.skip>true</jacoco.skip>' pom.xml
