// World UI on your own plot (scene tools/preview/scenes/world.luau): soil markers at a phone's
// patch size, egg timers at their real pixel size, the gate's income line at canvas size.
//   * nothing inside a timer overlaps (the "2x" chip vs the bar and its time text);
//   * the "2x" chip shows exactly on the watered timers;
//   * a soil tile (even mid-pulse, shadow included) stays on its patch;
//   * on-screen text sizes stay readable.
registerCheck({
  name: "world",
  match: (sceneName) => sceneName.startsWith("world"),
  run: (W, H) => {
    const problems = [];
    const vis = (el) => el && el.offsetParent !== null && getComputedStyle(el).display !== "none";
    const q = (root, name) => root.querySelector(`[title="${name}"]`);
    // On-screen font px of a text element: the fitted size times every scale above it.
    const font = (el) => {
      const span = el && el.querySelector("span");
      if (!span) return 0;
      return parseFloat(getComputedStyle(span.parentElement).fontSize) * (el.getBoundingClientRect().width / el.offsetWidth);
    };
    const overlap = (a, b) => {
      const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      return w > 0.5 && h > 0.5 ? [w, h] : null;
    };
    const inside = (r, box) => r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;
    const offScreen = (r) => r.left < 0 || r.top < 0 || r.right > W || r.bottom > H;

    // Soil markers.
    const patches = [...document.querySelectorAll('.gui [title^="Patch"]')];
    if (patches.length < 3) problems.push(`only ${patches.length} soil patches drawn`);
    for (const patch of patches) {
      const name = patch.title;
      const pr = patch.getBoundingClientRect();
      if (offScreen(pr)) problems.push(`${name} goes off screen`);
      const holder = q(patch, "Holder");
      const tile = holder && paintedRect(holder);
      if (!tile) { problems.push(`${name}: no tile drawn`); continue; }
      if (!inside(tile, pr)) problems.push(`${name}: tile leaves the patch`);
      const text = q(holder, "Text");
      const want = name.includes("Price") ? /^\$[\d.]+[KMBT]?$/ : /^\+$/;
      const content = text && text.textContent.trim();
      if (!want.test(content || "")) problems.push(`${name}: text "${content}"`);
      const f = font(text);
      const min = name.includes("Price") ? 11 : 14;
      if (f < min) problems.push(`${name}: text only ${f.toFixed(1)}px on a phone (< ${min})`);
      const tr = paintedRect(text);
      if (tr && !inside(tr, paintedRect(q(holder, "Tile")))) problems.push(`${name}: text spills off the tile`);
    }

    // Timers.
    const timers = [...document.querySelectorAll('.gui [title^="Timer"]')];
    if (timers.length < 3) problems.push(`only ${timers.length} timers drawn`);
    for (const timer of timers) {
      const name = timer.title;
      const bar = q(timer, "Bar"), chip = q(timer, "Chip");
      const watered = name.includes("Watered");
      if (vis(chip) !== watered) problems.push(`${name}: 2x chip ${vis(chip) ? "shown" : "missing"}`);
      const br = paintedRect(bar);
      if (!br) { problems.push(`${name}: no bar`); continue; }
      if (offScreen(br)) problems.push(`${name} goes off screen`);
      const time = q(bar, "Time");
      const tf = font(time);
      if (tf < 12) problems.push(`${name}: time text only ${tf.toFixed(1)}px (< 12)`);
      // A BillboardGui clips its descendants: every face, its ink outline (a box-shadow ring here)
      // and every hard shadow must stay inside the timer's box.
      const hr = timer.getBoundingClientRect();
      for (const d of timer.querySelectorAll(".g")) {
        if (!vis(d)) continue;
        const r = d.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) continue;
        const cs = getComputedStyle(d);
        const ring = /0px 0px 0px ([\d.]+)px/.exec(cs.boxShadow);
        const k = d.offsetWidth ? r.width / d.offsetWidth : 1;
        const e = ring ? parseFloat(ring[1]) * k : 0;
        const painted = ring || (cs.backgroundColor !== "transparent" && !/,\s*0\)$/.test(cs.backgroundColor));
        if (!painted) continue;
        const out = { left: r.left - e, top: r.top - e, right: r.right + e, bottom: r.bottom + e };
        if (!inside(out, hr)) problems.push(`${name}: ${d.title} (outline included) is clipped by the BillboardGui`);
      }
      if (vis(chip)) {
        const cr = paintedRect(chip);
        const o = cr && overlap(cr, br);
        if (o) problems.push(`${name}: 2x chip overlaps the bar (${o[0].toFixed(0)}x${o[1].toFixed(0)}px)`);
        const tr = paintedRect(time);
        const ot = cr && tr && overlap(cr, tr);
        if (ot) problems.push(`${name}: 2x chip overlaps the time text`);
        const chipText = q(chip, "Text");
        if (!chipText || chipText.textContent.trim() !== "2x") problems.push(`${name}: chip text "${chipText && chipText.textContent}"`);
        const cf = font(chipText);
        if (cf < 11) problems.push(`${name}: chip text only ${cf.toFixed(1)}px (< 11)`);
      }
    }

    // Gate income line (canvas px: 40 per stud).
    for (const name of ["GateNew", "GateIncome"]) {
      const board = document.querySelector(`.gui [title="${name}"]`);
      if (!board) { problems.push(`${name} missing`); continue; }
      const text = q(board, "Text");
      const content = text ? text.textContent.trim() : "";
      const want = name === "GateNew" ? /^\$0\/min · PLANT EGGS$/ : /^\$[\d.]+[KMBT]?\/min$/;
      if (!want.test(content)) problems.push(`${name}: text "${content}"`);
      const f = font(text);
      if (f < 16) problems.push(`${name}: text only ${f.toFixed(1)} canvas px (< 16, 0.4 stud)`);
      // Never broken mid-phrase: as many lines as the text has (1, or 2 before the first harvest).
      const span = text && text.querySelector("span");
      const lines = span ? Math.round(span.getBoundingClientRect().height / (f * 1.05)) : 0;
      if (lines > content.split("\n").length) problems.push(`${name}: wraps onto ${lines} lines`);
    }
    return problems;
  },
});

