// Copy buttons, the rail's current-section marker, and the settings filter.
(function () {
	document.querySelectorAll(".code").forEach((block) => {
		const code = block.querySelector("code");
		const button = document.createElement("button");
		button.className = "copy";
		button.type = "button";
		button.textContent = "Copy";
		button.addEventListener("click", () => {
			const done = () => {
				button.textContent = "Copied";
				setTimeout(() => (button.textContent = "Copy"), 1400);
			};
			const select = () => {
				const range = document.createRange();
				range.selectNodeContents(code);
				const selection = getSelection();
				selection.removeAllRanges();
				selection.addRange(range);
				button.textContent = "Press Ctrl+C";
			};
			try {
				navigator.clipboard.writeText(code.textContent).then(done, select);
			} catch (error) {
				select();
			}
		});
		block.append(button);
	});

	const links = [...document.querySelectorAll("nav.rail a.sub")];
	const byId = new Map(links.map((a) => [a.getAttribute("href").slice(1), a]));
	if ("IntersectionObserver" in window && links.length > 0) {
		const observer = new IntersectionObserver(
			(entries) => {
				entries.forEach((entry) => {
					if (!entry.isIntersecting) return;
					const link = byId.get(entry.target.id);
					if (!link) return;
					links.forEach((a) => a.classList.remove("on"));
					link.classList.add("on");
				});
			},
			{ rootMargin: "-15% 0px -75% 0px" },
		);
		document.querySelectorAll("main section[id]").forEach((section) => observer.observe(section));
	}

	// Config page: filter every reference row by name or description.
	const input = document.querySelector(".filter input");
	if (input) {
		const rows = [...document.querySelectorAll("table.ref tbody tr")];
		const count = document.querySelector(".filter .count");
		const total = rows.length;
		const sections = [...document.querySelectorAll("main section[id]")].filter((s) => s.querySelector("table.ref"));
		const apply = () => {
			const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
			let shown = 0;
			rows.forEach((row) => {
				const hit = words.every((word) => row.dataset.search.includes(word));
				row.hidden = !hit;
				if (hit) shown++;
			});
			sections.forEach((section) => {
				section.hidden = words.length > 0 && !section.querySelector("table.ref tbody tr:not([hidden])");
			});
			count.textContent = words.length > 0 ? `${shown} of ${total}` : `${total} settings`;
		};
		input.addEventListener("input", apply);
		document.addEventListener("keydown", (event) => {
			if (event.key === "/" && document.activeElement !== input) {
				event.preventDefault();
				input.focus();
			}
		});
		apply();
	}

	// A link to one setting highlights its row.
	const mark = () => {
		document.querySelectorAll("tr.hit").forEach((row) => row.classList.remove("hit"));
		const id = decodeURIComponent(location.hash.slice(1));
		const target = id && document.getElementById(id);
		const row = target && target.closest("tr");
		if (row) row.classList.add("hit");
	};
	addEventListener("hashchange", mark);
	mark();
})();
