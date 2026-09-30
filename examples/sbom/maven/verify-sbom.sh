#!/usr/bin/env bash
set -euo pipefail
mvn -B clean install
first="$(sha256sum < target/bom.json)"
sleep 2
log="$(mvn -B clean install)"
echo "$log"
grep -F 'target/bom.json to ' <<< "$log" | grep -F 'app-1.0.0-cyclonedx.json'
[ "$first" = "$(sha256sum < target/bom.json)" ]
grep -F '"publisher" : "Demo Org"' target/bom.json
! grep -E '"(copyright|supplier|manufacturer|authors)"' target/bom.json
[ "$(grep -c '"purl" : "pkg:maven/' target/bom.json)" -eq 7 ]
echo "The SBOM is installed beside the jar and the same on two clean builds"
