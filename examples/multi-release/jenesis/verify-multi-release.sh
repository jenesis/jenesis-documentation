#!/usr/bin/env bash
set -euo pipefail
java build/jenesis/Make.java
jar="$(find target -path "*/output/artifacts/*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" | head -1)"
major() {
    unzip -p "$jar" "$1" | od -An -j6 -N2 -tu1 | awk '{ print $1 * 256 + $2 }'
}
unzip -p "$jar" META-INF/MANIFEST.MF | grep '^Multi-Release: true'
test "$(major demo/app/Main.class)" = 65
test "$(major demo/app/Platform.class)" = 65
test "$(major META-INF/versions/25/demo/app/Platform.class)" = 69
echo "demo/app/Platform.class for Java 21, META-INF/versions/25/demo/app/Platform.class for Java 25"
java -Djdk.util.jar.enableMultiRelease=false -cp "$jar" demo.app.Main | grep 'Java 21 baseline'
java -cp "$jar" demo.app.Main
