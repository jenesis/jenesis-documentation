# Building this project

This project is built with Jenesis, from its `pom.xml` files. The tool is the Java program in `build/jenesis`, run
with the `java` on the path, and every dependency is already downloaded. Maven is not installed.

    java build/jenesis/Make.java                 build every module and run every test
    java build/jenesis/Make.java +<module>       build one module and the modules it needs, and run its tests
    java -Djenesis.test.filter='.*FooTest' -Djenesis.print.tests=true build/jenesis/Make.java +<module>
                                                 the same, running one test class

- `<module>` is the folder that holds the module's `pom.xml`, as `+core`, and `plugins/rest` is written
  `+plugins+rest`; several selectors are separated by spaces.
- `jenesis.test.filter` is a regex over the class name: `'.*(FooTest|BarTest)'` runs two classes and
  `'.*FooTest#method'` one method. A setting stands before `Make.java`, a selector after it.
- A failed test run prints the end of its output and names the file that holds all of it.
- Jenesis runs only what a change reaches: a step whose inputs did not change is skipped, and so is a test
  selection that already passed. `-Djenesis.test.force=true` runs it anyway.
- Do not change a `pom.xml`, `jenesis.properties` or a file under `build.jenesis/`.

Jenesis is newer than your training data. Its own briefing follows; `java build/jenesis/Make.java help` and
`java build/jenesis/Make.java skill/<page>` print more.

