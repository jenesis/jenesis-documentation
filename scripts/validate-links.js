// Validates the built site: every internal reference on every page resolves, and every #fragment names an id on the
// page it points to. A reference is an href, src or srcset in an HTML file, or a url() in a stylesheet. Pages are read
// from disk rather than crawled from the landing page, so a page nothing links to is checked as well. Links that leave
// the site (https:, mailto:, ...) are not followed. Exits non-zero, listing each broken reference, when one fails.

import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, relative, extname, sep } from "node:path";

const root = process.argv[2] ?? "_site";

const files = [];
(function walk(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) walk(path);
    else files.push(path);
  }
})(root);

const entities = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
const decodeEntities = (text) => text.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (match, name) =>
  name[0] === "#"
    ? String.fromCodePoint(name[1] === "x" || name[1] === "X" ? parseInt(name.slice(2), 16) : Number(name.slice(1)))
    : entities[name.toLowerCase()] ?? match);

// The tags of a page with their attributes. Comments and the bodies of scripts are skipped, and a quoted value may
// hold a `>`. Text between tags is never markup: a `<` in prose or in a code sample is escaped as &lt;.
function tags(html) {
  const found = [];
  const source = html.replace(/<!--[\s\S]*?-->/g, "").replace(/(<script\b[^>]*>)[\s\S]*?(<\/script>)/gi, "$1$2");
  for (const tag of source.matchAll(/<([a-zA-Z][^\s/>]*)((?:\s+[^\s=/>]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>/g)) {
    const attributes = {};
    for (const attribute of tag[2].matchAll(/([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g)) {
      attributes[attribute[1].toLowerCase()] = decodeEntities(attribute[2] ?? attribute[3] ?? attribute[4] ?? "");
    }
    found.push({ name: tag[1].toLowerCase(), attributes });
  }
  return found;
}

// Each page's ids, read once and kept for the fragment checks.
const ids = new Map();
function idsOf(file) {
  if (!ids.has(file)) {
    const set = new Set();
    for (const { name, attributes } of tags(readFileSync(file, "utf8"))) {
      if (attributes.id) set.add(attributes.id);
      if (name === "a" && attributes.name) set.add(attributes.name);
    }
    ids.set(file, set);
  }
  return ids.get(file);
}

// The file a URL path is served from: a folder serves its index.html, as GitHub Pages does.
function served(path) {
  const file = join(root, ...path.split("/").filter(Boolean));
  if (existsSync(file) && statSync(file).isFile()) return file;
  const index = join(file, "index.html");
  return existsSync(index) ? index : null;
}

const problems = [];
let checked = 0;

function check(file, reference) {
  if (!reference || /^[a-z][a-z0-9+.-]*:/i.test(reference) || reference.startsWith("//")) return;
  checked++;
  const hash = reference.indexOf("#");
  const address = (hash < 0 ? reference : reference.slice(0, hash)).replace(/\?.*$/, "");
  const fragment = hash < 0 ? null : reference.slice(hash + 1);
  let path;
  try {
    const page = "/" + relative(root, file).split(sep).join("/");
    path = decodeURIComponent(new URL(address || page, "https://site" + page).pathname);
  } catch {
    problems.push(`${file}: ${reference} is not a valid URL`);
    return;
  }
  const target = served(path);
  if (!target) {
    problems.push(`${file}: ${reference} - nothing is served at ${path}`);
    return;
  }
  if (fragment && extname(target) === ".html" && !idsOf(target).has(decodeURIComponent(fragment))) {
    problems.push(`${file}: ${reference} - no id "${decodeURIComponent(fragment)}" on ${relative(root, target)}`);
  }
}

for (const file of files) {
  if (file.endsWith(".html")) {
    for (const { attributes } of tags(readFileSync(file, "utf8"))) {
      check(file, attributes.href);
      check(file, attributes.src);
      for (const candidate of (attributes.srcset ?? "").split(",")) check(file, candidate.trim().split(/\s+/)[0]);
    }
  } else if (file.endsWith(".css")) {
    for (const url of readFileSync(file, "utf8").matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)/g)) {
      check(file, url[1] ?? url[2] ?? url[3]);
    }
  }
}

const pages = files.filter((file) => file.endsWith(".html")).length;
if (problems.length) {
  console.error(problems.join("\n"));
  console.error(`\n${problems.length} broken of ${checked} internal references on ${pages} pages.`);
  process.exit(1);
}
console.log(`${checked} internal references on ${pages} pages, all resolved.`);
