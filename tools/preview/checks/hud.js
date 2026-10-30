// HUD layout checks (scenes from ui-export's built-ins and tools/preview/scenes/hud.luau), on every
// "hud..." scene at its size. Design px = on-screen px / the HUD scale. See Config/Hud.lua.
//   top-right tiles 8 px apart AS DRAWN (one tile's shadow to the next one's ink outline), red dots
//   inside their tiles and clear of the glyph (its outline and shadow); in hud-dots all three dots
//   are lit
//   right column rows in order weather, Instant Weather, bundle, bag, 8 px apart as drawn (and 8 px
//   under the tiles' shadows); Instant Weather as wide as the bundle ribbon
//   plot: SHOP the same size as WATER and right beside it (same row, WATER on the left; never
//   stacked); WATER reads "WATER · 2x 30s" (two lines, "WATER" / "· 2x 30s"), dimmed
//   (never pink) with its drain ring while watered
//   hub: SHOP is the biggest button on screen
//   no ImageLabel/ImageButton in the HUD; the tile/Cash/Gems/HATCH/bag/WATER icons are vector glyphs
//   egg tray: owned eggs + at most one "next egg" tile (name, price, "AT THE" / "EGG SHOP"); in
//   EVERY tray tile each text is at its full size (its MaxTextSize, i.e. not squeezed by
//   TextScaled because the tile is too narrow), at least MIN_FONT px on screen, and only breaks
//   between words (every word fits the label's width); rebirth-gated tiers never appear as the
//   next egg; the egg art is Config/Hud tray.art (64) px; up to two owned eggs + the next egg
//   fit in the tray without scrolling
const FULL_SIZE = 0.98;
const MIN_FONT = 7;
const TRAY_ART = 64;
registerCheck({
  name: "hud",
  match: (n) => n.startsWith("hud"),
  run: (W, H, sceneName) => {
    const problems = [];
    const kind = sceneName.split("@")[0];
    const plot = kind.includes("plot");
    const q = (sel, root = document) => root.querySelector(`.gui ${sel}`) || root.querySelector(sel);
    const el = (name) => document.querySelector(`.gui [title="${name}"]`);
    const vis = (e) => !!e && e.offsetParent !== null && getComputedStyle(e).display !== "none";
    const scaleOf = (e) => e.getBoundingClientRect().width / (e.offsetWidth || 1);
    const rect = (e) => e.getBoundingClientRect();
    const near = (a, b, tol = 1) => Math.abs(a - b) <= tol;
    // What an element draws on screen: its filled boxes, grown by their ink outline (a UIStroke is
    // a box-shadow spread in the render), plus its hard shadow frame. Plain text rows (no fill, no
    // outline) count by their frame.
    const drawn = (e) => {
      let r = null;
      for (const d of [e, ...e.querySelectorAll("*")]) {
        if (d !== e && d.offsetParent === null) continue;
        if (d.tagName === "SPAN") continue;
        const cs = getComputedStyle(d);
        if (cs.visibility === "hidden" || cs.display === "none") continue;
        const alpha = /rgba\([^)]*,\s*([\d.]+)\)$/.exec(cs.backgroundColor);
        const fill = cs.backgroundColor !== "transparent" && !(alpha && +alpha[1] === 0);
        const m = /0px 0px 0px ([\d.]+)px/.exec(cs.boxShadow);
        if (!fill && !m) continue;
        const b = d.getBoundingClientRect();
        if (b.width < 1 || b.height < 1) continue;
        const grow = m ? parseFloat(m[1]) * scaleOf(d) : 0;
        const g = { left: b.left - grow, top: b.top - grow, right: b.right + grow, bottom: b.bottom + grow };
        r = r ? { left: Math.min(r.left, g.left), top: Math.min(r.top, g.top), right: Math.max(r.right, g.right), bottom: Math.max(r.bottom, g.bottom) } : g;
      }
      return r || rect(e);
    };

    // Tiles: Upgrades | Daily | Almanac, 8 design px apart as drawn, red dots inside.
    const tiles = ["Upgrades", "Daily", "Almanac"].map((n) => [n, el(n)]);
    if (tiles.some(([, e]) => !vis(e))) problems.push("a top-right tile is missing");
    else {
      const s = scaleOf(tiles[0][1]);
      for (let i = 0; i + 1 < tiles.length; i++) {
        const gap = (drawn(tiles[i + 1][1]).left - drawn(tiles[i][1]).right) / s;
        if (!near(gap, 8, 1.5)) problems.push(`${tiles[i][0]} -> ${tiles[i + 1][0]} drawn gap ${gap.toFixed(1)} px (want 8)`);
      }
      for (const [n, t] of tiles) {
        const dot = [...t.querySelectorAll('[title="Dot"]')].find(vis);
        if (!dot) {
          if (kind.endsWith("-dots")) problems.push(`${n}'s red dot isn't lit in ${kind}`);
          continue;
        }
        const tr = rect(t), dr = rect(dot);
        // The dot's ink outline (UIStroke, box-shadow) is drawn outside its box.
        const stroke = (parseFloat((getComputedStyle(dot).boxShadow.match(/0px 0px 0px ([\d.]+)px/) || [])[1]) || 0) * s * Math.SQRT2;
        if (dr.left - stroke < tr.left - 0.5 || dr.right + stroke > tr.right + 0.5 || dr.top - stroke < tr.top - 0.5 || dr.bottom + stroke > tr.bottom + 0.5)
          problems.push(`${n}'s red dot pokes out of the tile`);
        // The dot is a diamond: its outline reaches L1 radius (bbox half-width + stroke) from its
        // center. No part of the glyph (fill, outline or shadow; rotated parts by their bounding
        // box) may come within it.
        const cx = (dr.left + dr.right) / 2, cy = (dr.top + dr.bottom) / 2;
        const radius = (dr.right - dr.left) / 2 + stroke;
        for (const part of t.querySelectorAll('[title="Glyph"] [title="Part"]')) {
          if (!vis(part)) continue;
          const pr = rect(part);
          const px = Math.min(Math.max(cx, pr.left), pr.right), py = Math.min(Math.max(cy, pr.top), pr.bottom);
          if (Math.abs(px - cx) + Math.abs(py - cy) < radius - 0.5) { problems.push(`${n}'s glyph runs into its red dot`); break; }
        }
      }
    }

    // Right column: visible rows in order, 8 px apart as drawn, the first 8 px under the tiles.
    const order = ["Weather", "InstantWeather", "Bundle", "BagChip"];
    const rows = order.map((n) => [n, el(n)]).filter(([, e]) => vis(e));
    // In screen order too (a reordered layout would still pass the gap checks).
    for (let i = 0; i + 1 < rows.length; i++)
      if (rect(rows[i + 1][1]).top < rect(rows[i][1]).top) problems.push(`${rows[i + 1][0]} sits above ${rows[i][0]}`);
    if (rows.length && vis(tiles[0][1])) {
      const s = scaleOf(rows[0][1]);
      const first = (drawn(rows[0][1]).top - drawn(tiles[2][1]).bottom) / s;
      if (!near(first, 8, 1.5)) problems.push(`${rows[0][0]} is ${first.toFixed(1)} px under the tiles as drawn (want 8)`);
      for (let i = 0; i + 1 < rows.length; i++) {
        const gap = (drawn(rows[i + 1][1]).top - drawn(rows[i][1]).bottom) / s;
        if (!near(gap, 8, 1.5)) problems.push(`${rows[i][0]} -> ${rows[i + 1][0]} drawn gap ${gap.toFixed(1)} px (want 8)`);
      }
    }
    const iw = el("InstantWeather"), bundle = el("Bundle");
    if (vis(iw) && vis(bundle) && !near(rect(iw).width, rect(bundle).width, 0.5))
      problems.push(`Instant Weather ${rect(iw).width.toFixed(0)} px wide, bundle ${rect(bundle).width.toFixed(0)} px`);

    // SHOP vs WATER at the plot; SHOP the biggest button in the hub.
    const shop = el("Shop"), water = el("Water");
    if (plot) {
      if (!vis(shop) || !vis(water)) problems.push("Shop or Water missing at the plot");
      else {
        const a = rect(shop), b = rect(water), s = scaleOf(shop);
        if (!near(a.width, b.width) || !near(a.height, b.height))
          problems.push(`Shop ${a.width.toFixed(0)}x${a.height.toFixed(0)} != Water ${b.width.toFixed(0)}x${b.height.toFixed(0)}`);
        const gx = Math.max(a.left, b.left) - Math.min(a.right, b.right);
        const gy = Math.max(a.top, b.top) - Math.min(a.bottom, b.bottom);
        const sideBySide = near(a.top, b.top) && b.right <= a.left + 0.5 && gx >= 0 && gx / s <= 16;
        if (!sideBySide) problems.push(`Shop isn't right beside Water (Water ${b.left.toFixed(0)},${b.top.toFixed(0)} Shop ${a.left.toFixed(0)},${a.top.toFixed(0)}${gy >= 0 ? ", stacked" : ""})`);
      }
    } else if (!vis(shop)) problems.push("Shop missing in the hub");
    else {
      const shopArea = rect(shop).width * rect(shop).height;
      for (const face of document.querySelectorAll('.gui [title="Face"]')) {
        if (!vis(face) || shop.contains(face) || face.tagName !== "DIV") continue;
        const btn = face.parentElement && face.parentElement.closest(".g");
        const r = rect(btn || face);
        if (r.width * r.height > shopArea + 1) problems.push(`${(btn || face).title} is bigger than Shop`);
      }
    }

    // Water: label from config; while watered, dimmed (locked grey, never pink) and the ring runs.
    if (plot && vis(water)) {
      const face = water.querySelector('[title="Face"]');
      const look = face ? getComputedStyle(face).backgroundImage : "";
      if (look.includes("255, 79, 163")) problems.push("Water is pink");
      const ring = vis(water.querySelector('[title="Ring1"]'));
      const line1 = (water.querySelector('[title="Label"] span') || {}).textContent || "";
      const line2 = (water.querySelector('[title="Sub"] span') || {}).textContent || "";
      // The two lines as rendered, read top to bottom (a line break reads as a space).
      const label = `${line1} ${line2}`;
      if (ring) {
        if (!look.includes("85, 91, 112")) problems.push("Water isn't dimmed while the ring runs");
        if (!/^WATER · 2x \d+:\d\d$/.test(label)) problems.push(`watered Water label "${label}"`);
      } else if (label !== "WATER · 2x 30s") problems.push(`Water label "${label}"`);
      if (kind.startsWith("hud-plot-watered") && !ring) problems.push("drain ring not running in the watered scene");
    }

    // No images for icons anywhere in the HUD (scene JSON: the Hud frame's subtree).
    const scene = data.scenes.find((s) => s.name === sceneName);
    const walk = (n, f) => { f(n); for (const c of (Array.isArray(n.children) ? n.children : Object.values(n.children || {}))) walk(c, f); };
    let hudNode = null;
    walk(scene.root, (n) => { if (!hudNode && n.name === "Hud" && n.class === "Frame") hudNode = n; });
    if (hudNode) walk(hudNode, (n) => { if (n.class === "ImageLabel" || n.class === "ImageButton") problems.push(`${n.class} "${n.name}" in the HUD`); });

    // Icons are vector glyphs, not emoji text.
    const OLD = /💰|💎|🥚|🎒|💧|⬆|📖/;
    const iconHosts = ["Upgrades", "Daily", "Almanac", "Cash", "Gems"].concat(plot ? ["Hatch", "BagChip", "Water"] : []);
    for (const n of iconHosts) {
      const host = el(n);
      if (!vis(host)) continue;
      if (![...host.querySelectorAll('[title="Glyph"]')].some(vis)) problems.push(`${n} has no vector glyph`);
      const emoji = [...host.querySelectorAll("span")].find((sp) => vis(sp.parentElement) && OLD.test(sp.textContent));
      if (emoji) problems.push(`${n} still shows "${emoji.textContent}"`);
    }

    // Egg tray: owned eggs + one next tile; gated tiers never; expected per scene.
    if (plot) {
      const cards = el("Cards");
      const inner = cards && [...cards.children].find((c) => c.classList.contains("inner"));
      const tiles = inner ? [...inner.children].filter((c) => c.classList.contains("g")).map((c) => c.title) : [];
      if (tiles.includes("Locked")) problems.push("the old padlock card is in the tray");
      const next = el("NextEgg");
      const nextText = next ? [...next.querySelectorAll("span")].map((s) => s.textContent).join(" | ") : "";
      // next: [price, name line]
      const EXPECT = {
        "hud-plot": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-touch": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-instant-weather": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-eggs0": { owned: [], next: ["$50", "STARTER"] },
        "hud-plot-eggs1-new": { owned: ["Starter"], next: ["$500", "SWAMP"] },
        "hud-plot-eggs2": { owned: ["Starter", "Swamp"], next: ["$5K", "LAB"] },
        "hud-plot-eggs2-gem": { owned: ["Starter", "StarterGem"], next: ["$500", "SWAMP"] },
        "hud-plot-eggs2-pumpkin": { owned: ["Starter", "Pumpkin"], next: ["$500", "SWAMP"] },
        "hud-plot-eggs2-gemsonly": { owned: ["StarterGem", "SwampGem"], next: ["$50", "STARTER"] },
        "hud-plot-eggs6": { owned: ["Starter", "Swamp", "Lab", "StarterGem", "SwampGem", "Pumpkin"], next: null },
        "hud-plot-eggs6-touch": { owned: ["Starter", "Swamp", "Lab", "StarterGem", "SwampGem", "Pumpkin"], next: null },
        "hud-plot-watered": { owned: ["Starter", "Swamp"], next: null },
        "hud-plot-watered-touch": { owned: ["Starter", "Swamp"], next: null },
      };
      const want = EXPECT[kind];
      const owned = tiles.filter((t) => t !== "NextEgg");
      for (const gated of ["Toxic", "Void", "Cosmic"]) if (owned.includes(gated) && !(want && want.owned.includes(gated))) problems.push(`gated tier ${gated} in the tray`);
      if (want) {
        if ([...owned].sort().join(",") !== [...want.owned].sort().join(",")) problems.push(`tray shows ${owned.join("+") || "nothing"} (want ${want.owned.join("+") || "nothing"})`);
        if (want.next === null && tiles.includes("NextEgg")) problems.push(`unexpected next-egg tile "${nextText}"`);
        if (want.next !== null) {
          if (!tiles.includes("NextEgg")) problems.push(`no next-egg tile (want ${want.next})`);
          else {
            const price = (next.querySelector('[title="Count"] span') || {}).textContent;
            const name = (next.querySelector('[title="Label"] span') || {}).textContent;
            const sub = (next.querySelector('[title="Sub"] span') || {}).textContent || "";
            if (price !== want.next[0]) problems.push(`next egg priced "${price}" (want ${want.next[0]})`);
            if (name !== want.next[1]) problems.push(`next egg named "${name}" (want ${want.next[1]})`);
            if (!/^at the\s+egg shop$/i.test(sub)) problems.push(`next egg tile says "${nextText}"`);
          }
        }
      }
      if (tiles.filter((t) => t === "NextEgg").length > 1) problems.push("more than one next-egg tile");
      // The early trays (up to 2 owned eggs + the next egg) fit without scrolling: every tile, as
      // drawn (outline and shadow), lies across inside the Cards viewport, which ends before HATCH.
      if (/^hud-plot-(eggs[012]|watered)/.test(kind) && cards && inner) {
        const box = rect(cards);
        const hatch = el("Hatch");
        if (hatch && vis(hatch) && drawn(hatch).left < box.right - 0.5) problems.push("the egg cards run under HATCH");
        for (const tile of [...inner.children].filter((c) => c.classList.contains("g"))) {
          const d = drawn(tile);
          if (d.left < box.left - 0.5 || d.right > box.right + 0.5) {
            problems.push(`${tile.title} tile is cut off by the tray (${d.left.toFixed(0)}..${d.right.toFixed(0)} in ${box.left.toFixed(0)}..${box.right.toFixed(0)})`);
          }
        }
      }
      // Every scene: the next egg is never a rebirth-gated tier (all mocks are at Rebirth 0).
      const nextName = next ? ((next.querySelector('[title="Label"] span') || {}).textContent || "") : "";
      if (/TOXIC|VOID|COSMIC/.test(nextName)) problems.push(`gated tier "${nextName}" as the next egg`);
      // Every tray tile: 64 px art, and each text line at nearly full size on one line.
      for (const tileName of tiles) {
        const tile = inner && [...inner.children].find((c) => c.title === tileName);
        if (!tile) continue;
        const art = tile.querySelector('[title="Viewport"]');
        if (art && vis(art) && !near(art.offsetWidth, TRAY_ART, 0.5)) problems.push(`${tileName}'s egg art is ${art.offsetWidth} px (want ${TRAY_ART})`);
        for (const sp of tile.querySelectorAll("span")) {
          const host = sp.parentElement;
          if (!vis(host) || !sp.textContent.trim()) continue;
          const cs = getComputedStyle(host);
          const design = parseFloat(cs.fontSize), px = design * scaleOf(host), max = +host.dataset.max || design;
          if (design < max * FULL_SIZE) problems.push(`${tileName} "${sp.textContent}" squeezed to ${design.toFixed(1)} design px (full size ${max})`);
          if (px < MIN_FONT) problems.push(`${tileName} "${sp.textContent}" at ${px.toFixed(1)} px on screen (min ${MIN_FONT})`);
          // Line breaks only between words: every word fits the label's width on its own.
          const ctx = (window.__measure ||= document.createElement("canvas").getContext("2d"));
          ctx.font = `${cs.fontWeight} ${design}px ${cs.fontFamily}`;
          for (const word of sp.textContent.split(/\s+/).filter(Boolean)) {
            const w = ctx.measureText(word).width;
            if (w > host.clientWidth + 0.5) problems.push(`${tileName}: "${word}" is wider than its label (${w.toFixed(1)} > ${host.clientWidth} design px)`);
          }
        }
      }
    }
    return problems;
  },
});
