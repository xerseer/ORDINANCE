#!/usr/bin/env node
/*
	Builds the documentation site into docs/, which GitHub Pages serves from
	main. docs/ is generated: edit site/ and rebuild, and commit both. CI
	fails if the committed docs/ does not match a fresh build.

	Pages are written in site/*.md, in a small Markdown dialect (see render()).
	The parts that describe the code are not written by hand: the config
	reference, the preset comparison and the example weapons are read from the
	Luau sources, so they cannot fall out of date. The build fails when a
	config section or a public API function has no documentation, so CI
	catches a setting added without docs.

	Usage:
		node tools/docs.mjs              build once
		node tools/docs.mjs --serve      build, serve on 127.0.0.1:4173, rebuild on change
*/

import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, watch, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const docsDir = join(root, "site");
const outDir = join(root, "docs");
const REPO = "https://github.com/xerseer/ORDINANCE";

const read = (path) => readFileSync(join(root, path), "utf8").replace(/\r\n/g, "\n");

/* ------------------------------------------------------------------------ */
/* Luau table literals                                                       */
/* ------------------------------------------------------------------------ */

// Enough of Luau to read the config files: tables, strings, numbers,
// booleans, constructor calls (kept as text) and `:: type` assertions (skipped).
function tokenize(source) {
	const tokens = [];
	let i = 0;
	while (i < source.length) {
		const c = source[i];
		if (/\s/.test(c)) {
			i++;
		} else if (source.startsWith("--[[", i)) {
			const end = source.indexOf("]]", i);
			i = end < 0 ? source.length : end + 2;
		} else if (source.startsWith("--", i)) {
			const end = source.indexOf("\n", i);
			i = end < 0 ? source.length : end;
		} else if (c === '"' || c === "'") {
			let j = i + 1;
			let value = "";
			while (j < source.length && source[j] !== c) {
				if (source[j] === "\\") {
					const next = source[j + 1];
					value += next === "n" ? "\n" : next === "t" ? "\t" : next;
					j += 2;
				} else {
					value += source[j++];
				}
			}
			tokens.push({ t: "str", v: value });
			i = j + 1;
		} else if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(source[i + 1]))) {
			const match = source.slice(i).match(/^(0x[0-9a-fA-F]+|[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)/);
			tokens.push({ t: "num", v: Number(match[1]) });
			i += match[1].length;
		} else if (/[A-Za-z_]/.test(c)) {
			const match = source.slice(i).match(/^[A-Za-z_][A-Za-z0-9_]*/);
			tokens.push({ t: "id", v: match[0] });
			i += match[0].length;
		} else if (source.startsWith("::", i)) {
			tokens.push({ t: "::" });
			i += 2;
		} else {
			tokens.push({ t: c });
			i++;
		}
	}
	return tokens;
}

function parseValue(tokens, pos, locals) {
	const token = tokens[pos.i];
	let value;
	if (token.t === "{") {
		value = parseTable(tokens, pos, locals);
	} else if (token.t === "str" || token.t === "num") {
		pos.i++;
		value = token.v;
	} else if (token.t === "-" && tokens[pos.i + 1]?.t === "num") {
		pos.i += 2;
		value = -tokens[pos.i - 1].v;
	} else if (token.t === "id") {
		let name = token.v;
		pos.i++;
		while (tokens[pos.i]?.t === "." && tokens[pos.i + 1]?.t === "id") {
			name += "." + tokens[pos.i + 1].v;
			pos.i += 2;
		}
		if (name === "true" || name === "false") {
			value = name === "true";
		} else if (name === "nil") {
			value = null;
		} else if (name === "math.huge") {
			value = Infinity;
		} else if (tokens[pos.i]?.t === "(") {
			pos.i++;
			const args = [];
			while (tokens[pos.i].t !== ")") {
				args.push(parseValue(tokens, pos, locals));
				if (tokens[pos.i].t === ",") pos.i++;
			}
			pos.i++;
			value = { call: name, args };
		} else if (name in locals) {
			value = locals[name];
		} else {
			throw new Error(`docs: unknown name ${name}`);
		}
	} else {
		throw new Error(`docs: unexpected ${token.t} in a table literal`);
	}
	// Skip a type assertion up to the end of the entry.
	if (tokens[pos.i]?.t === "::") {
		let depth = 0;
		pos.i++;
		while (pos.i < tokens.length) {
			const t = tokens[pos.i].t;
			if (depth === 0 && (t === "," || t === ";" || t === "}" || t === ")")) break;
			if (t === "{" || t === "(" || t === "[") depth++;
			if (t === "}" || t === ")" || t === "]") depth--;
			pos.i++;
		}
	}
	return value;
}

