#!/usr/bin/env bash
# Run in the project's root once it is cloned, for both arms.
set -euo pipefail

# The poms hand JUnit two settings through surefire. They are stated in the project itself here, where both tools
# find them.
for module in jgrapht-*/; do
  [ -d "$module/src/test/java" ] || continue
  mkdir -p "$module/src/test/resources"
  printf 'junit.jupiter.testinstance.lifecycle.default = per_class\njunit.jupiter.execution.parallel.enabled = true\n' \
    > "$module/src/test/resources/junit-platform.properties"
done

# One test opens a class-path resource as a file, which holds only while the test classes lie in a folder; it reads
# the resource as a stream here, which holds for a folder and for a jar.
sed -i \
  -e 's|getClass().getResource("/kroA200.tsp").getPath()|"/kroA200.tsp"|' \
  -e 's|new Scanner(new File(filePath))|new Scanner(GonAlgorithmTest.class.getResourceAsStream(filePath))|' \
  -e '/^import java.io.File;$/d' \
  jgrapht-core/src/test/java/org/jgrapht/alg/centers/GonAlgorithmTest.java
grep -q 'getResourceAsStream(filePath)' jgrapht-core/src/test/java/org/jgrapht/alg/centers/GonAlgorithmTest.java
