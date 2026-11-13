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

	Usage: node tools/bundle.mjs [--out build]
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
writeFileSync(
	join(outDir, "latest.json"),
	JSON.stringify({ format: 1, version, tag: `v${version}`, bundle: "ordnance.bundle.json" }, null, "\t") + "\n",
);

const bytes = statSync(join(outDir, "ordnance.bundle.json")).size;
console.log(`bundle: Ordnance v${version}, ${count(tree)} instances, ${(bytes / 1024).toFixed(1)} KiB -> ${outDir}`);
