#!/usr/bin/env node
/*
	Builds build/ordnance.bundle.json: the whole framework as one JSON tree.

	Studio plugins can make HTTP requests but cannot load binary model files
	from them, so the updater ships the framework as text instead. The plugin
	downloads this file and rebuilds the instance tree with Instance.new.

	The walker follows the same file conventions as Rojo, for the subset the
	repo uses:
		dir/init.luau            -> ModuleScript named after the directory
		dir/ (no init)           -> Folder
		Name.luau                -> ModuleScript
		Name.server.luau         -> Script, RunContext = Server
		Name.client.luau         -> Script, RunContext = Client
		Name.model.json          -> instance tree in Rojo's JSON model format

	Node format: { n: name, c: className, s?: source, p?: properties, k?: children }

	Also writes, next to the bundle:
		latest.json            the version, for the updater to check cheaply
		catalogue.json         an index of every weapon and preset in src
		catalogue/<kind>/<name>.json   each one as an instance tree, for the
		                       plugin's Catalogue tab to insert

	With --embed the bundle is also written to plugin/src/Embedded.json, so the
	plugin can install without a connection. That file is generated and ignored
	by git.

	Usage: node tools/bundle.mjs [--out build] [--embed]
*/

import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const outFlag = args.indexOf("--out");
const outDir = resolve(root, outFlag >= 0 ? args[outFlag + 1] : "build");

const read = (path) => readFileSync(path, "utf8").replace(/\r\n/g, "\n");

function scriptNode(name, suffix, source) {
	if (suffix === ".server") {
		return { n: name, c: "Script", p: { RunContext: "Server" }, s: source };
	}
	if (suffix === ".client") {
		return { n: name, c: "Script", p: { RunContext: "Client" }, s: source };
	}
	return { n: name, c: "ModuleScript", s: source };
}

function modelNode(json, fallbackName) {
	const node = { n: json.Name ?? json.name ?? fallbackName, c: json.ClassName ?? json.className };
	const properties = json.Properties ?? json.properties;
	if (properties && Object.keys(properties).length > 0) {
		node.p = properties;
	}
	const attributes = json.Attributes ?? json.attributes;
	if (attributes && Object.keys(attributes).length > 0) {
		node.a = attributes;
	}
	const children = json.Children ?? json.children;
	if (children && children.length > 0) {
		node.k = children.map((child) => modelNode(child, child.ClassName ?? child.className));
	}
	return node;
}

function walkFile(path, file) {
	let match = file.match(/^(.+?)(\.server|\.client)?\.luau?$/);
	if (match) {
		return scriptNode(match[1], match[2] ?? "", read(path));
	}
	match = file.match(/^(.+)\.model\.json$/);
	if (match) {
		return modelNode(JSON.parse(read(path)), match[1]);
	}
	return null;
}

function walkDir(dir, name) {
	const entries = readdirSync(dir).sort((a, b) => a.localeCompare(b, "en"));
	let node = { n: name, c: "Folder" };

	const init = entries.find((entry) => /^init(\.server|\.client)?\.luau?$/.test(entry));
	if (init) {
		const suffix = init.match(/^init(\.server|\.client)?\./)[1] ?? "";
		node = scriptNode(name, suffix, read(join(dir, init)));
	}

	const children = [];
	for (const entry of entries) {
		if (entry === init || entry.startsWith(".") || entry.endsWith(".meta.json")) {
			continue;
		}
		const path = join(dir, entry);
		const child = statSync(path).isDirectory() ? walkDir(path, entry) : walkFile(path, entry);
		if (child) {
			children.push(child);
		}
	}
	if (children.length > 0) {
		node.k = children;
	}
	return node;
}

function count(node) {
	return 1 + (node.k ?? []).reduce((total, child) => total + count(child), 0);
}

const versionSource = read(join(root, "src", "Framework", "Version.luau"));
const version = versionSource.match(/return\s+"([^"]+)"/)?.[1];
if (!version) {
	console.error("bundle: could not read the version from src/Framework/Version.luau");
	process.exit(1);
}

const tree = walkDir(join(root, "src"), "Ordnance");
const bundle = { format: 1, name: "Ordnance", version, root: tree };

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "ordnance.bundle.json"), JSON.stringify(bundle));
if (args.includes("--embed")) {
	writeFileSync(join(root, "plugin", "src", "Embedded.json"), JSON.stringify(bundle));
}

// Catalogue: one file per weapon and per preset, plus an index.
function describe(node) {
	const block = (node.s ?? "").match(/^--\[\[([\s\S]*?)\]\]/)?.[1];
	if (!block) return undefined;
	const lines = block.split("\n").map((line) => line.trim());
	const text = [];
	for (const line of lines.slice(2)) {
		if (line === "") break;
		text.push(line);
	}
	return text.join(" ") || undefined;
}
const entries = [];
for (const [folder, kind] of [["Weapons", "weapon"], ["Presets", "preset"]]) {
	const container = (tree.k ?? []).find((node) => node.n === folder);
	for (const node of container?.k ?? []) {
		if (node.c !== "ModuleScript") continue;
		const path = `catalogue/${kind}s/${node.n}.json`;
		mkdirSync(join(outDir, "catalogue", `${kind}s`), { recursive: true });
		writeFileSync(join(outDir, path), JSON.stringify(node));
		entries.push({ id: node.n, kind, name: node.n, description: describe(node), author: "xerseer", version, path });
	}
}
writeFileSync(join(outDir, "catalogue.json"), JSON.stringify({ format: 1, version, entries }, null, "\t") + "\n");
writeFileSync(
	join(outDir, "latest.json"),
	JSON.stringify({ format: 1, version, tag: `v${version}`, bundle: "ordnance.bundle.json" }, null, "\t") + "\n",
);

const bytes = statSync(join(outDir, "ordnance.bundle.json")).size;
console.log(`bundle: Ordnance v${version}, ${count(tree)} instances, ${(bytes / 1024).toFixed(1)} KiB, ${entries.length} catalogue entries -> ${outDir}`);
