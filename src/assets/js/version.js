// Fill each landing-page tile's version chip from the GitHub API at page load. Every tile carries the
// repository its component releases from, and the newest release tag is read at run time rather than baked
// into the page, so a component that releases never leaves a superseded number on the site.
//
// Nothing is rendered until a lookup answers: the chips ship empty and hidden, and this script reveals one
// only once it holds a real tag. A failed or rate-limited request - or no JavaScript at all - therefore
// shows no version, which is the honest answer, rather than one that may be out of date.
//
// Results are cached per session, so moving around the site re-reads them rather than re-fetching.
(function () {
  var chips = document.querySelectorAll("[data-release-repo]");
  if (!chips.length) return;

  // The build tool and jpx share a repository, so group the chips and fetch each repository once.
  var byRepo = {};
  chips.forEach(function (chip) {
    var repo = chip.getAttribute("data-release-repo");
    (byRepo[repo] = byRepo[repo] || []).push(chip);
  });

  var cache = null;
  try {
    cache = window.sessionStorage;
  } catch (e) {
    // Storage can be denied outright; the fetches below still work without it.
  }

  Object.keys(byRepo).forEach(function (repo) {
    var key = "jenesis-release:" + repo;
    var show = function (tag) {
      if (!tag) return;
      byRepo[repo].forEach(function (chip) {
        chip.textContent = tag;
        chip.hidden = false;
      });
    };

    var cached = cache && cache.getItem(key);
    if (cached) {
      show(cached);
      return;
    }

    fetch("https://api.github.com/repos/" + repo + "/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then(function (response) { return response.ok ? response.json() : null; })
      .then(function (release) {
        if (!release || !release.tag_name) return;
        if (cache) cache.setItem(key, release.tag_name);
        show(release.tag_name);
      })
      .catch(function () {});
  });
})();
