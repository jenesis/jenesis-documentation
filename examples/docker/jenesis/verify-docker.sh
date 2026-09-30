#!/usr/bin/env bash
set -euo pipefail
java build/jenesis/Make.java stage
context=target/stage/docker/output/module-sources
grep -qx 'FROM eclipse-temurin:25-jre' "$context/Dockerfile"
grep -qx '"--module"' "$context/application.args"
docker build -t demo/app "$context"
docker run --rm demo/app
