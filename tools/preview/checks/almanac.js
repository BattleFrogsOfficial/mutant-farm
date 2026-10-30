// Almanac milestone track (scenes from tools/preview/scenes/almanac.luau: almanac-<found>@WxH and
// almanac-tip-26@WxH): the track exists; the title is only "📖 Almanac <n> / <total>"; markers and
// labels don't overlap each other and stay inside the track and the panel; labels draw at >= 11 px
// on screen or are collapsed to their icon; the fill matches its fraction of the current segment;
// passed markers are gold with a check (and as many as expected); nothing of the track overlaps the
// tabs, the grid or the pager; the tooltip scene shows the tapped marker's reward.
registerCheck({
  name: "almanac",
  match: (sceneName) => /^almanac-(tip-)?\d+@/.test(sceneName),
  run: (W, H, sceneName) => {
    const problems = [];
    const vis = (el) => el && el.offsetParent !== null && getComputedStyle(el).display !== "none";
    const [, tipScene, nStr] = /^almanac-(tip-)?(\d+)@/.exec(sceneName);
    const n = +nStr;
    const EVERY = 25, LAST = 400; // Config/Game.almanacMilestones (every 25), 410 species -> 400
    const panel = [...document.querySelectorAll('.gui [title="Panel"]')].find((p) => vis(p) && p.querySelector('[title="AlmanacTrack"]'));
    if (!panel) return ["Almanac panel with a track not found"];
    const track = panel.querySelector('[title="AlmanacTrack"]');
    if (!vis(track)) return ["track hidden"];
    const tr = track.getBoundingClientRect();
    const pr = panel.getBoundingClientRect();
    if (pr.left < 0 || pr.top < 0 || pr.right > W || pr.bottom > H) problems.push("panel goes off screen");

    // Title: found / total, nothing else.
    const titleSpan = panel.querySelector('[title="Header"] [title="TextLabel"] span');
    const title = titleSpan ? titleSpan.textContent : "";
    const m = /^📖 Almanac (\d+) \/ (\d+)$/.exec(title);
    if (!m) problems.push(`title "${title}" isn't "📖 Almanac <n> / <total>"`);
    else if (+m[1] !== n) problems.push(`title shows ${m[1]} found, want ${n}`);

    const inner = [...track.children].find((c) => c.classList.contains("inner"));
    const parts = [...inner.children].filter((c) => c.title && vis(c));
    const markers = parts.filter((c) => c.title.startsWith("Marker"));
    const labels = parts.filter((c) => c.title.startsWith("Label"));
    const tooltip = parts.find((c) => c.title === "Tooltip");
    if (markers.length === 0) problems.push("no markers");

    // Markers and labels: no overlaps (the tooltip covers labels on purpose), inside track + panel.
    const items = [...markers, ...labels].map((el) => ({ name: el.title, r: paintedRect(el) })).filter((x) => x.r);
    for (let i = 0; i < items.length; i++) {
      const a = items[i];
      if (a.r.left < tr.left - 1 || a.r.right > tr.right + 1 || a.r.top < tr.top - 1 || a.r.bottom > tr.bottom + 1) problems.push(`${a.name} sticks out of the track`);
      if (a.r.left < pr.left || a.r.right > pr.right) problems.push(`${a.name} sticks out of the panel`);
      for (let j = i + 1; j < items.length; j++) {
        const b = items[j];
        const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
        const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
        if (w > 0.5 && h > 0.5) problems.push(`${a.name} overlaps ${b.name} (${w.toFixed(0)}x${h.toFixed(0)}px)`);
      }
    }
    // Tap targets (the marker buttons themselves): side by side, never overlapping.
    const hits = markers.map((el) => ({ name: el.title, r: el.getBoundingClientRect() })).sort((a, b) => a.r.left - b.r.left);
    for (let i = 1; i < hits.length; i++) {
      const over = hits[i - 1].r.right - hits[i].r.left;
      if (over > 0.5) problems.push(`tap targets ${hits[i - 1].name} and ${hits[i].name} overlap by ${over.toFixed(1)}px`);
    }
    // Each label spans its own marker (packing may shift it sideways, never off its marker), and
    // on desktop sizes the big later ones keep their numbers ("100 🥚Toxic", never just "🥚").
    const desktop = W >= 1024 && H >= 540;
    for (const el of labels) {
      const at = el.title.slice("Label".length);
      const mk = track.querySelector(`[title="Marker${at}"] [title="Passed"], [title="Marker${at}"] [title="Next"], [title="Marker${at}"] [title="Later"]`);
      if (!mk) { problems.push(`${el.title} has no marker`); continue; }
      const mr = mk.getBoundingClientRect(), lr = el.getBoundingClientRect();
      const cx = (mr.left + mr.right) / 2;
      if (lr.left > cx + 0.5 || lr.right < cx - 0.5) problems.push(`${el.title} doesn't span its marker`);
      if (desktop && !el.textContent.includes(at)) problems.push(`${el.title} "${el.textContent.trim()}" lost its number on desktop`);
    }
    // On-screen font: the label's px times every scale above it (HUD scale, panel fit).
    const fontOf = (el) => {
      const span = el.querySelector("span");
      return span ? parseFloat(getComputedStyle(span.parentElement).fontSize) * (el.getBoundingClientRect().width / el.offsetWidth) : 0;
    };
    for (const el of labels) {
      const text = el.textContent.trim();
      const iconOnly = !/[\p{L}\p{N}]/u.test(text);
      const px = fontOf(el);
      if (!iconOnly && px < 11) problems.push(`${el.title} "${text}" at ${px.toFixed(1)}px (< 11, not collapsed)`);
    }

    // Fill: (found - last passed) / (next - last passed) of the segment that ends at the big diamond.
    const fill = parts.find((c) => c.title === "Fill");
    const bar = parts.find((c) => c.title === "Bar");
    const allPassed = n >= LAST;
    if (!fill || !bar) problems.push("fill or bar missing");
    else {
      const fr = fill.getBoundingClientRect();
      let want;
      if (allPassed) want = bar.getBoundingClientRect().width;
      else {
        const next = track.querySelector('[title="Next"]');
        if (!vis(next)) problems.push("no next-milestone diamond");
        else {
          const nr = next.getBoundingClientRect();
          const lastAt = Math.floor(n / EVERY) * EVERY;
          want = ((n - lastAt) / EVERY) * ((nr.left + nr.right) / 2 - fr.left);
        }
      }
      if (want !== undefined && Math.abs(fr.width - want) > 2) problems.push(`fill ${fr.width.toFixed(1)}px, want ${want.toFixed(1)}px`);
    }

    // Passed markers: every passed milestone, gold with a check.
    const passed = [...track.querySelectorAll('[title="Passed"]')].filter(vis);
    const wantPassed = Math.min(Math.floor(n / EVERY), LAST / EVERY);
    if (passed.length !== wantPassed) problems.push(`${passed.length} passed markers, want ${wantPassed}`);
    for (const p of passed) {
      if (getComputedStyle(p).backgroundColor !== "rgb(255, 210, 74)") problems.push(`passed marker ${p.parentElement.closest(".g").title} isn't gold`);
      const holder = p.parentElement.closest(".g");
      if (!holder.querySelector('[title="Check"]')) problems.push(`passed marker ${holder.title} has no check`);
    }

    // Nothing of the track overlaps the tabs, the grid or the pager.
    const trackRect = paintedRect(track);
    for (const name of ["Tabs", "Grid", "Pager"]) {
      const el = panel.querySelector(`[title="${name}"]`);
      if (!vis(el)) { problems.push(`${name} missing`); continue; }
      const r = paintedRect(el);
      if (!r || !trackRect) continue;
      const w = Math.min(r.right, trackRect.right) - Math.max(r.left, trackRect.left);
      const h = Math.min(r.bottom, trackRect.bottom) - Math.max(r.top, trackRect.top);
      if (w > 0.5 && h > 0.5) problems.push(`track overlaps ${name} (${w.toFixed(0)}x${h.toFixed(0)}px)`);
    }
    // Tabs vs grid vs pager too (the grid lost a few px of height for the track).
    const blocks = ["Tabs", "Grid", "Pager"].map((name) => ({ name, r: paintedRect(panel.querySelector(`[title="${name}"]`)) })).filter((x) => x.r);
    for (let i = 0; i < blocks.length; i++) for (let j = i + 1; j < blocks.length; j++) {
      const a = blocks[i].r, b = blocks[j].r;
      const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (w > 0.5 && h > 0.5) problems.push(`${blocks[i].name} overlaps ${blocks[j].name}`);
    }

    // Tabs: the tier name and its count, each on one line at its full size (never squeezed).
    const tabsEl = panel.querySelector('[title="Tabs"]');
    for (const part of tabsEl ? tabsEl.querySelectorAll('[title="TabName"], [title="TabCount"]') : []) {
      const host = part.querySelector(".txt");
      const span = host && host.querySelector("span");
      if (!span || !vis(part)) continue;
      const size = parseFloat(getComputedStyle(host).fontSize), max = +host.dataset.max || size;
      if (size < max * 0.98) problems.push(`tab "${span.textContent}" squeezed to ${size.toFixed(1)} px (full ${max})`);
      if (span.getClientRects().length > 1) problems.push(`tab "${span.textContent}" wraps`);
    }
    if (!tabsEl || tabsEl.querySelectorAll('[title="TabName"]').length < 7) problems.push("tabs missing their name line");

    // Tooltip: only in the tip scene, the tapped marker's reward, inside the track, readable.
    if (tipScene) {
      if (!tooltip) problems.push("tooltip missing");
      else {
        const text = tooltip.textContent.trim();
        if (text !== "100 species: Toxic Egg") problems.push(`tooltip says "${text}"`);
        const r = tooltip.getBoundingClientRect();
        if (r.left < tr.left - 1 || r.right > tr.right + 1 || r.bottom > tr.bottom + 1) problems.push("tooltip sticks out of the track");
        const px = fontOf(tooltip.querySelector('[title="Text"]'));
        if (px < 11) problems.push(`tooltip text at ${px.toFixed(1)}px (< 11)`);
        const span = tooltip.querySelector("span").getBoundingClientRect();
        if (span.left < r.left - 0.5 || span.right > r.right + 0.5) problems.push("tooltip text overflows its box");
      }
    } else if (tooltip) problems.push("tooltip open without a tap");
    return problems;
  },
});
