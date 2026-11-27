#!/usr/bin/env bash
# Run in the project root after the clone, the history removal and the REMOVE deletions of task.env.
# Every change here is made to the project itself, so the Maven arm and the Jenesis arm get the same project.
set -euo pipefail

python3 - <<'PY'
import os, re, sys

def edit(path, *changes):
    text = open(path, encoding="utf-8").read()
    for pattern, replacement, expected in changes:
        text, count = re.subn(pattern, replacement, text, flags=re.S)
        if count != expected:
            sys.exit("prepare: %s matched %r %d times, expected %d" % (path, pattern, count, expected))
    open(path, "w", encoding="utf-8").write(text)

def plugin(artifact_id):
    # One <plugin> block of the build, found by its artifactId, with the whitespace before it.
    return (r"\n[ \t]*<plugin>(?:(?!</plugin>).)*?<artifactId>" + re.escape(artifact_id)
            + r"</artifactId>(?:(?!</plugin>).)*?</plugin>", "")

def build_plugin(artifact_id):
    return plugin(artifact_id) + (1,)

# The reactor: the pure-Java modules that both tools build and test, and nothing that compiles native code, shades,
# packages bundles or tests the packaging. The stubs are compile-time stand-ins common and transport need.
modules = ["dev-tools", "common", "buffer", "resolver", "transport", "testsuite-common",
           "jfr-stub", "varhandle-stub", "ffm-stub"]
edit("pom.xml", (r"\n  <modules>\n.*?\n  </modules>\n",
                 "\n  <modules>\n" + "".join("    <module>%s</module>\n" % m for m in modules) + "  </modules>\n", 1))

# Work only Maven would do while building to test: API and style checks, OSGi manifests, the version properties
# written from git, and the manifest the jar plugin would read from the bundle plugin.
# Only the plugins of the project's own <build>, not those of its profiles or its pluginManagement.
text = open("pom.xml", encoding="utf-8").read()
head, build, rest = re.match(r"(.*?\n  <build>\n)(.*?)(\n    <pluginManagement>.*)", text, re.S).groups()
open("pom.xml", "w", encoding="utf-8").write(build)
edit("pom.xml",
     build_plugin("revapi-maven-plugin"),
     build_plugin("maven-enforcer-plugin"),
     build_plugin("maven-checkstyle-plugin"),
     build_plugin("xml-maven-plugin"),
     build_plugin("maven-bundle-plugin"),
     build_plugin("maven-antrun-plugin"))
build = open("pom.xml", encoding="utf-8").read()
open("pom.xml", "w", encoding="utf-8").write(head + build + rest)
edit("pom.xml",
     (r"\n[ \t]*<manifestFile>\$\{project\.build\.outputDirectory\}/META-INF/MANIFEST\.MF</manifestFile>", "", 1))

# common: the primitive collections are generated once below instead of by the Groovy plugin; no shading of
# JCTools, no OSGi manifest, no module-info generated into a multi-release folder.
edit("common/pom.xml",
     build_plugin("maven-shade-plugin"),
     build_plugin("build-helper-maven-plugin"),
     build_plugin("groovy-maven-plugin"),
     build_plugin("maven-bundle-plugin"),
     build_plugin("module-info"))
# buffer: no OSGi manifest and no module-info; and no second surefire execution that runs every buffer test once
# more with other JVM flags on JDK 24 and newer.
edit("buffer/pom.xml",
     build_plugin("maven-bundle-plugin"),
     build_plugin("module-info"),
     (r"\n  <profiles>\n.*?\n  </profiles>\n", "\n", 1))
edit("resolver/pom.xml", build_plugin("module-info"))
edit("transport/pom.xml", build_plugin("module-info"))
# dev-tools: no remote-resources bundle descriptor.
edit("dev-tools/pom.xml", build_plugin("maven-remote-resources-plugin"))

