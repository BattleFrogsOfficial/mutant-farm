// HUD layout checks (scenes from ui-export's built-ins and tools/preview/scenes/hud.luau), on every
// "hud..." scene at its size. Design px = on-screen px / the HUD scale. See Config/Hud.lua.
//   top-right tiles exactly 8 px apart, red dots inside their tiles
//   right column rows in order weather, Instant Weather, bundle, bag, 8 px apart (and 8 px under
//   the tiles); Instant Weather as wide as the bundle ribbon
//   plot: SHOP the same size as WATER and right beside it; WATER reads "WATER · 2x 30s", dimmed
//   (never pink) with its drain ring while watered
//   hub: SHOP is the biggest button on screen
//   no ImageLabel/ImageButton in the HUD; the tile/Cash/Gems/HATCH/bag/WATER icons are vector glyphs
//   egg tray: owned eggs + at most one "next egg" tile (price + "at the Egg Shop"); gated tiers never
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

    // Tiles: Upgrades | Daily | Almanac, 8 design px apart, red dots inside.
    const tiles = ["Upgrades", "Daily", "Almanac"].map((n) => [n, el(n)]);
    if (tiles.some(([, e]) => !vis(e))) problems.push("a top-right tile is missing");
    else {
      const s = scaleOf(tiles[0][1]);
      for (let i = 0; i + 1 < tiles.length; i++) {
        const gap = (rect(tiles[i + 1][1]).left - rect(tiles[i][1]).right) / s;
        if (!near(gap, 8)) problems.push(`${tiles[i][0]} -> ${tiles[i + 1][0]} gap ${gap.toFixed(1)} px (want 8)`);
      }
      for (const [n, t] of tiles) {
        const dot = [...t.querySelectorAll('[title="Dot"]')].find(vis);
        if (!dot) continue;
        const tr = rect(t), dr = rect(dot);
        // The dot's ink outline (UIStroke, box-shadow) is drawn outside its box.
        const stroke = (parseFloat((getComputedStyle(dot).boxShadow.match(/0px 0px 0px ([\d.]+)px/) || [])[1]) || 0) * s * Math.SQRT2;
        if (dr.left - stroke < tr.left - 0.5 || dr.right + stroke > tr.right + 0.5 || dr.top - stroke < tr.top - 0.5 || dr.bottom + stroke > tr.bottom + 0.5)
          problems.push(`${n}'s red dot pokes out of the tile`);
      }
    }

    // Right column: visible rows in order, 8 px apart, the first 8 px under the tiles.
    const order = ["Weather", "InstantWeather", "Bundle", "BagChip"];
    const rows = order.map((n) => [n, el(n)]).filter(([, e]) => vis(e));
    if (rows.length && vis(tiles[0][1])) {
      const s = scaleOf(rows[0][1]);
      const first = (rect(rows[0][1]).top - rect(tiles[2][1]).bottom) / s;
      if (!near(first, 8)) problems.push(`${rows[0][0]} is ${first.toFixed(1)} px under the tiles (want 8)`);
      for (let i = 0; i + 1 < rows.length; i++) {
        const gap = (rect(rows[i + 1][1]).top - rect(rows[i][1]).bottom) / s;
        if (!near(gap, 8)) problems.push(`${rows[i][0]} -> ${rows[i + 1][0]} gap ${gap.toFixed(1)} px (want 8)`);
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
        const sideBySide = near(a.top, b.top) && gx >= 0 && gx / s <= 16;
        const stacked = near(a.left, b.left) && gy >= 0 && gy / s <= 16;
        if (!sideBySide && !stacked) problems.push("Shop isn't right beside Water");
      }
    } else if (vis(shop)) {
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
      const label = (water.querySelector('[title="Label"] span') || {}).textContent || "";
      if (ring) {
        if (!look.includes("85, 91, 112")) problems.push("Water isn't dimmed while the ring runs");
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
    if (!plot) {
      // Tiles also have to be glyph-only (checked above); nothing more for the hub.
    }

    // Egg tray: owned eggs + one next tile; gated tiers never; expected per scene.
    if (plot) {
      const cards = el("Cards");
      const inner = cards && [...cards.children].find((c) => c.classList.contains("inner"));
      const tiles = inner ? [...inner.children].filter((c) => c.classList.contains("g")).map((c) => c.title) : [];
      if (tiles.includes("Locked")) problems.push("the old padlock card is in the tray");
      const next = el("NextEgg");
      const nextText = next ? [...next.querySelectorAll("span")].map((s) => s.textContent).join(" | ") : "";
      const EXPECT = {
        "hud-plot": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-touch": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-instant-weather": { owned: ["Starter", "Swamp", "Pumpkin"], next: null },
        "hud-plot-eggs0": { owned: [], next: "$50" },
        "hud-plot-eggs1-new": { owned: ["Starter"], next: "$500" },
        "hud-plot-eggs2": { owned: ["Starter", "Swamp"], next: "$5K" },
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
            if (price !== want.next) problems.push(`next egg priced "${price}" (want ${want.next})`);
            if (!/at the egg shop/i.test(nextText)) problems.push(`next egg tile says "${nextText}"`);
          }
        }
      }
      if (tiles.filter((t) => t === "NextEgg").length > 1) problems.push("more than one next-egg tile");
    }
    return problems;
  },
});
