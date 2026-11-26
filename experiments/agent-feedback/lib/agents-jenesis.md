# Building this project

This project is built with Jenesis, from its `pom.xml` files. The tool is the Java program in `build/jenesis`, run
with the `java` on the path, and every dependency is already downloaded. Maven is not installed.

    java build/jenesis/Make.java skill/start

prints the tool's briefing for a coding agent: how to build one module, run one test class and read the result.
Read it before the first build.

Do not change a `pom.xml`, `jenesis.properties` or a file under `build.jenesis/`.
