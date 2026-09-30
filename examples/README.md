# Examples

Every build shown on [jenesis.build/why/tool/](https://jenesis.build/why/tool/) is a complete project here, one
folder per section and tool: `examples/<section>/<tool>/`. The page shows their files verbatim, so what it
compares is what these projects build.

```
examples/verify.sh                   # every example
examples/verify.sh caching           # the four tools of one section
examples/verify.sh supply-chain/maven
```

`verify.sh` runs the command on the first line of each project's `.verify` in that project's folder and checks
that the output holds the line below it. Several projects prove a claim rather than only building: the caching
examples edit a class and check what ran again, the supply-chain examples tamper with a checksum, a key, an
identity and a jar and expect each build to fail, and the reproducible examples build twice and compare bytes.

It needs a JDK 25 on the `PATH` and, for the examples of each tool:

- Jenesis: `build/jenesis/` in the project, linked from `JENESIS_HOME` (a checkout's `sources/build/jenesis`)
  or installed from https://get.jenesis.build, which takes the release `JENESIS_REF` names;
- Maven 3.9.16 as `mvn` (Hello, world uses its wrapper);
- Gradle 9.8.0 as `gradle` (Hello, world uses its wrapper);
- Bazelisk as `bazel`, which reads each project's `.bazelversion`;
- a Docker daemon for the container images.
