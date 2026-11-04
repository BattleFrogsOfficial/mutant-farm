// World UI on your own plot (scene tools/preview/scenes/world.luau): soil markers at a phone's
// patch size, egg timers at their real pixel size, the gate's income line at canvas size.
//   * nothing inside a timer overlaps (the "2x" chip vs the bar and its time text);
//   * the multiplier chip shows exactly on the watered timers ("2x" on the pad, "10x" boosted);
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
      // Auto-Harvest's REPLANT toggle: inside the patch, clear of the "+" tile, check glyph when on
      // (an empty box when off), the label in full and readable on a phone.
      const toggle = q(patch, "ReplantToggle");
      if (name.startsWith("PatchToggle")) {
        if (!toggle) { problems.push(`${name}: no toggle drawn`); continue; }
        const face = q(toggle, "Face");
        const fr = paintedRect(face);
        if (!fr || !inside(fr, pr)) problems.push(`${name}: toggle leaves the patch`);
        if (tile && fr && overlap(fr, tile)) problems.push(`${name}: toggle overlaps the "+" tile`);
        const on = !name.includes("Off");
        if (vis(q(face, "Check")) !== on) problems.push(`${name}: check glyph ${on ? "missing" : "shown"}`);
        const box = q(face, "EmptyBox"); // hidden subtrees aren't exported
        if (!!(box && vis(box)) === on) problems.push(`${name}: empty box ${on ? "shown" : "missing"}`);
        const label = q(face, "Text");
        if ((label && label.textContent.trim()) !== "REPLANT") problems.push(`${name}: label "${label && label.textContent.trim()}"`);
        const lf = font(label);
        if (lf < 8) problems.push(`${name}: label only ${lf.toFixed(1)}px on a phone (< 8)`);
        const lr = paintedRect(label);
        if (lr && label.querySelector("span") && label.querySelector("span").getClientRects().length > 1) problems.push(`${name}: label wraps`);
        if (lr && fr && (lr.right > fr.right + 0.5 || lr.left < fr.left - 0.5)) problems.push(`${name}: label spills off the chip`);
        if (!holder) continue;
      }
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
        const wantChip = name.includes("Boost") ? "10x" : "2x";
        if (!chipText || chipText.textContent.trim() !== wantChip) problems.push(`${name}: chip text "${chipText && chipText.textContent}" (want ${wantChip})`);
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

// Next Up's Lab goal (scenes hud-plot-lab*, world.luau) in the tutorial card's chrome: shown on the
// plot, "LAB EGG" / "$12.4K / $25K earned", the line at 16 px (a price) inside its label, the title
// clear of the progress segments.
registerCheck({
  name: "world-nextup",
  match: (s) => s.startsWith("hud-plot-lab"),
  run: (W, H, s) => {
    const nu = document.querySelector('.gui [title="NextUp"]');
    if (!nu || nu.offsetParent === null) return [`${s}: Next Up not shown`];
    const title = nu.querySelector('[title="Title"] span'), span = nu.querySelector('[title="Line"] span');
    if (!nu.querySelector('[title="Glyph"]')) return [`${s}: Next Up has no star glyph`];
    if (!span || !title) return [`${s}: Next Up has no goal text`];
    const problems = [];
    if (title.textContent.trim() !== "LAB EGG") problems.push(`${s}: Next Up title reads "${title.textContent}"`);
    const text = span.textContent.trim();
    if (!/^\$[\d.]+[KMBT]? \/ \$[\d.]+[KMBT]? earned$/.test(text)) problems.push(`${s}: Next Up reads "${text}"`);
    const el = span.closest(".g");
    const designPx = parseFloat(getComputedStyle(span.parentElement).fontSize);
    if (designPx < 16) problems.push(`${s}: Lab goal at ${designPx.toFixed(1)} design px (< 16 for a price)`);
    const sr = span.getBoundingClientRect(), lr = el.getBoundingClientRect();
    if (sr.right > lr.right + 0.5 || sr.left < lr.left - 0.5) problems.push(`${s}: Lab goal spills out of its label`);
    const seg = nu.querySelector('[title="Segments"]');
    const gr = seg && seg.offsetParent !== null ? paintedRect(seg) : null;
    if (!gr) problems.push(`${s}: progress segments missing`);
    else {
      const tr = title.getBoundingClientRect();
      if (tr.right > gr.left + 0.5) problems.push(`${s}: the title runs into the progress segments`);
    }
    return problems;
  },
});
