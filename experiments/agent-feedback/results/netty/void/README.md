# Void runs

The 28 Netty variant runs in this folder ran from a folder whose name held a plus sign (`netty-maven+cache-1`).
Netty's `ResourcesUtil.getFile` decodes the path of a test resource as a URL, which reads the plus sign as a space, so
`HostsFileParserTest` failed in every one of them for a reason that has nothing to do with the task or the variant.
The agents reacted to it - excluding the test, switching the build cache off, telling Maven to carry on after
failures - and the times and costs measure that reaction. The runs were repeated from a folder without a plus sign;
the scripts read `results/*/*.json` and so leave this folder out.
