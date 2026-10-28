// The builds a coding agent moved to Jenesis, and the medians of the benchmark that compares each with its original:
// in seconds, [Jenesis, before], for a full build, a build with nothing changed and one after a method body was edited.
// Jenesis from an ahead-of-time cache is compared with the original build without a daemon.
// Each pair is shown with the share of the time before that Jenesis saved, rounded down, and each tab with the median
// saving of every kind of build across the projects.
const projects = [
  { name: "Guava", repository: "https://github.com/google/guava", tool: "Maven", agent: "57 min",
    nodaemon: { full: [703.0, 819.2], again: [3.8, 802.2], edit: [664.8, 836.3] },
    daemon: { full: [673.5, 789.2], again: [2.8, 779.2], edit: [637.3, 818.3] } },
  { name: "JUnit 5", repository: "https://github.com/junit-team/junit-framework", tool: "Gradle", agent: "1 h 18 min",
    nodaemon: { full: [222.2, 258.2], again: [6.6, 17.6], edit: [131.8, 173.8] },
    daemon: { full: [160.2, 236.5], again: [4.1, 6.7], edit: [103.7, 170.1] },
    aot: { full: 206.1, again: 5.3, edit: 130.0 } },
  { name: "Mockito", repository: "https://github.com/mockito/mockito", tool: "Gradle", agent: "53 min",
    nodaemon: { full: [202.1, 223.5], again: [6.0, 23.0], edit: [174.1, 177.2] },
    daemon: { full: [159.7, 191.6], again: [3.5, 6.5], edit: [143.1, 152.8] },
    aot: { full: 200.8, again: 4.6, edit: 173.7 } },
  { name: "AssertJ", repository: "https://github.com/assertj/assertj", tool: "Maven", agent: "45 min",
    nodaemon: { full: [95.2, 142.3], again: [4.4, 117.9], edit: [65.2, 123.7] },
    daemon: { full: [69.9, 103.3], again: [2.5, 79.7], edit: [58.5, 88.3] },
    aot: { full: 92.6, again: 3.0, edit: 65.5 } },
  { name: "Google Auto", repository: "https://github.com/google/auto", tool: "Maven", agent: "37 min",
    nodaemon: { full: [79.7, 99.2], again: [3.5, 95.2], edit: [30.6, 98.6] },
    daemon: { full: [71.5, 71.7], again: [2.0, 70.2], edit: [20.2, 70.2] },
    aot: { full: 82.7, again: 2.1, edit: 26.6 } },
  { name: "Jackson Databind", repository: "https://github.com/FasterXML/jackson-databind", tool: "Maven", agent: "23 min",
    nodaemon: { full: [55.1, 65.5], again: [4.2, 66.7], edit: [43.7, 66.2] },
    daemon: { full: [48.7, 53.4], again: [2.1, 53.6], edit: [36.1, 52.0] },
    aot: { full: 51.0, again: 2.5, edit: 42.0 } },
  { name: "Gson", repository: "https://github.com/google/gson", tool: "Maven", agent: "30 min",
    nodaemon: { full: [55.1, 73.3], again: [3.6, 44.4], edit: [19.9, 67.2] },
    daemon: { full: [33.2, 49.2], again: [2.0, 22.0], edit: [13.6, 43.0] },
    aot: { full: 44.7, again: 1.7, edit: 15.8 } },
  { name: "jsoup", repository: "https://github.com/jhy/jsoup", tool: "Maven", agent: "32 min",
    nodaemon: { full: [40.8, 51.6], again: [2.7, 39.7], edit: [36.3, 39.5] },
    daemon: { full: [35.4, 37.8], again: [1.7, 30.6], edit: [31.0, 31.4] },
    aot: { full: 37.9, again: 1.2, edit: 32.2 } },
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
  if (pairing !== "aot") {
    return project[pairing];
  }
  return project.aot && Object.fromEntries(kinds.map(kind => [kind, [project.aot[kind], project.nodaemon[kind][1]]]));
}

function rows(pairing) {
  return projects.filter(project => measured(project, pairing)).map(project => {
    const times = measured(project, pairing);
    return {
      name: project.name,
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

export default {
  pairings: [
    { id: "nodaemon", label: "Without a daemon", rows: rows("nodaemon"), medians: medians("nodaemon") },
    { id: "daemon", label: "With a daemon", rows: rows("daemon"), medians: medians("daemon") },
    { id: "aot", label: "With an ahead-of-time cache", rows: rows("aot"), medians: medians("aot") },
  ],
};
