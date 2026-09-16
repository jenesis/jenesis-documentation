// Section links: clicking a chapter heading copies a link to that heading to the clipboard, so a reader can
// point someone at the exact section they are reading. The ids come from the build - eleventy.config.js gives
// every h2 and h3 one, slugged from its own words.
//
// Keyboard and screen readers reach the same thing: each heading carries a real link, so it is tabbable and
// announced, and the outcome is spoken through a live region rather than shown only in colour.
(function () {
  var article = document.querySelector(".docs-content article");
  if (!article) return;

  var announcer = document.createElement("p");
  announcer.className = "app-sr-only";
  announcer.setAttribute("role", "status");
  announcer.setAttribute("aria-live", "polite");
  article.appendChild(announcer);

  function announce(message) {
    // Clearing first makes a repeated message a change again, which is what a live region announces.
    announcer.textContent = "";
    setTimeout(function () {
      announcer.textContent = message;
    }, 60);
  }

  function copy(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    // A preview served over plain http has no clipboard API; the selection route still works there.
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

  Array.prototype.forEach.call(article.querySelectorAll("h2, h3"), function (heading) {
    var id = heading.id;
    if (!id) return;

    var link = document.createElement("a");
    link.className = "docs-anchor__link";
    link.href = "#" + id;
    link.textContent = "#";
    link.setAttribute("aria-label", "Copy link to this section");
    link.title = "Copy link to this section";
    heading.classList.add("docs-anchor");
    heading.appendChild(link);

    var clearing;

    heading.addEventListener("click", function (event) {
      // A click that ends a text selection is a selection, not a link; and a link the chapter itself wrote
      // into the heading keeps its own behaviour.
      if (window.getSelection && String(window.getSelection())) return;
      var clicked = event.target.closest ? event.target.closest("a") : null;
      if (clicked && clicked !== link) return;

      event.preventDefault();
      // replaceState rather than location.hash: the address bar carries the link without the page jumping
      // away from the heading the reader just clicked.
      history.replaceState(null, "", "#" + id);
      copy(location.href).then(
        function () {
          link.setAttribute("data-copied", "");
          clearTimeout(clearing);
          clearing = setTimeout(function () {
            link.removeAttribute("data-copied");
          }, 1600);
          announce("Link to this section copied");
        },
        function () {
          announce("Could not copy - the link is in the address bar");
        }
      );
    });
  });

  // Arriving on a link moves the reading position, so move the keyboard focus with it: the next Tab then
  // continues from the section the reader landed on rather than from the top of the page.
  function focusTarget() {
    if (!location.hash) return;
    // By id rather than by selector: an advisory anchor such as #jenreg.auth.open is a valid id but not a
    // valid id selector.
    var target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (!target) return;
    target.setAttribute("tabindex", "-1");
    target.focus({ preventScroll: true });
  }

  window.addEventListener("hashchange", focusTarget);
  focusTarget();
})();
