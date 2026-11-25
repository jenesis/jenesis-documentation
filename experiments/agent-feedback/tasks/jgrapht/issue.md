# HowardMinimumMeanCycle.getCycle() never returns on some small graphs

`org.jgrapht.alg.cycle.HowardMinimumMeanCycle#getCycle()` (module `jgrapht-core`) does not terminate on some
small directed weighted graphs. It keeps allocating until the JVM dies with `OutOfMemoryError`.

## Reproduce

```java
Graph<Integer, DefaultWeightedEdge> graph =
    new DirectedWeightedPseudograph<>(DefaultWeightedEdge.class);
for (int v = 0; v < 4; v++) {
    graph.addVertex(v);
}
Graphs.addEdge(graph, 0, 2, 2);
Graphs.addEdge(graph, 1, 2, 1);
Graphs.addEdge(graph, 2, 3, 2);
Graphs.addEdge(graph, 3, 0, 1);
Graphs.addEdge(graph, 3, 1, 2);

HowardMinimumMeanCycle<Integer, DefaultWeightedEdge> mmc = new HowardMinimumMeanCycle<>(graph);
mmc.getCycle(); // never returns, eventually java.lang.OutOfMemoryError
```

This graph has two cycles, `0 -> 2 -> 3 -> 0` and `1 -> 2 -> 3 -> 1`, both with mean 5/3.

A second graph shows the same hang:

```java
Graphs.addEdge(graph, 0, 1, 4);
Graphs.addEdge(graph, 1, 2, 2);
Graphs.addEdge(graph, 2, 0, 5);
Graphs.addEdge(graph, 2, 1, 5);
```

Its minimum mean cycle is `1 -> 2 -> 1` with mean 3.5.

## Expected

- `getCycle()` returns on every graph, and the returned cycle is a closed walk in the graph whose edge weights
  sum to the weight it reports, so that weight / length equals `getCycleMean()`.
- For the first graph: a cycle of mean 5/3 (`0 -> 2 -> 3 -> 0`).
- For the second graph: the cycle `1 -> 2 -> 1` with mean 3.5.
- The `maximumIterations` constructor argument must be honoured without breaking this: with
  `new HowardMinimumMeanCycle<>(graph, 1)` on the second graph the algorithm stops after one iteration and
  returns the best cycle it found by then, `0 -> 1 -> 2 -> 0` with mean 11/3, again as a consistent cycle.
- The cycles above are written as the returned `GraphPath` reports them: start and end vertex are the vertex
  written first, and the edge list follows in that order.

## Observed

`getCycle()` hangs and exhausts the heap on both graphs with the default iteration limit. The existing tests of
`HowardMinimumMeanCycle` pass.
