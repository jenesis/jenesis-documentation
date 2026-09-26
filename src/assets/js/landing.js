// The landing pages' one behaviour: tabs that follow the ARIA tabs pattern. Tab lists marked data-tabs-sync move
// together: choosing a tab with a given data-key selects the tab with that key in every synced list on the page,
// and the page is scrolled by however much the lists above the chosen one grew or shrank, so it does not jump.
(function () {
  var groups = [];

  document.querySelectorAll("[data-tabs]").forEach(function (tabs) {
    var list = Array.prototype.slice.call(tabs.querySelectorAll('[role="tab"]'));
    var synced = tabs.hasAttribute("data-tabs-sync");

    function show(tab) {
      list.forEach(function (other) {
        var selected = other === tab;
        other.setAttribute("aria-selected", selected ? "true" : "false");
        other.tabIndex = selected ? 0 : -1;
        document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
      });
    }

    function select(tab) {
      if (!synced) {
        show(tab);
        return;
      }
      var key = tab.getAttribute("data-key");
      var before = tab.getBoundingClientRect().top;
      groups.forEach(function (group) {
        var match = group.list.filter(function (other) { return other.getAttribute("data-key") === key; })[0];
        if (match) group.show(match);
      });
      window.scrollBy(0, tab.getBoundingClientRect().top - before);
    }

    if (synced) groups.push({ list: list, show: show });

    list.forEach(function (tab, index) {
      tab.addEventListener("click", function () { select(tab); });
      tab.addEventListener("keydown", function (event) {
        var next = null;
        if (event.key === "ArrowRight") next = list[(index + 1) % list.length];
        if (event.key === "ArrowLeft") next = list[(index - 1 + list.length) % list.length];
        if (event.key === "Home") next = list[0];
        if (event.key === "End") next = list[list.length - 1];
        if (next) {
          event.preventDefault();
          select(next);
          next.focus();
        }
      });
    });
  });
})();
