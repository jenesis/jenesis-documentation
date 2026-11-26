# Building this project

This project is built with Maven. `mvn` is on the path, and every dependency and plugin is already downloaded, so
work offline with `-o`. No other build tool is installed.

    mvn -o test                                  build every module and run every test
    mvn -o -pl <module> -am test                 build one module and the modules it needs, and run their tests
    mvn -o -pl <module> -am test -Dtest=FooTest -Dsurefire.failIfNoSpecifiedTests=false
                                                 the same, running one test class

- `<module>` is the folder that holds the module's `pom.xml`, as `core` or `plugins/rest`; several are separated by
  commas.
- `-Dtest` takes several classes, as `-Dtest='FooTest,BarTest'`, and one method, as `-Dtest='FooTest#method'`.
  `-Dsurefire.failIfNoSpecifiedTests=false` keeps the modules that hold no such class from failing.
- `-q` prints failures alone. What a test printed is in `<module>/target/surefire-reports/`.
- Maven runs the tests again on every call, whether or not anything changed.
- Do not change a `pom.xml`.
