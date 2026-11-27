
## Running Maven here

- Every call takes `-o`: nothing is downloaded, and the sibling modules are not installed in the local repository.
- One module and what it needs: `mvn -o -q -pl <module> -am test`. A module named with `-pl` alone fails to
  resolve its siblings. `-amd` adds the modules that depend on it.
- One test class: add `-Dtest=<Class> -Dsurefire.failIfNoSpecifiedTests=false`.
- `-q` prints the failures alone. A failed test is listed in `<module>/target/surefire-reports/<class>.txt`.
- Run a build in the foreground and give the shell call a timeout that covers it, up to ten minutes; write the
  output of a longer build to a file and read its end.
