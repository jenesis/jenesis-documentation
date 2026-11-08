// The builds a coding agent moved to Jenesis, and Commons IO beside the Mill build that Mill's own examples keep for it,
// with the medians of the benchmark that compares each with its original:
// in seconds, [Jenesis, before], for a full build, a build with nothing changed and one after a method body was edited.
// Jenesis from an ahead-of-time cache and as a native image is compared with the original build without a daemon,
// measured beside it where a pair is given; the native image is summed up in a sentence rather than a tab. A project whose daemon pairing is marked ran a daemon per project.
// Each pair is shown with the share of the time before that Jenesis saved, rounded down, and each tab with the median
// saving of every kind of build across the projects.
const projects = [
  { name: "Guava", repository: "https://github.com/google/guava", tool: "Maven", agent: "57 min", apart: ["daemon"],
    nodaemon: { full: [623.2, 730.8], again: [3.1, 707.7], edit: [595.5, 710.2] },
    daemon: { full: [545.1, 642.3], again: [1.9, 621.5], edit: [528.5, 635.9] },
    aot: { full: 554.1, again: 2.0, edit: 540.8 },
    native: { full: 553.8, again: 0.8, edit: 529.3 } },
  { name: "JUnit 5", repository: "https://github.com/junit-team/junit-framework", tool: "Gradle", agent: "1 h 18 min",
    nodaemon: { full: [188.7, 218.5], again: [5.7, 14.5], edit: [110.6, 145.3] },
    daemon: { full: [127.4, 193.8], again: [3.4, 4.9], edit: [89.7, 131.0] },
    aot: { full: 182.5, again: 4.8, edit: 107.1 },
    native: { full: 166.4, again: 7.0, edit: 96.6 } },
  { name: "Mockito", repository: "https://github.com/mockito/mockito", tool: "Gradle", agent: "53 min", apart: ["daemon"],
    nodaemon: { full: [167.7, 185.3], again: [5.1, 18.5], edit: [133.2, 140.0] },
    daemon: { full: [112.9, 132.7], again: [2.7, 4.6], edit: [98.7, 106.7] },
    aot: { full: 166.2, again: 4.4, edit: 134.7 },
    native: { full: 163.2, again: 2.8, edit: 128.8 } },
  { name: "AssertJ", repository: "https://github.com/assertj/assertj", tool: "Maven", agent: "45 min",
    nodaemon: { full: [86.8, 134.1], again: [3.6, 109.3], edit: [60.8, 115.0] },
    daemon: { full: [59.0, 86.1], again: [2.5, 65.4], edit: [48.3, 69.8] },
    aot: { full: 84.7, again: 3.0, edit: 57.4 },
    native: { full: 80.3, again: 1.5, edit: 57.5 } },
  { name: "Google Auto", repository: "https://github.com/google/auto", tool: "Maven", agent: "37 min",
    nodaemon: { full: [79.7, 99.2], again: [3.5, 95.2], edit: [30.6, 98.6] },
    daemon: { full: [71.5, 71.7], again: [2.0, 70.2], edit: [20.2, 70.2] },
    aot: { full: 82.7, again: 2.1, edit: 26.6 },
    native: { full: [66.5, 82.6], again: [0.9, 77.8], edit: [23.0, 83.3] } },
  { name: "Jackson Databind", repository: "https://github.com/FasterXML/jackson-databind", tool: "Maven", agent: "23 min",
    nodaemon: { full: [57.8, 67.7], again: [4.3, 67.7], edit: [50.8, 65.7] },
    daemon: { full: [44.4, 49.7], again: [2.2, 49.2], edit: [35.8, 49.8] },
    aot: { full: 51.4, again: 2.9, edit: 42.0 },
    native: { full: 54.1, again: 1.7, edit: 43.4 } },
  { name: "Gson", repository: "https://github.com/google/gson", tool: "Maven", agent: "30 min",
    nodaemon: { full: [54.3, 74.1], again: [3.1, 46.0], edit: [18.9, 67.8] },
    daemon: { full: [30.0, 49.7], again: [1.8, 27.4], edit: [11.5, 45.1] },
    aot: { full: 48.8, again: 2.3, edit: 17.6 },
    native: { full: 43.0, again: 1.1, edit: 15.0 } },
  { name: "jsoup", repository: "https://github.com/jhy/jsoup", tool: "Maven", agent: "32 min",
    nodaemon: { full: [33.8, 43.2], again: [2.2, 33.7], edit: [31.2, 35.1] },
    daemon: { full: [28.7, 36.2], again: [1.5, 28.5], edit: [26.8, 29.5] },
    aot: { full: 35.0, again: 1.3, edit: 32.3 },
    native: { full: 30.9, again: 0.6, edit: 28.9 } },
  { name: "Commons IO*", repository: "https://github.com/com-lihaoyi/mill/tree/1.3.1/example/thirdparty/commons-io",
    tool: "Mill", agent: "by hand",
    nodaemon: { full: [69.3, 70.1], again: [2.0, 79.0], edit: [69.3, 71.6] },
    daemon: { full: [65.7, 65.9], again: [1.4, 72.5], edit: [65.7, 67.0] },
    aot: { full: [69.9, 71.2], again: [1.1, 77.2], edit: [69.5, 71.9] },
    native: { full: [69.8, 70.8], again: [1.0, 80.0], edit: [70.6, 72.8] } },
];