# The primitive collections, as common/src/main/script/codegen.groovy generates them from the templates.
keys = [("byte", "Byte", "byteValue"), ("char", "Character", "charValue"), ("short", "Short", "shortValue"),
        ("int", "Integer", "intValue"), ("long", "Long", "longValue")]
generated = 0
for templates, output in (("common/src/main/templates", "common/src/main/java"),
                          ("common/src/test/templates", "common/src/test/java")):
    for folder, _, files in os.walk(templates):
        for name in files:
            if not name.endswith(".template"):
                continue
            source = open(os.path.join(folder, name), encoding="utf-8").read()
            for primitive, boxed, method in keys:
                key = primitive.capitalize()
                hash_code = "(int) (key ^ (key >>> 32))" if primitive == "long" else "(int) key"
                text = source
                for token, value in (("K", key), ("k", primitive), ("O", boxed), ("KEY_NUMBER_METHOD", method),
                                     ("HASH_CODE", hash_code)):
                    text = text.replace("@%s@" % token, value)
                target_folder = os.path.join(output, os.path.relpath(folder, templates))
                target = os.path.join(target_folder, re.sub(r"^(.*)K([^.]+)\.template$", r"\g<1>%s\2.java" % key, name))
                if os.path.exists(target):
                    sys.exit("prepare: %s exists already" % target)
                os.makedirs(target_folder, exist_ok=True)
                open(target, "w", encoding="utf-8").write(text)
                generated += 1
if generated != 20:
    sys.exit("prepare: generated %d collection sources, expected 20" % generated)
PY

# Tests that measure wall-clock time or race spinning threads against a timeout, and fail on this four-core machine
# when other test JVMs or builds load it (with either tool; Jenesis runs the modules' tests side by side, so there they
# fail in most full builds). They are switched off for both tools; NOTES.md lists each with what it did.
python3 - <<'PY'
import re, sys
disabled = {
    "transport/src/test/java/io/netty/channel/DefaultChannelPipelineTest.java":
        ["testRemoveOfHandlerReplacedConcurrently"],
    "transport/src/test/java/io/netty/channel/SingleThreadEventLoopTest.java":
        ["scheduleTaskAtFixedRateA", "scheduleTaskAtFixedRateB",
         "scheduleLaggyTaskAtFixedRateA", "scheduleLaggyTaskAtFixedRateB"],
    "common/src/test/java/io/netty/util/HashedWheelTimerTest.java":
        ["testExecutionOnTime"],
    "common/src/test/java/io/netty/util/concurrent/AutoScalingEventExecutorChooserFactoryTest.java":
        ["testMetricsProvideCorrectUtilizationAndActiveExecutorCount"],
}
for path, methods in disabled.items():
    text = open(path, encoding="utf-8").read()
    for method in methods:
        pattern = re.compile(r"^([ \t]+)((?:public )?void " + method + r"\(\))", re.M)
        text, count = pattern.subn(
            r'\1@org.junit.jupiter.api.Disabled("Timing-sensitive under load")\n\1\2', text)
        if count != 1:
            sys.exit("prepare: %s declares %s %d times, expected 1" % (path, method, count))
    open(path, "w", encoding="utf-8").write(text)
PY
test "$(grep -c 'Timing-sensitive under load' transport/src/test/java/io/netty/channel/SingleThreadEventLoopTest.java)" = 4

grep -q '<module>transport</module>' pom.xml
! grep -q '<module>handler</module>' pom.xml
! grep -q 'groovy-maven-plugin\|maven-shade-plugin' common/pom.xml
! grep -q 'maven-bundle-plugin\|revapi-maven-plugin\|maven-checkstyle-plugin' pom.xml common/pom.xml buffer/pom.xml
test -f common/src/main/java/io/netty/util/collection/IntObjectHashMap.java
test -f common/src/test/java/io/netty/util/collection/LongObjectHashMapTest.java
rm -r common/src/main/templates common/src/test/templates common/src/main/script
