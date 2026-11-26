Filtered `NavigableMap` views hand out the backing map's own entries from their navigation methods

`Maps.filterKeys`, `Maps.filterValues` and `Maps.filterEntries`, called on a `NavigableMap`, return a view whose
methods that return a single entry - `firstEntry()`, `lastEntry()`, `ceilingEntry()`, `floorEntry()`,
`higherEntry()`, `lowerEntry()`, `pollFirstEntry()` and `pollLastEntry()` - give back the entry objects of the
backing map. Two things go wrong with that.

**A polled entry can show another mapping.** With a `TreeMap` behind the view:

```java
NavigableMap<Integer, String> unfiltered = new TreeMap<>();
unfiltered.put(1, "one");
unfiltered.put(2, "two");
unfiltered.put(3, "three");
NavigableMap<Integer, String> filtered = Maps.filterKeys(unfiltered, k -> k != 1);
System.out.println(filtered.pollFirstEntry()); // prints 3=three, expected 2=two
```

The backing map is left correct (`{1=one, 3=three}`), only the returned entry is wrong. Draining
`Maps.filterKeys(treeMapOf0to9, k -> k % 2 == 1)` with `pollFirstEntry()` returns the keys 2, 4, 6, 7, 9 where
1, 3, 5, 7, 9 were removed. `pollLastEntry()` has the same problem.

**The entries are live.** `java.util.NavigableMap` specifies that these methods return snapshots of the mapping
at the time they were produced, which do not support `Entry.setValue`. On a filtered view, calling `setValue` on
the result of `firstEntry()`, `lastEntry()`, `ceilingEntry(k)`, `floorEntry(k)`, `higherEntry(k)` or
`lowerEntry(k)` - and on the views derived from it, such as `descendingMap()` and `headMap(...)` - writes through
to the backing map, for a map filtered by value even with a value the predicate rejects. Expected: `setValue` on
an entry returned by any of these eight methods throws `UnsupportedOperationException` and the entry keeps
showing the mapping it was created for.

Iteration is a different matter and should stay as it is: the entries of `filtered.entrySet()` (also of
`descendingMap().entrySet()`) are live, their `setValue` writes through and throws `IllegalArgumentException`
for a value the predicate rejects.

`ForwardingNavigableMap` has the same two problems in its `standardFirstEntry()`, `standardLastEntry()`,
`standardPollFirstEntry()` and `standardPollLastEntry()` helpers: a subclass that implements `pollFirstEntry()`
with `standardPollFirstEntry()` over, say, `treeMap.tailMap(2, true)` of the map above gets `3=three` instead of
`2=two`, and the entries these helpers return accept `setValue`.

The test-suite builder for navigable maps in `guava-testlib` (`NavigableMapTestSuiteBuilder`) does not notice
any of this, since it only compares the returned entries with `equals`; it ought to require that the entries
returned by the navigation methods are immutable.
