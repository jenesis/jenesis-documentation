#!/usr/bin/env bash
set -euo pipefail
root="$(pwd -P)"
rm -rf target
for build in first second; do
    mkdir -p "target/$build"
    cp -r pom.xml src "target/$build/"
done
(cd target/first && mvn -B clean deploy -DaltDeploymentRepository=reference::file://"$root"/target/reference)
sleep 2
(cd target/second && umask 077 && TZ=Pacific/Kiritimati mvn -B clean verify \
    org.apache.maven.plugins:maven-artifact-plugin:3.7.0:compare -Dreference.repo=file://"$root"/target/reference)
sha256sum target/first/target/app-1.0.0.jar target/second/target/app-1.0.0.jar
[ "$(sha256sum < target/first/target/app-1.0.0.jar)" = "$(sha256sum < target/second/target/app-1.0.0.jar)" ] \
    && echo "The two jars are identical"
