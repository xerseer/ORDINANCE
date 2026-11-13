#!/usr/bin/env node
/*
	Serves build/ on localhost so Studio can pull a fresh bundle during
	development without Rojo's plugin:

		node tools/bundle.mjs && node tools/serve.mjs

	Then, in Studio, the plugin's "Install from local build" (or the snippet in
	tools/sync.luau pasted into the command bar) rebuilds ReplicatedStorage.Ordnance.

	Local only: binds to 127.0.0.1 and serves files from build/ and nothing else.
*/

import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "build");
const port = Number(process.env.ORDNANCE_PORT ?? 34873);

createServer((request, response) => {
	const name = normalize(decodeURIComponent((request.url ?? "/").split("?")[0])).replace(/^[\\/]+/, "");
	const path = join(root, name);
	if (!path.startsWith(root) || !existsSync(path) || !statSync(path).isFile()) {
		response.writeHead(404).end("not found");
		return;
	}
	response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
	createReadStream(path).pipe(response);
}).listen(port, "127.0.0.1", () => {
	console.log(`serve: http://127.0.0.1:${port}/ordnance.bundle.json`);
});
