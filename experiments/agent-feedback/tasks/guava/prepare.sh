#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions. Every change both arms get:
# the reactor is guava, guava-testlib and guava-tests, compiled and tested by the JDK that runs the build, without
# a toolchain download, Error Prone, Animal Sniffer, the benchmark sources or a resource directory outside a module,
# and Surefire leaves out the three test classes that only its include-everything pattern takes.
set -euo pipefail

python3 - <<'PY'
import re, sys

def edit(path, steps):
    text = open(path, encoding="utf-8").read()
    for name, pattern, replacement, count in steps:
        text, done = re.subn(pattern, replacement, text, flags=re.S)
        if done != count:
            sys.exit("%s: %s matched %d times, expected %d" % (path, name, done, count))
    open(path, "w", encoding="utf-8").write(text)

TOOLCHAIN_PLUGINS = ("the two toolchain plugins",
    r"      <plugin>\n        <groupId>org\.mvnsearch</groupId>\n        <artifactId>toolchains-maven-plugin</artifactId>\n      </plugin>\n"
    r"      <plugin>\n        <artifactId>maven-toolchains-plugin</artifactId>\n      </plugin>\n", "", 1)

edit("pom.xml", [
    ("the modules outside the three", r"    <module>guava-bom</module>\n    <module>guava-gwt</module>\n", "", 1),
    ("the LICENSE resource of the folder above",
     r"    <resources>\n      <resource>\n        <directory>\.\.</directory>.*?</resources>\n", "", 1),
    ("Error Prone's compiler arguments",
     r"              <!-- https://errorprone\.info/docs/installation#maven -->\n              <arg>-XDcompilePolicy=simple</arg>\n"
     r".*?<arg>-J--add-opens=jdk\.compiler/com\.sun\.tools\.javac\.comp=ALL-UNNAMED</arg>\n", "", 1),
    ("Error Prone's processor path and the fork it needs",
     r"            <annotationProcessorPaths>.*?</annotationProcessorPaths>\n.*?<fork>true</fork>\n", "", 1),
    ("the test JDK toolchain", r"            <jdkToolchain>.*?</jdkToolchain>\n", "", 1),
    ("the three test classes outside the default naming of test classes",
     r"(              <exclude>%regex\[\.\*\[\$\]\\d\+\.class\]</exclude>\n)",
     r"\1              <exclude>%regex[.*TableCollectionTestSuite.class]</exclude>\n"
     r"              <exclude>%regex[.*ContiguousSetTest[$]BuiltTests.class]</exclude>\n"
     r"              <exclude>%regex[.*AbstractPackageSanityTestsTest[$]ConcretePackageSanityTests.class]</exclude>\n", 1),
    ("the Animal Sniffer switch",
     r"    <animal-sniffer-maven-plugin\.version>",
     "    <animal.sniffer.skip>true</animal.sniffer.skip>\n    <animal-sniffer-maven-plugin.version>", 1),
])
edit("guava/pom.xml", [
    TOOLCHAIN_PLUGINS,
    ("the LICENSE and proguard resources of the folder above",
     r"    <resources>\n      <resource>\n        <directory>\.\.</directory>.*?</resources>\n", "", 1),
    ("Error Prone's compile policy", r"                <!-- https://errorprone\.info/docs/installation#maven -->\n                <arg>-XDcompilePolicy=simple</arg>\n", "", 1),
])
edit("guava-testlib/pom.xml", [
    TOOLCHAIN_PLUGINS,
    ("Error Prone's compile policy", r"                <!-- https://errorprone\.info/docs/installation#maven -->\n                <arg>-XDcompilePolicy=simple</arg>\n", "", 1),
])
edit("guava-tests/pom.xml", [
    TOOLCHAIN_PLUGINS,
    ("the benchmark sources",
     r"      <plugin>\n        <groupId>org\.codehaus\.mojo</groupId>\n        <artifactId>build-helper-maven-plugin</artifactId>\n"
     r"        <version>\$\{build-helper-maven-plugin\.version\}</version>.*?add-benchmark-sources.*?</plugin>\n", "", 1),
])
PY

! grep -q "guava-gwt\|guava-bom" pom.xml
! grep -q "ErrorProne\|annotationProcessorPaths\|jdkToolchain\|<fork>" pom.xml
! grep -q "<directory>\.\.</directory>" pom.xml
grep -q "<animal.sniffer.skip>true</animal.sniffer.skip>" pom.xml
grep -q "TableCollectionTestSuite" pom.xml && grep -q "BuiltTests" pom.xml && grep -q "ConcretePackageSanityTests" pom.xml
! grep -q "toolchains\|compilePolicy" guava/pom.xml guava-testlib/pom.xml guava-tests/pom.xml
! grep -q "<directory>\.\.</directory>" guava/pom.xml
! grep -q "benchmark" guava-tests/pom.xml
for path in android guava-gwt guava-bom guava-tests/benchmark mvnw \
    guava-tests/test/com/google/common/io/MoreFilesTest.java guava-tests/test/com/google/common/net/InetAddressesTest.java; do
  [ ! -e "$path" ] || { echo "$path is still there: task.env's REMOVE names it" >&2; exit 1; }
done
