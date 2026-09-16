// Eleventy configuration for the Jenesis documentation site.
//
// Content model: every documentation page carries front matter { section, order, title }.
// `section` is one of tool | jpx | launcher | modules | repository and groups the page into that
// tool's left-hand menu; `order` sorts it within the menu. A new chapter is a single Markdown
// file with that front matter - it appears in the menu automatically, so adding a chapter never
// has to touch navigation.

export default function (eleventy) {
  // Static assets pass through untouched (CSS, JS, logos, fonts, the CNAME).
  eleventy.addPassthroughCopy({ "src/assets": "assets" });
  eleventy.addPassthroughCopy({ "src/CNAME": "CNAME" });
  eleventy.addPassthroughCopy({ "src/KEYS": "KEYS" });

  // Every chapter heading gets an id derived from its own words, so a section can be linked to and the
  // copy-link affordance in anchor.js has something to copy. A heading that already carries a hand-written
  // anchor (`## <span id="...">`) keeps only that one: those ids are published link targets, they do not
  // always match the wording, and a second id on the heading would duplicate them.
  eleventy.amendLibrary("md", (markdown) => {
    markdown.core.ruler.push("headingIds", (state) => {
      const taken = new Set();
      for (const token of state.tokens) {
        const html = token.type === "html_block"
          ? token.content
          : (token.children ?? [])
              .filter((child) => child.type === "html_inline")
              .map((child) => child.content)
              .join(" ");
        for (const match of html.matchAll(/\bid="([^"]+)"/g)) taken.add(match[1]);
      }
      for (const [index, heading] of state.tokens.entries()) {
        if (heading.type !== "heading_open" || (heading.tag !== "h2" && heading.tag !== "h3")) continue;
        const inline = state.tokens[index + 1];
        if (!inline || inline.type !== "inline" || /\bid="/.test(inline.content)) continue;
        const slug = (inline.children ?? [])
          .filter((child) => child.type === "text" || child.type === "code_inline")
          .map((child) => child.content)
          .join(" ")
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-+|-+$/g, "");
        if (!slug) continue;
        let id = slug;
        for (let suffix = 2; taken.has(id); suffix++) id = `${slug}-${suffix}`;
        taken.add(id);
        heading.attrSet("id", id);
      }
    });
  });

  // One collection per tool section, sorted by the page's `order`, so the sidebar and the
  // prev/next links are derived from the files that actually exist.
  for (const section of ["tool", "jpx", "launcher", "modules", "repository"]) {
    eleventy.addCollection(section, (api) =>
      api
        .getFilteredByGlob([`src/${section}/**/*.md`, `src/${section}/**/*.njk`])
        .sort((a, b) => (a.data.order ?? 0) - (b.data.order ?? 0))
    );
  }

  // The five sections as an ordered list, for the landing page and the top navigation.
  eleventy.addGlobalData("sections", () => [
    { key: "tool", url: "/tool/", logo: "jenesis-tool", repo: "https://github.com/jenesis/jenesis", title: "Jenesis", tagline: "The Java-native build tool." },
    { key: "jpx", url: "/jpx/", logo: "jenesis-jpx", repo: "https://github.com/jenesis/jenesis", title: "Jenesis jpx", tagline: "Runs any published module or Maven artifact with one command - npx for Java." },
    { key: "launcher", url: "/launcher/", logo: "jenesis-launcher", repo: "https://github.com/jenesis/jenesis-launcher", title: "Jenesis Launcher", tagline: "Executable jars that keep real Java modularity - no fat-jar merge." },
    { key: "modules", url: "/modules/", logo: "jenesis-modules", repo: "https://github.com/jenesis/jenesis-modules", title: "Jenesis Module Index", tagline: "Every module name declared on Maven Central, resolved to the artifact behind it - one owner per name." },
    { key: "repository", url: "/repository/", logo: "jenesis-repository", repo: "https://github.com/jenesis/jenesis-repository", title: "Jenesis Repository", tagline: "A module-aware, database-free artifact repository for Maven, modules, OCI and raw files - a modular jar published the Maven way is a published module too." },
  ]);

  return {
    dir: { input: "src", output: "_site", includes: "_includes", data: "_data" },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