function parseTable(tokens, pos, locals) {
	pos.i++; // {
	const list = [];
	const map = new Map();
	while (tokens[pos.i].t !== "}") {
		const token = tokens[pos.i];
		if (token.t === "[") {
			pos.i++;
			const key = parseValue(tokens, pos, locals);
			pos.i += 2; // ] =
			map.set(key, parseValue(tokens, pos, locals));
		} else if (token.t === "id" && tokens[pos.i + 1]?.t === "=") {
			pos.i += 2;
			map.set(token.v, parseValue(tokens, pos, locals));
		} else {
			list.push(parseValue(tokens, pos, locals));
		}
		if (tokens[pos.i].t === "," || tokens[pos.i].t === ";") pos.i++;
	}
	pos.i++; // }
	if (map.size === 0) return list.length > 0 ? list : {};
	return Object.fromEntries(map);
}

// Parses the value assigned to `local NAME` (or after the first top-level
// `return`), resolving earlier locals that are themselves literals.
function luauValue(source, name, locals = {}) {
	const pattern = name ? new RegExp(`local ${name}(?::[^=\\n]*)?\\s*=\\s*`) : /^return\s+/m;
	const match = source.match(pattern);
	if (!match) throw new Error(`docs: could not find ${name ?? "return"}`);
	const tokens = tokenize(source.slice(match.index + match[0].length));
	return parseValue(tokens, { i: 0 }, locals);
}

const isList = (value) => Array.isArray(value);
const isMap = (value) => value !== null && typeof value === "object" && !isList(value) && !value.call;

/* ------------------------------------------------------------------------ */
/* Framework data                                                            */
/* ------------------------------------------------------------------------ */

const PRESET_ORDER = ["Standard", "Arcade", "Tactical", "Realistic"];
const rank = (id) => (PRESET_ORDER.includes(id) ? PRESET_ORDER.indexOf(id) : PRESET_ORDER.length);

function loadFramework() {
	const schemaSource = read("src/Framework/Config/Schema.luau");
	const FIRE_MODES = luauValue(schemaSource, "FIRE_MODES");
	const rules = luauValue(schemaSource, "RULES", { FIRE_MODES });
	const globalOnly = Object.keys(luauValue(schemaSource, "GLOBAL_ONLY"));
	const weaponOnly = Object.keys(luauValue(schemaSource, "WEAPON_ONLY"));
	const defaults = luauValue(read("src/Framework/Config/Defaults.luau"), "Defaults");
	const version = read("src/Framework/Version.luau").match(/return\s+"([^"]+)"/)[1];

	const loadFolder = (folder) =>
		readdirSync(join(root, folder))
			.sort((a, b) => a.localeCompare(b, "en"))
			.map((entry) => {
				const path = statSync(join(root, folder, entry)).isDirectory()
					? `${folder}/${entry}/init.luau`
					: `${folder}/${entry}`;
				const source = read(path);
				const id = entry.replace(/\.luau$/, "");
				const header = source.match(/^--\[\[\n([\s\S]*?)\]\]/)?.[1] ?? "";
				const blurb = header
					.split("\n\n")
					.slice(0, 1)
					.join("")
					.split("\n")
					.slice(1)
					.map((line) => line.trim())
					.join(" ");
				return { id, path, value: luauValue(source), blurb };
			});

	return {
		rules,
		globalOnly,
		weaponOnly,
		defaults,
		version,
		// Mildest to strictest, then any others alphabetically.
		presets: loadFolder("src/Presets").sort((a, b) => rank(a.id) - rank(b.id)),
		weapons: loadFolder("src/Weapons"),
		api: [...read("src/init.luau").matchAll(/^function Ordnance\.(\w+)/gm)].map((m) => m[1]),
		signals: [...read("src/init.luau").matchAll(/^Ordnance\.(\w+) = Events\./gm)].map((m) => m[1]),
	};
}

