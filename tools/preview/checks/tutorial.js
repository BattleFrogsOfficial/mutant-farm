// The tutorial card (scenes tools/preview/scenes/tutorial.luau): shown in both zones, the right
// chrome (gold stripe, star or check glyph), title in CAPS, "n / 9" on the title row clear of the
// title, one instruction line that fits its label on one line, and in the hub above SHOP's row
// (when SHOP sits bottom-right). The HUD overlap check covers the rest.
registerCheck({
  name: "tutorial",
  match: (s) => s.startsWith("hud-plot-tut") || s.startsWith("hud-hub-tut"),
  run: (W, H, s) => {
    const problems = [];
    const card = document.querySelector('.gui [title="NextUp"]');
    if (!card || card.offsetParent === null) return [`${s}: the tutorial card isn't shown`];
    const q = (name) => card.querySelector(`[title="${name}"]`);
    const textOf = (el) => ((el && el.querySelector("span")) || {}).textContent || "";
    const r = (el) => el.getBoundingClientRect();
    const overlap = (a, b) => Math.min(a.right, b.right) - Math.max(a.left, b.left) > 0.5 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 0.5;
    if (!q("Stripe")) problems.push(`${s}: no gold stripe`);
    if (!card.querySelector('[title="Glyph"]')) problems.push(`${s}: no glyph`);
    const title = q("Title"), line = q("Line");
    const t = textOf(title).trim(), l = textOf(line).trim();
    if (!t || t !== t.toUpperCase()) problems.push(`${s}: title "${t}" not in CAPS`);
    if (!l) problems.push(`${s}: no instruction line`);
    // Text fits on one line inside its label.
    for (const [name, el] of [["title", title], ["line", line]]) {
      const span = el && el.querySelector("span");
      if (!span) continue;
      const sr = span.getBoundingClientRect(), lr = r(el);
      if (sr.right > lr.right + 0.5) problems.push(`${s}: ${name} "${span.textContent}" spills out of its label`);
      if (span.getClientRects().length > 1) problems.push(`${s}: ${name} wraps onto two lines`);
    }
    const tutorial = !s.includes("nextup");
    const count = q("StepCount");
    if (tutorial) {
      if (!count || count.offsetParent === null) problems.push(`${s}: no "n / 9"`);
      else {
        if (!/^\d \/ 9$/.test(textOf(count).trim())) problems.push(`${s}: step count reads "${textOf(count)}"`);
        const ts = title.querySelector("span");
        if (ts && overlap(ts.getBoundingClientRect(), count.querySelector("span").getBoundingClientRect()))
          problems.push(`${s}: the title runs into "n / 9"`);
      }
    } else if (count && count.offsetParent !== null) problems.push(`${s}: Next Up shows a step count`);
    // In the hub, above SHOP's row when SHOP is bottom-right (8 px as drawn: both 3 px outlines).
    if (s.startsWith("hud-hub") && !s.endsWith("touch")) {
      const shop = document.querySelector('.gui [title="Shop"]');
      if (shop && shop.offsetParent !== null) {
        const gui = card.closest(".gui");
        const scale = gui.getBoundingClientRect().width / gui.offsetWidth;
        const sr = r(shop), cr = r(card);
        if (sr.left < cr.right && sr.top - cr.bottom < (8 + 6) * scale - 1.5 && sr.top > H / 2)
          problems.push(`${s}: the card isn't clear above SHOP's row (${((sr.top - cr.bottom) / scale).toFixed(1)} px)`);
      }
    }
    return problems;
  },
});