const kinds = ["full", "again", "edit"];

function time(seconds) {
  if (seconds < 120) {
    return `${Math.round(seconds)} s`;
  }
  const rounded = Math.round(seconds / 5) * 5;
  const minutes = Math.floor(rounded / 60), rest = rounded % 60;
  return rest === 0 ? `${minutes} min` : `${minutes} min ${rest} s`;
}

function saving(share) {
  const percent = Math.floor(Math.abs(share) * 100);
  return `${percent === 0 ? "" : share < 0 ? "+" : "−"}${percent}\u00a0%`;
}

function measured(project, pairing) {
  const times = project[pairing];
  if (pairing === "nodaemon" || pairing === "daemon" || !times) {
    return times;
  }
  return Object.fromEntries(kinds.map(kind => [kind,
    Array.isArray(times[kind]) ? times[kind] : [times[kind], project.nodaemon[kind][1]]]));
}

function rows(pairing) {
  return projects.filter(project => measured(project, pairing)).map(project => {
    const times = measured(project, pairing);
    return {
      name: project.name + ((project.apart || []).includes(pairing) ? "\u2020" : ""),
      repository: project.repository,
      tool: project.tool,
      agent: project.agent,
      cells: kinds.map(kind => {
        const share = 1 - times[kind][0] / times[kind][1];
        return {
          times: `${time(times[kind][0])} / ${time(times[kind][1])}`,
          saving: saving(share),
          spread: share < 0.05,
        };
      }),
    };
  });
}

function medians(pairing) {
  return kinds.map(kind => {
    const shares = projects.map(project => measured(project, pairing))
      .filter(times => times)
      .map(times => 1 - times[kind][0] / times[kind][1])
      .sort((a, b) => a - b);
    const middle = shares.length / 2;
    return saving(shares.length % 2 ? shares[Math.floor(middle)] : (shares[middle - 1] + shares[middle]) / 2);
  });
}

function share(pairing, kind) {
  const shares = projects.map(project => measured(project, pairing))
    .filter(times => times)
    .map(times => 1 - times[kind][0] / times[kind][1])
    .sort((a, b) => a - b);
  const middle = shares.length / 2;
  return Math.floor(100 * (shares.length % 2 ? shares[Math.floor(middle)] : (shares[middle - 1] + shares[middle]) / 2));
}

export default {
  native: Object.fromEntries(kinds.map(kind => [kind, share("native", kind)])),
  pairings: [
    { id: "nodaemon", label: "Without a daemon", rows: rows("nodaemon"), medians: medians("nodaemon") },
    { id: "daemon", label: "With a daemon", rows: rows("daemon"), medians: medians("daemon") },
    { id: "aot", label: "With an ahead-of-time cache", rows: rows("aot"), medians: medians("aot") },
  ],
};
