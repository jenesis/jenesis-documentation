// The landing pages' one behaviour: tabs that follow the ARIA tabs pattern.
(function () {
  document.querySelectorAll("[data-tabs]").forEach(function (tabs) {
    var list = Array.prototype.slice.call(tabs.querySelectorAll('[role="tab"]'));

    function select(tab) {
      list.forEach(function (other) {
        var selected = other === tab;
        other.setAttribute("aria-selected", selected ? "true" : "false");
        other.tabIndex = selected ? 0 : -1;
        document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
      });
    }

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
