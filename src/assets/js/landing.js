// The landing pages' behaviour: tabs that follow the ARIA tabs pattern, and buttons that copy a text to the clipboard.
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

(function () {
  function copy(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    var field = document.createElement("textarea");
    field.value = text;
    field.setAttribute("readonly", "");
    field.setAttribute("aria-hidden", "true");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();
    var copied = document.execCommand("copy");
    document.body.removeChild(field);
    return copied ? Promise.resolve() : Promise.reject();
  }

  document.querySelectorAll("[data-copy]").forEach(function (button) {
    var label = button.textContent;
    button.setAttribute("aria-live", "polite");
    button.addEventListener("click", function () {
      copy(document.getElementById(button.getAttribute("data-copy")).textContent).then(function () {
        button.textContent = "Copied";
      }, function () {
        button.textContent = "Select and copy";
      });
      setTimeout(function () { button.textContent = label; }, 2000);
    });
  });
})();
