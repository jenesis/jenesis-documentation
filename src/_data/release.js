// Which repository each landing-page tile takes its release from. No version is committed here on purpose:
// assets/js/version.js reads the newest release tag from the GitHub API at page load, and a tile whose
// lookup does not answer stays hidden rather than showing a number that may since have been superseded.
//
// The build tool and jpx ship in the same artifact and therefore share a repository - the refresh fetches
// each distinct repository once.
export default {
  install: "curl -fsSL https://get.jenesis.build | bash",
  components: {
    tool: { repo: "jenesis/jenesis" },
    jpx: { repo: "jenesis/jenesis" },
    launcher: { repo: "jenesis/jenesis-launcher" },
    modules: { repo: "jenesis/jenesis-modules" },
    repository: { repo: "jenesis/jenesis-repository" },
  },
};
