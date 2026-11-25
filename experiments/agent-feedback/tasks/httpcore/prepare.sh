#!/usr/bin/env bash
# Run in the project's root once it is cloned. The poms name source and target 1.8 and no release, and the code uses
# jdk.net types that release 8 does not offer. The project states a release of 11 here, which holds those types, so
# that both tools compile against the same API.
set -euo pipefail
sed -i 's|^\(\s*\)<maven.compiler.source>${javaVersion}</maven.compiler.source>|\1<maven.compiler.release>11</maven.compiler.release>\n&|' pom.xml
sed -i 's|<release combine.self="override"/>|<release>11</release>|' pom.xml
grep -q '<maven.compiler.release>11</maven.compiler.release>' pom.xml
grep -q '<release>11</release>' pom.xml
