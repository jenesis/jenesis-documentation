# Transitive dependencies of a range-resolved dependency are silently missing

## Observed

Since Maven moved to Resolver 2.x (Maven 3.10.0, 4.0.0-rc-7; Maven 3.9.x is fine), a build can silently lose
transitive dependencies. No warning and no error is reported; the classes are simply not on the class path and
the code fails later with `ClassNotFoundException`.

The original report: a project depends directly on `software.amazon.awscdk:aws-cdk-lib:2.140.0` and on
`io.github.cdklabs:cdknag:2.37.55`, whose POM declares `aws-cdk-lib` with the version range `[2.176.0,3.0.0)`.
The version selected from the range ends up in the resolved graph, but the dependencies that version declares
(for example `cdk-asset-awscli-v1`) are missing. A second report shows the same with Guava: the selected
`guava` version has lost all its children.

## Reduced to the resolver

With the default dependency collector of Resolver 2.x (breadth-first, default configuration), collect the
dependencies of a root with these artifact descriptors:

```
root:1      -> parent:1, library:1
parent:1    -> library:[2,4)
library:1   -> (nothing)
library:2   -> (nothing)
library:3   -> range-asset:1
range-asset:1 -> (nothing)
```

The collected graph contains `root -> parent -> library:3`, as it should (3 is the highest version in the
range), but that `library:3` node has no children: `range-asset:1` was never collected below it. Because the
node for `library:3` can go on to win conflict resolution, `range-asset` is then absent from the resolved
dependencies altogether.

## Expected

A dependency whose version comes from a version range has its own dependencies collected, exactly as if that
version had been declared directly: in the example, `library:3` under `parent` has `range-asset:1` as a child.
Dependencies declared with a plain version must keep behaving as they do today: a second occurrence of the very
same artifact that was already collected is still skipped as a duplicate of the first, and not as the loser
of a version conflict, also when a range-resolved occurrence of another version of that artifact was seen in
between.

Collection reports no exceptions in any of these cases, before or after.
