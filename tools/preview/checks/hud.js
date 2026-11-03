// HUD layout checks (scenes from ui-export's built-ins and tools/preview/scenes/hud.luau), on every
// "hud..." scene at its size. Design px = on-screen px / the HUD scale. See Config/Hud.lua.
//   Cash -> Gems and the top-right tiles 8 px apart AS DRAWN (shadow to the next ink outline), red dots
//   inside their tiles and clear of the glyph (its outline and shadow); in hud-dots all three dots
//   are lit
//   right column rows in order Instant Weather, bundle, bag, 8 px apart as drawn (and 8 px under
//   the tiles' shadows); Instant Weather as wide as the bundle ribbon
//   weather line centered under the Cash / Gems row in every zone: plain text far from an event, a
//   chip in the event's color from 5 min before it (hud-weather-idle, hud-weather-soon, hud-plot-weather-active)
//   plot: SHOP at Config/Hud plotButtons size, no WATER button; the growth circle reads "CLICK" /
//   "TAP", "<3-10>x", "FOR 5s" (or "ACTIVE", the multiplier, the seconds left under its cooldown
//   shade), never pink, at its configured spot inside the band between the toast lane and Next Up
//   hub: SHOP is the biggest button on screen
//   no ImageLabel/ImageButton in the HUD; the tile/Cash/Gems/HATCH/bag/growth circle icons are vector glyphs
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

    // Cash -> Gems, 8 design px apart as drawn.
    const cash = el("Cash"), gems = el("Gems");
    if (!vis(cash) || !vis(gems)) problems.push("Cash or Gems missing");
    else {
      const gap = (drawn(gems).left - drawn(cash).right) / scaleOf(cash);
      if (!near(gap, 8, 1.5)) problems.push(`Cash -> Gems drawn gap ${gap.toFixed(1)} px (want 8)`);
    }

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

    // Weather line: shown, centered under Cash + Gems, below them; plain far from an event, a chip
    // (the event's color) when soon or active, with the right wording.
    const weather = el("Weather"), cashEl = el("Cash"), gemsEl = el("Gems");
    if (!vis(weather)) problems.push("weather line missing");
    else if (vis(cashEl) && vis(gemsEl)) {
      const w = rect(weather), c = rect(cashEl), g = rect(gemsEl);
      const mid = (c.left + g.right) / 2, wmid = (w.left + w.right) / 2;
      if (Math.abs(mid - wmid) > 2 * scaleOf(weather) + 1) problems.push(`weather line off center (${wmid.toFixed(0)} vs ${mid.toFixed(0)})`);
      if (w.top < c.bottom) problems.push("weather line isn't under the Cash row");
      const chip = vis(weather.querySelector('[title="Chip"]'));
      const text = ((weather.querySelector('[title="Text"] span') || {}).textContent || "").trim();
      if (!weather.querySelector('[title="Glyph"]')) problems.push("weather line has no glyph");
      if (kind.startsWith("hud-weather-idle") && (chip || !/ IN \d+:\d\d$/.test(text))) problems.push(`idle weather "${text}"${chip ? " (boxed)" : ""}`);
      if (kind.startsWith("hud-weather-soon") && (!chip || !/ IN \d+:\d\d$/.test(text))) problems.push(`soon weather "${text}"${chip ? "" : " (no chip)"}`);
      if (kind.startsWith("hud-plot-weather-active") && (!chip || !/ · \d+:\d\d LEFT$/.test(text))) problems.push(`active weather "${text}"`);
    }

    // Right column: visible rows in order, 8 px apart as drawn, the first 8 px under the tiles.
    const order = ["InstantWeather", "Bundle", "BagChip"];
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

    // SHOP at the plot (Config/Hud plotButtons size); SHOP the biggest button in the hub.
    const shop = el("Shop");
    if (plot) {
      if (!vis(shop)) problems.push("Shop missing at the plot");
      else {
        const a = rect(shop), s = scaleOf(shop), want = data.hud.plotButtons;
        if (!near(a.width / s, want.width, 1) || !near(a.height / s, want.height, 1))
          problems.push(`plot Shop ${(a.width / s).toFixed(0)}x${(a.height / s).toFixed(0)} (want ${want.width}x${want.height})`);
      }
      if (el("Water")) problems.push("the old WATER button is still there");
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

    // Growth circle (plot, while an egg grows): offering "CLICK" ("TAP" on touch) / "<n>x" /
    // "FOR 5s", or on its cooldown "ACTIVE" / "<n>x" / "0:04" with the shade showing; navy, never
    // pink; at its configured spot, inside the band between the toast lane and Next Up (8 px clear
    // of each as drawn), so a toast never covers it.
    const boost = el("Boost");
    if (plot && kind.includes("boost") && !vis(boost)) problems.push("the growth circle is missing");
    if (!plot && vis(boost)) problems.push("the growth circle shows in the hub");
    if (plot && vis(boost)) {
      const cfg = data.hud.boost;
      const text = (n) => ((boost.querySelector(`[title="${n}"] span`) || {}).textContent || "").trim();
      const l1 = text("Line1"), mult = text("Mult"), l3 = text("Line3");
      const shade = boost.querySelector('[title="Shade"]');
      const shaded = shade && rect(shade).height > 0.5;
      const touchScene = kind.endsWith("touch");
      if (l1 === "ACTIVE") {
        if (!/^\d+x$/.test(mult) || !/^\d+:\d\d$/.test(l3)) problems.push(`active circle reads "${l1} ${mult} ${l3}"`);
        if (!shaded) problems.push("active circle without its cooldown shade");
      } else {
        const want = touchScene ? "TAP" : "CLICK";
        if (l1 !== want || !/^(3|4|5|6|7|8|9|10)x$/.test(mult) || l3 !== "FOR 5s")
          problems.push(`circle reads "${l1} / ${mult} / ${l3}" (want "${want} / <3-10>x / FOR 5s")`);
        if (shaded) problems.push("waiting circle shows the cooldown shade");
      }
      if (kind.includes("boosted") && l1 !== "ACTIVE") problems.push("the boosted scene's circle isn't active");
      for (const f of boost.querySelectorAll('[title="Glyph"] div')) {
        const bg = getComputedStyle(f).backgroundColor;
        if (bg.includes("255, 79, 163")) { problems.push("the growth circle is pink"); break; }
      }
      // The HUD's scale (the circle's own pulse UIScale doesn't count: it's drawn, not layout).
      const gui = boost.closest(".gui"), s = scaleOf(gui), g = rect(gui), b = drawn(boost);
      const top = (b.top - g.top) / s, bottom = (b.bottom - g.top) / s, canvasH = g.height / s;
      const bandTop = data.hud.toast.y + data.hud.toast.height + cfg.gap;
      const bandBottom = canvasH - data.hud.nextUpBottom - data.hud.nextUpHeight - data.hud.faceOutline - cfg.gap;
      if (top < bandTop - 1.5) problems.push(`growth circle reaches ${(bandTop - top).toFixed(1)} px into the toast lane`);
      if (bottom > bandBottom + 1.5) problems.push(`growth circle reaches ${(bottom - bandBottom).toFixed(1)} px into Next Up's gap`);
      const r = rect(boost), cx = ((r.left + r.right) / 2 - g.left) / s - g.width / s / 2;
      const spotMatch = kind.match(/boost(\d)/);
      if (spotMatch && !near(cx, cfg.spots[Number(spotMatch[1]) - 1], 1)) problems.push(`circle at x ${cx.toFixed(1)} (want spot ${spotMatch[1]}: ${cfg.spots[Number(spotMatch[1]) - 1]})`);
    }

    // No images for icons anywhere in the HUD (scene JSON: the Hud frame's subtree).
    const scene = data.scenes.find((s) => s.name === sceneName);
    const walk = (n, f) => { f(n); for (const c of (Array.isArray(n.children) ? n.children : Object.values(n.children || {}))) walk(c, f); };
    let hudNode = null;
    walk(scene.root, (n) => { if (!hudNode && n.name === "Hud" && n.class === "Frame") hudNode = n; });
    if (hudNode) walk(hudNode, (n) => { if (n.class === "ImageLabel" || n.class === "ImageButton") problems.push(`${n.class} "${n.name}" in the HUD`); });

    // Icons are vector glyphs, not emoji text.
    const OLD = /[\u2190-\u2BFF\u3000-\uFFFF]|[\uD800-\uDBFF]/; // any emoji
    const iconHosts = ["Upgrades", "Daily", "Almanac", "Cash", "Gems"].concat(plot ? ["Hatch", "BagChip", "Boost"] : []);
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