// Next Up's longest goal, Lab's earned gate (scenes hud-plot-lab*, world.luau): shown on the plot,
// the right text, fits its label without spilling, and isn't shrunk below the label's usual size
// (the goals share one label with MaxTextSize 15 design px; "NEXT SOIL PATCH: $675" gets 15).
registerCheck({
  name: "world-nextup",
  match: (s) => s.startsWith("hud-plot-lab"),
  run: (W, H, s) => {
    const nu = document.querySelector('.gui [title="NextUp"]');
    if (!nu || nu.offsetParent === null) return [`${s}: Next Up not shown`];
    const span = [...nu.querySelectorAll("span")].find((x) => /EARNED|SOIL|EGG/.test(x.textContent));
    if (!nu.querySelector('[title="Glyph"]')) return [`${s}: Next Up has no star glyph`];
    if (!span) return [`${s}: Next Up has no goal text`];
    const problems = [];
    const text = span.textContent.trim();
    if (!/^LAB EGG: \$[\d.]+[KMBT]? \/ \$[\d.]+[KMBT]? EARNED$/.test(text)) problems.push(`${s}: Next Up reads "${text}"`);
    const el = span.closest(".g");
    const designPx = parseFloat(getComputedStyle(span.parentElement).fontSize);
    if (designPx < 14) problems.push(`${s}: Lab goal shrunk to ${designPx.toFixed(1)} design px (< 14)`);
    const sr = span.getBoundingClientRect(), lr = el.getBoundingClientRect();
    if (sr.right > lr.right + 0.5 || sr.left < lr.left - 0.5) problems.push(`${s}: Lab goal spills out of its label`);
    const seg = nu.querySelector('[title="Segments"]');
    const gr = seg && seg.offsetParent !== null ? paintedRect(seg) : null;
    if (!gr) problems.push(`${s}: progress segments missing`);
    else if (sr.right > gr.left + 0.5) problems.push(`${s}: Lab goal runs into the progress segments`);
    return problems;
  },
});
