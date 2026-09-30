#!/usr/bin/env bash
set -euo pipefail
rm -rf build/second
gradle --no-daemon clean jar
mkdir -p build/second
cp -r build.gradle.kts settings.gradle.kts src build/second/
sleep 2
(cd build/second && umask 077 && TZ=Pacific/Kiritimati gradle --no-daemon jar)
sha256sum build/libs/app-1.0.0.jar build/second/build/libs/app-1.0.0.jar
[ "$(sha256sum < build/libs/app-1.0.0.jar)" = "$(sha256sum < build/second/build/libs/app-1.0.0.jar)" ] \
    && echo "The two jars are identical"