// Every leaf setting as [path, default].
function leaves(table, prefix, rules, out = []) {
	for (const [key, value] of Object.entries(table)) {
		const path = prefix ? `${prefix}.${key}` : key;
		const free = rules[path]?.kind === "free";
		if (isMap(value) && !free && Object.keys(value).length > 0) {
			leaves(value, path, rules, out);
		} else {
			out.push([path, value]);
		}
	}
	return out;
}

/* ------------------------------------------------------------------------ */
/* Formatting                                                                */
/* ------------------------------------------------------------------------ */

const escapeHtml = (text) =>
	String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function luau(value) {
	if (value === null) return "nil";
	if (value === Infinity) return "math.huge";
	if (typeof value === "string") return JSON.stringify(value);
	if (typeof value === "number" || typeof value === "boolean") return String(value);
	if (value.call) return `${value.call}(${value.args.map(luau).join(", ")})`;
	if (isList(value)) return value.length === 0 ? "{}" : `{ ${value.map(luau).join(", ")} }`;
	const entries = Object.entries(value);
	return entries.length === 0 ? "{}" : `{ ${entries.map(([k, v]) => `${k} = ${luau(v)}`).join(", ")} }`;
}

function valueCell(value) {
	let html = `<code>${escapeHtml(luau(value))}</code>`;
	if (value?.call === "Color3.fromRGB") {
		html = `<span class="swatch" style="background:rgb(${value.args.join(",")})"></span>${html}`;
	}
	return html;
}

function accepts(rule, value) {
	if (!rule) return typeOf(value);
	if (rule.kind === "keys") return "list of key names";
	if (rule.kind === "choices") return `list of ${rule.choices.map((c) => `<code>${c}</code>`).join(" ")}`;
	if (rule.kind === "strings") return "list of names";
	if (rule.kind === "model") return "child name or Instance";
	if (rule.kind === "free") return "table";
	if (rule.kind === "frame") return "six numbers";
	if (rule.choices) return rule.choices.map((c) => `<code>${c}</code>`).join(" ");
	if (typeof value === "number") {
		const whole = rule.integer ? "whole, " : "";
		if (rule.min !== undefined && rule.max !== undefined) return `${whole}${rule.min} to ${rule.max}`;
		if (rule.min !== undefined) return `${whole}${rule.min} or more`;
		return rule.integer ? "whole number" : "number";
	}
	return typeOf(value);
}

function typeOf(value) {
	if (typeof value === "boolean") return "true or false";
	if (typeof value === "number") return "number";
	if (typeof value === "string") return value.startsWith("rbxasset") ? "sound id" : "text";
	if (value?.call) return value.call.split(".")[0];
	if (isList(value)) return "list";
	return "table";
}

/* ------------------------------------------------------------------------ */
/* Generated blocks                                                          */
/* ------------------------------------------------------------------------ */

