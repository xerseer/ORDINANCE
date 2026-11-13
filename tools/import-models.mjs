#!/usr/bin/env node
/*
	Imports weapon models that were serialized inside Studio.

	Studio cannot write files, so the rigging script prints each model as JSON
	in numbered chunks:

		@@ORD|<Weapon>|<n>|<json chunk>
		@@ORDEND|<Weapon>|<chunk count>|<total bytes>

	This tool reads the newest Studio log, reassembles the last complete copy
	of each model, checks its length and writes it to
	src/Weapons/<Weapon>/Model.model.json, which Rojo turns back into a Model.

	Usage: node tools/import-models.mjs [path-to-log]
*/

import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function newestLog() {
	const directory = join(process.env.LOCALAPPDATA ?? "", "Roblox", "logs");
	if (!existsSync(directory)) {
		return null;
	}
	const logs = readdirSync(directory)
		.filter((name) => name.includes("Studio") && name.endsWith(".log"))
		.map((name) => ({ path: join(directory, name), time: statSync(join(directory, name)).mtimeMs }))
		.sort((a, b) => b.time - a.time);
	return logs.find((log) => readFileSync(log.path, "utf8").includes("@@ORDEND|"))?.path ?? null;
}

const logPath = process.argv[2] ?? newestLog();
if (!logPath) {
	console.error("import-models: no Studio log with serialized models was found");
	process.exit(1);
}

const chunks = new Map(); // weapon -> Map(index -> text)
const finished = new Map(); // weapon -> json

for (const line of readFileSync(logPath, "utf8").split(/\r?\n/)) {
	const chunk = line.match(/@@ORD\|([^|]+)\|(\d+)\|(.*)$/);
	if (chunk) {
		const [, weapon, index, text] = chunk;
		if (index === "1") {
			chunks.set(weapon, new Map());
		}
		chunks.get(weapon)?.set(Number(index), text);
		continue;
	}
	const end = line.match(/@@ORDEND\|([^|]+)\|(\d+)\|(\d+)/);
	if (end) {
		const [, weapon, count, bytes] = end;
		const parts = chunks.get(weapon);
		if (!parts || parts.size !== Number(count)) {
			console.error(`import-models: ${weapon} is missing chunks; skipped`);
			continue;
		}
		const json = Array.from({ length: parts.size }, (_, i) => parts.get(i + 1)).join("");
		if (json.length !== Number(bytes)) {
			console.error(`import-models: ${weapon} is ${json.length} bytes, expected ${bytes}; skipped`);
			continue;
		}
		finished.set(weapon, json);
	}
}

// Rojo reads an implicit CFrame as twelve numbers: position, then the rotation
// matrix row by row.
function flattenFrame(value) {
	if (value && !Array.isArray(value) && value.position && value.orientation) {
		return [...value.position, ...value.orientation.flat()];
	}
	return value;
}

// Key order follows the Explorer: name, class, properties, children.
function ordered(node) {
	const result = {};
	if (node.Name !== undefined) result.Name = node.Name;
	result.ClassName = node.ClassName;
	if (node.Properties) {
		const entries = Object.entries(node.Properties).sort(([a], [b]) => a.localeCompare(b));
		result.Properties = Object.fromEntries(entries.map(([key, value]) => [key, key === "CFrame" ? flattenFrame(value) : value]));
	}
	if (node.Children) result.Children = node.Children.map(ordered);
	return result;
}

// One part per line: compact, and a moved part is a one-line diff.
function format(model) {
	const lines = model.Children.map((child) => "\t\t" + JSON.stringify(child));
	return ['{', '\t"ClassName": "Model",', '\t"Children": [', lines.join(",\n"), "\t]", "}"].join("\n");
}

for (const [weapon, json] of finished) {
	const directory = join(root, "src", "Weapons", weapon);
	mkdirSync(directory, { recursive: true });
	const model = ordered(JSON.parse(json));
	writeFileSync(join(directory, "Model.model.json"), format(model) + "\n");
	console.log(`import-models: ${weapon} -> src/Weapons/${weapon}/Model.model.json (${model.Children.length} children)`);
}

if (finished.size === 0) {
	console.error("import-models: no complete models in the log");
	process.exit(1);
}
