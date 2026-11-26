#!/usr/bin/env python3
"""uninstall.py <repository>: removes what `mvn install` put into a local repository, and nothing it downloaded."""
import os
import re
import shutil
import sys

for folder, _, files in os.walk(sys.argv[1]):
    if "maven-metadata-local.xml" not in files:
        continue
    metadata = os.path.join(folder, "maven-metadata-local.xml")
    if any(name.endswith(".pom") for name in files):
        shutil.rmtree(folder)
        continue
    with open(metadata) as file:
        for version in re.findall(r"<version>([^<]+)</version>", file.read()):
            shutil.rmtree(os.path.join(folder, version), ignore_errors=True)
    os.remove(metadata)
