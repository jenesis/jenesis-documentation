#!/usr/bin/env bash
set -euo pipefail
sbom=target/stage/maven/output/demo/app/1.0.0/app-1.0.0-cyclonedx.json
jar=target/stage/maven/output/demo/app/1.0.0/app-1.0.0.jar
rm -rf target
java build/jenesis/Make.java stage
cp "$sbom" build/first.cdx.json
rm -rf target
java build/jenesis/Make.java stage
cmp build/first.cdx.json "$sbom"
rm build/first.cdx.json
unzip -p "$jar" META-INF/sbom/app.cdx.json | cmp - "$sbom"
grep -F '"supplier": { "name": "Example Org"' "$sbom"
grep -F '"manufacturer": { "name": "Example Org"' "$sbom"
grep -F '"publisher": "Example Org"' "$sbom"
grep -F '"copyright": "Copyright 2026 Example Org"' "$sbom"
grep -F '{ "type": "vcs", "url": "https://github.com/example/demo-app" }' "$sbom"
grep -F '"purl": "pkg:maven/com.fasterxml.jackson.core/jackson-core@2.22.3"' "$sbom"
grep -F '"scope": "excluded"' "$sbom"
[ "$(grep -c '"alg": "SHA-256"' "$sbom")" -eq 6 ]
[ "$(grep -c '"license": { "id"' "$sbom")" -eq 7 ]
echo "The SBOM is in the jar and beside it, complete, and the same on two clean builds"