function makeDirectives(fw) {
	const covered = new Set();

	const directives = {
		version: () => fw.version,

		// One table per top-level config section.
		config(args) {
			const section = args[0];
			const value = fw.defaults[section];
			if (value === undefined) throw new Error(`docs: no config section ${section}`);
			covered.add(section);
			const rows = isMap(value) && fw.rules[section]?.kind !== "free" ? leaves(value, section, fw.rules) : [[section, value]];
			const body = rows
				.map(([path, def]) => {
					const rule = fw.rules[path];
					const shortPath = path === section ? path : path.slice(section.length + 1);
					return `<tr data-search="${escapeHtml((path + " " + (rule?.doc ?? "")).toLowerCase())}"><td><code id="${slug(path)}">${escapeHtml(shortPath)}</code></td><td>${valueCell(def)}</td><td>${accepts(rule, def)}</td><td>${inline(rule?.doc ?? "")}</td></tr>`;
				})
				.join("\n");
			let scope = "";
			if (fw.globalOnly.includes(section)) scope = `<p class="scope">Global only: read from <code>Ordnance.Config</code> or a preset. A weapon that sets it is told so and ignored.</p>`;
			if (fw.weaponOnly.includes(section)) scope = `<p class="scope">Weapon only: belongs in a weapon module.</p>`;
			return `${scope}<div class="tbl"><table class="ref"><thead><tr><th>Setting</th><th>Default</th><th>Accepts</th><th>What it does</th></tr></thead><tbody>\n${body}\n</tbody></table></div>`;
		},

		// The identity settings, which live at the top level.
		"config-identity"() {
			const keys = Object.keys(fw.defaults).filter((key) => !isMap(fw.defaults[key]) || fw.rules[key]?.kind === "free");
			keys.forEach((key) => covered.add(key));
			const body = keys
				.map((key) => {
					const rule = fw.rules[key];
					const where = fw.globalOnly.includes(key) ? "Global" : fw.weaponOnly.includes(key) ? "Weapon" : "Both";
					return `<tr data-search="${escapeHtml((key + " " + (rule?.doc ?? "")).toLowerCase())}"><td><code id="${slug(key)}">${key}</code></td><td>${valueCell(fw.defaults[key])}</td><td>${where}</td><td>${inline(rule?.doc ?? "")}</td></tr>`;
				})
				.join("\n");
			return `<div class="tbl"><table class="ref"><thead><tr><th>Setting</th><th>Default</th><th>Where</th><th>What it does</th></tr></thead><tbody>\n${body}\n</tbody></table></div>`;
		},

		// Every setting any preset changes, side by side with the default.
		presets() {
			const columns = fw.presets.filter((p) => p.id !== "Standard");
			const paths = new Set();
			for (const preset of columns) {
				for (const [path] of leaves(preset.value, "", fw.rules)) paths.add(path);
			}
			const defaultsFlat = Object.fromEntries(leaves(fw.defaults, "", fw.rules));
			const order = Object.keys(defaultsFlat);
			const sorted = [...paths].sort((a, b) => order.indexOf(a) - order.indexOf(b));
			const head = `<tr><th>Setting</th><th>Default</th>${columns.map((p) => `<th>${p.id}</th>`).join("")}</tr>`;
			const body = sorted
				.map((path) => {
					const cells = columns.map((preset) => {
						const value = path.split(".").reduce((t, k) => (t == null ? undefined : t[k]), preset.value);
						return `<td>${value === undefined ? `<span class="dim">–</span>` : `<code>${escapeHtml(luau(value))}</code>`}</td>`;
					});
					return `<tr><td><a href="config.html#${slug(path)}"><code>${path}</code></a></td><td><code>${escapeHtml(luau(defaultsFlat[path]))}</code></td>${cells.join("")}</tr>`;
				})
				.join("\n");
			return `<div class="tbl"><table class="compare"><thead>${head}</thead><tbody>\n${body}\n</tbody></table></div>`;
		},

		"preset-list"() {
			return `<dl class="defs">${fw.presets
				.map((p) => `<dt><code>${p.id}</code></dt><dd>${inline(p.blurb)}</dd>`)
				.join("")}</dl>`;
		},

		// The example weapons with their headline numbers.
		weapons() {
			const get = (w, path) => {
				const own = path.split(".").reduce((t, k) => (t == null ? undefined : t[k]), w.value);
				return own ?? path.split(".").reduce((t, k) => t[k], fw.defaults);
			};
			const body = fw.weapons
				.map((w) => {
					const projectile = get(w, "Ballistics.Type") === "Projectile";
					const pellets = get(w, "Fire.Pellets");
					const damage = projectile && get(w, "Ballistics.Explosive.Enabled")
						? `${get(w, "Ballistics.Explosive.Damage")} blast`
						: `${get(w, "Damage.Base")}${pellets > 1 ? ` × ${pellets}` : ""}`;
					const action = get(w, "Fire.Action");
					const modes = get(w, "Fire.Modes").join(", ");
					return `<tr><td><a href="${REPO}/tree/main/${w.path.replace(/\/init\.luau$/, "")}"><code>${w.id}</code></a></td><td>${escapeHtml(w.value.Description ?? "")}</td><td>${modes}${action !== "SelfLoading" ? `, ${action.toLowerCase()}` : ""}</td><td>${get(w, "Fire.RPM")}</td><td>${get(w, "Ammo.Magazine")}</td><td>${damage}</td></tr>`;
				})
				.join("\n");
			return `<div class="tbl"><table><thead><tr><th>Module</th><th>What it is</th><th>Fire</th><th>RPM</th><th>Mag</th><th>Damage</th></tr></thead><tbody>\n${body}\n</tbody></table></div>`;
		},

		// The source of an example file, highlighted.
		source(args) {
			const path = args[0];
			const label = path.replace(/^src\//, "").replace(/\//g, ".").replace(/\.init\.luau$|\.luau$/, "");
			return codeBlock(read(path).trimEnd(), "lua", label);
		},
	};

	directives.check = () => {
		const missing = Object.keys(fw.defaults).filter((key) => !covered.has(key));
		if (missing.length > 0) {
			throw new Error(`docs: config sections with no reference table: ${missing.join(", ")}`);
		}
	};
	return directives;
}

/* ------------------------------------------------------------------------ */
/* Markdown                                                                  */
/* ------------------------------------------------------------------------ */

const KEYWORDS = new Set(
	"local function end return if then else elseif for in do while repeat until not and or nil true false break continue export type typeof".split(" "),
);
const TOKEN = /(--\[\[[\s\S]*?\]\]|--[^\n]*)|("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`)|(\b\d+(?:\.\d+)?\b)|([A-Za-z_]\w*)(?=\s*\()|([A-Za-z_]\w*)/g;

function highlight(source) {
	let out = "";
	let last = 0;
	let match;
	TOKEN.lastIndex = 0;
	while ((match = TOKEN.exec(source))) {
		out += escapeHtml(source.slice(last, match.index));
		const text = escapeHtml(match[0]);
		if (match[1]) out += `<span class="tk-com">${text}</span>`;
		else if (match[2]) out += `<span class="tk-str">${text}</span>`;
		else if (match[3]) out += `<span class="tk-num">${text}</span>`;
		else if (match[4]) out += KEYWORDS.has(match[4]) ? `<span class="tk-kw">${text}</span>` : `<span class="tk-fn">${text}</span>`;
		else out += KEYWORDS.has(match[5]) ? `<span class="tk-kw">${text}</span>` : text;
		last = TOKEN.lastIndex;
	}
	return out + escapeHtml(source.slice(last));
}

function codeBlock(source, lang, label) {
	const body = lang === "lua" || lang === "luau" ? highlight(source) : escapeHtml(source);
	const labelHtml = label ? `<div class="label">${escapeHtml(label)}</div>` : "";
	return `<div class="code">${labelHtml}<pre><code>${body}</code></pre></div>`;
}

const slug = (text) =>
	text
		.toLowerCase()
		.replace(/<[^>]+>/g, "")
		.replace(/[`*]/g, "")
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-|-$/g, "");

function inline(text) {
	const codes = [];
	let html = String(text).replace(/`([^`]+)`/g, (_, code) => {
		codes.push(`<code>${escapeHtml(code)}</code>`);
		return `\u0000${codes.length - 1}\u0000`;
	});
	html = escapeHtml(html)
		.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
		.replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>")
		.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, href) => {
			const external = /^https?:/.test(href);
			return external
				? `<a href="${href}" target="_blank" rel="noopener">${label}&nbsp;↗</a>`
				: `<a href="${href}">${label}</a>`;
		})
		.replace(/ -- /g, " – ");
	return html.replace(/\u0000(\d+)\u0000/g, (_, index) => codes[Number(index)]);
}

/*
	The dialect:
		title: / description: / order: lines, then ---          front matter
		# Title                                                  the page heading; the next paragraph is the lede
		## Section {#id}                                         a section, listed in the rail
		### Heading
		paragraphs, - lists, 1. lists, | tables |
		```lua Label                                             code with an optional label
		> text                                                   a note
		> Limit: text                                            a Roblox limit, said plainly
		:::pair  ...  :::                                        two blocks side by side
		{{name args}}                                            a generated block
		<raw html>                                               passed through
*/
function render(markdown, directives) {
	const [front, ...rest] = markdown.split(/^---$/m);
	const meta = Object.fromEntries(
		front
			.trim()
			.split("\n")
			.map((line) => {
				const at = line.indexOf(":");
				return [line.slice(0, at).trim(), line.slice(at + 1).trim()];
			}),
	);
	const lines = rest.join("---").split("\n");
	const out = [];
	const sections = [];
	let open = false;
	let title = meta.title;
	let wantLede = false;
	let i = 0;

	const closeSection = () => {
		if (open) out.push("</section>");
		open = false;
	};

	while (i < lines.length) {
		const line = lines[i];

		if (line.trim() === "") {
			i++;
			continue;
		}

		let match;
		if ((match = line.match(/^# (.+)$/))) {
			title = match[1];
			out.push(`<section id="top"><h1>${inline(match[1])}</h1>`);
			open = true;
			wantLede = true;
			i++;
			continue;
		}
		if ((match = line.match(/^## (.+?)(?:\s+\{#([\w-]+)\})?$/))) {
			closeSection();
			const id = match[2] ?? slug(match[1]);
			sections.push({ id, title: match[1].replace(/`/g, "") });
			out.push(`<section id="${id}"><h2>${inline(match[1])}</h2>`);
			open = true;
			wantLede = false;
			i++;
			continue;
		}
		if ((match = line.match(/^### (.+?)(?:\s+\{#([\w-]+)\})?$/))) {
			const id = match[2] ?? slug(match[1]);
			out.push(`<h3 id="${id}">${inline(match[1])}</h3>`);
			i++;
			continue;
		}
		if ((match = line.match(/^```(\w*)\s*(.*)$/))) {
			const body = [];
			i++;
			while (i < lines.length && !lines[i].startsWith("```")) body.push(lines[i++]);
			i++;
			out.push(codeBlock(body.join("\n"), match[1], match[2]));
			continue;
		}
		if (line.startsWith(":::pair")) {
			out.push(`<div class="pair">`);
			i++;
			continue;
		}
		if (line.trim() === ":::") {
			out.push(`</div>`);
			i++;
			continue;
		}
		if ((match = line.match(/^\{\{([\w-]+)\s*(.*?)\}\}$/))) {
			const fn = directives[match[1]];
			if (!fn) throw new Error(`docs: unknown block {{${match[1]}}}`);
			out.push(fn(match[2] ? match[2].split(/\s+/) : []));
			i++;
			continue;
		}
		if (line.startsWith("<")) {
			const body = [];
			while (i < lines.length && lines[i].trim() !== "") body.push(lines[i++]);
			out.push(body.join("\n"));
			continue;
		}
		if (line.startsWith(">")) {
			const body = [];
			while (i < lines.length && lines[i].startsWith(">")) body.push(lines[i++].replace(/^>\s?/, ""));
			let text = body.join(" ");
			const limit = text.startsWith("Limit:");
			if (limit) text = text.replace(/^Limit:\s*/, "");
			out.push(
				limit
					? `<div class="note limit"><span class="kicker">Roblox limit</span><p>${inline(text)}</p></div>`
					: `<div class="note"><p>${inline(text)}</p></div>`,
			);
			continue;
		}
		if (line.startsWith("|")) {
			const rows = [];
			while (i < lines.length && lines[i].startsWith("|")) rows.push(lines[i++]);
			const cells = (row) => row.replace(/^\||\|$/g, "").split(/(?<!\\)\|/).map((c) => inline(c.trim().replace(/\\\|/g, "|")));
			const head = cells(rows[0]);
			const body = rows.slice(2).map(cells);
			out.push(
				`<div class="tbl"><table><thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${body
					.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`)
					.join("")}</tbody></table></div>`,
			);
			continue;
		}
		if (/^(- |\d+\. )/.test(line)) {
			const ordered = /^\d+\. /.test(line);
			const items = [];
			while (i < lines.length && (/^(- |\d+\. )/.test(lines[i]) || /^\s{2,}\S/.test(lines[i]))) {
				if (/^(- |\d+\. )/.test(lines[i])) items.push(lines[i].replace(/^(- |\d+\. )/, ""));
				else items[items.length - 1] += " " + lines[i].trim();
				i++;
			}
			const tag = ordered ? "ol" : "ul";
			out.push(`<${tag}>${items.map((item) => `<li>${inline(item)}</li>`).join("")}</${tag}>`);
			continue;
		}

		const body = [];
		while (i < lines.length && lines[i].trim() !== "" && !/^(#|```|>|\||- |\d+\. |\{\{|<|:::)/.test(lines[i])) {
			body.push(lines[i++]);
		}
		out.push(`<p${wantLede ? ` class="lede"` : ""}>${inline(body.join(" "))}</p>`);
		wantLede = false;
	}
	closeSection();
	return { meta, title, sections, html: out.join("\n") };
}

/* ------------------------------------------------------------------------ */
/* Pages                                                                     */
/* ------------------------------------------------------------------------ */

function layout(page, pages, version) {
	const rail = pages
		.map((other) => {
			const current = other.file === page.file;
			const link = `<a class="item${current ? " here" : ""}" href="${other.file}"${current ? ' aria-current="page"' : ""}>${escapeHtml(other.meta.nav ?? other.title)}</a>`;
			if (!current || page.sections.length === 0) return link;
			const subs = page.sections
				.map((s) => `<a class="sub" href="#${s.id}">${escapeHtml(s.title)}</a>`)
				.join("");
			return `${link}<div class="subs">${subs}</div>`;
		})
		.join("\n    ");
	const description = escapeHtml(page.meta.description ?? "");
	const docTitle = page.file === "index.html" ? "Ordnance" : `${page.title} – Ordnance`;
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escapeHtml(docTitle)}</title>
<meta name="description" content="${description}">
<meta property="og:title" content="${escapeHtml(docTitle)}">
<meta property="og:description" content="${description}">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Schibsted+Grotesk:wght@400;500;600;700&amp;family=JetBrains+Mono:wght@400;600&amp;display=swap">
<link rel="stylesheet" href="style.css">
</head>
<body>
<div class="shell">
  <nav class="rail" aria-label="Pages">
    <a class="brand" href="index.html">Ordnance</a>
    <span class="ver">v${version}</span>
    <a class="get" href="${REPO}/releases" target="_blank" rel="noopener">Get Ordnance&nbsp;↗</a>
    ${rail}
    <a class="item out" href="${REPO}" target="_blank" rel="noopener">Source&nbsp;↗</a>
  </nav>
  <main>
${page.html}
    <footer>
      <span>Ordnance v${version}. MIT licence.</span>
      <a href="${REPO}/blob/main/site/${page.source}">Edit this page&nbsp;↗</a>
    </footer>
  </main>
</div>
<script src="site.js"></script>
</body>
</html>
`;
}

function build() {
	const fw = loadFramework();
	const directives = makeDirectives(fw);
	const sources = readdirSync(docsDir).filter((file) => file.endsWith(".md"));
	const pages = sources.map((source) => {
		const text = read(`site/${source}`).replace(/\{\{version\}\}/g, fw.version);
		const page = render(text, directives);
		return { ...page, source, file: source === "index.md" ? "index.html" : source.replace(/\.md$/, ".html") };
	});
	pages.sort((a, b) => Number(a.meta.order ?? 99) - Number(b.meta.order ?? 99));
	directives.check();

	// Every public function and signal must appear on the API page.
	const api = pages.find((p) => p.file === "api.html");
	const undocumented = [...fw.api, ...fw.signals].filter((name) => !api?.html.includes(`id="${slug(name)}"`));
	if (undocumented.length > 0) {
		throw new Error(`docs: public API with no entry on the API page: ${undocumented.join(", ")}`);
	}

	rmSync(outDir, { recursive: true, force: true });
	mkdirSync(outDir, { recursive: true });
	cpSync(join(docsDir, "assets"), outDir, { recursive: true });
	for (const page of pages) {
		writeFileSync(join(outDir, page.file), layout(page, pages, fw.version));
	}
	writeFileSync(join(outDir, ".nojekyll"), "");
	return pages.length;
}

function buildAndReport() {
	try {
		const count = build();
		console.log(`docs: ${count} pages -> ${outDir}`);
		return true;
	} catch (error) {
		console.error(error.message);
		return false;
	}
}

if (!buildAndReport() && !process.argv.includes("--serve")) {
	process.exit(1);
}

if (process.argv.includes("--serve")) {
	const types = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml" };
	const port = Number(process.env.DOCS_PORT ?? 4173);
	createServer((request, response) => {
		let name = normalize(decodeURIComponent((request.url ?? "/").split(/[?#]/)[0])).replace(/^[\\/]+/, "");
		if (name === "" || name.endsWith("/") || name.endsWith("\\")) name += "index.html";
		const path = join(outDir, name);
		if (!path.startsWith(outDir) || !existsSync(path) || !statSync(path).isFile()) {
			response.writeHead(404, { "content-type": "text/plain" }).end("not found");
			return;
		}
		response.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream", "cache-control": "no-store" });
		response.end(readFileSync(path));
	}).listen(port, "127.0.0.1", () => console.log(`docs: http://127.0.0.1:${port}/`));

	let timer;
	for (const dir of [docsDir, join(root, "src")]) {
		watch(dir, { recursive: true }, () => {
			clearTimeout(timer);
			timer = setTimeout(buildAndReport, 120);
		});
	}
}
