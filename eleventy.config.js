// Eleventy configuration for the Jenesis documentation site.
//
// Content model: every documentation page carries front matter { section, order, title }.
// `section` is one of tool | jpx | launcher | modules | repository and groups the page into that
// tool's left-hand menu; `order` sorts it within the menu. A new chapter is a single Markdown
// file with that front matter - it appears in the menu automatically, so adding a chapter never
// has to touch navigation.

import Prism from "prismjs";
import loadLanguages from "prismjs/components/index.js";
import demos from "./src/_data/demos.js";

// The languages a code fence may name. A fence with no language, or `text`, is output, a tree or a path and
// stays plain; any other name fails the build, so a typo does not silently ship an uncoloured sample.
const highlighted = ["bash", "java", "properties", "xml", "kotlin", "json", "dockerfile", "yaml", "gitignore"];
loadLanguages(highlighted);

export default function (eleventy) {
  // Static assets pass through untouched (CSS, JS, logos, fonts, the CNAME).
  eleventy.addPassthroughCopy({ "src/assets": "assets" });
  eleventy.addPassthroughCopy({ "src/CNAME": "CNAME" });
  eleventy.addPassthroughCopy({ "src/KEYS": "KEYS" });

  // Every chapter heading gets an id derived from its own words, so a section can be linked to and the
  // copy-link affordance in anchor.js has something to copy. A heading that already carries a hand-written
  // anchor (`## <span id="...">`) keeps only that one: those ids are published link targets, they do not
  // always match the wording, and a second id on the heading would duplicate them.
  // Inline code offers a line break after the characters a path, a URL or a dotted key is built from - `/`, `.`,
  // `=`, `?`, `&` and `_` - so a long one wraps at a seam rather than mid-word, and a table holding one can fit its
  // column without breaking anything anywhere. A <wbr> is invisible and is not copied with the text.
  eleventy.amendLibrary("md", (markdown) => {
    const escape = markdown.utils.escapeHtml;
    markdown.renderer.rules.code_inline = (tokens, index, options, env, self) => {
      const token = tokens[index];
      const content = Array.from(token.content, (character) =>
        escape(character) + ("/.=?&_".includes(character) ? "<wbr>" : "")).join("");
      return `<code${self.renderAttrs(token)}>${content}</code>`;
    };
  });

  // Code samples are coloured when the site is built: Prism wraps each token in a <span class="token ...">, and
  // docs.css gives the few token kinds a colour. The page ships no script for it. Returning "" leaves a plain
  // block to markdown-it, which escapes it as before.
  eleventy.amendLibrary("md", (markdown) => {
    markdown.set({
      highlight: (code, language) => {
        if (!language || language === "text") return "";
        if (!highlighted.includes(language)) throw new Error(`Code fence language "${language}" is not highlighted; add it to eleventy.config.js`);
        return Prism.highlight(code, Prism.languages[language], language);
      },
    });
  });

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

  // `{% demos 18, 20 %}` closes a section with the demos that exercise it, one link per line, each named
  // "Demo <number>: <name>" from demos.js. An unknown number fails the build rather than printing a dead link.
  const demoByNumber = new Map(
    demos.groups.flatMap((group) => group.demos).map((demo) => [Number(demo.slug.split("-")[1]), demo])
  );
  eleventy.addShortcode("demos", (...numbers) => {
    const items = numbers.map((number) => {
      const demo = demoByNumber.get(Number(number));
      if (!demo) throw new Error(`No demo numbered ${number} in src/_data/demos.js`);
      return `<li><a href="${demos.repo}/${demo.slug}"><span>Demo ${Number(number)}: ${demo.name}</span></a></li>`;
    });
    return `<ul class="demo-links">${items.join("")}</ul>`;
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
    { key: "repository", url: "/repository/", logo: "jenesis-repository", repo: "https://github.com/jenesis/jenesis-repository", title: "Jenesis Repository", tagline: "A module-aware, database-free artifact repository for Maven, npm, PyPI, containers and twenty more ecosystems, with a gate for what comes in." },
  ]);

  return {
    dir: { input: "src", output: "_site", includes: "_includes", data: "_data" },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
