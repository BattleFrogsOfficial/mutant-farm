// Renders build/ui.json (from ui-export.luau) to PNGs: each GUI scene laid out by the browser with
// Roblox's rules (UDim2 + AnchorPoint, UIListLayout/UIGridLayout, UIPadding, UICorner, UIStroke,
// UIScale, TextScaled), over a world screenshot, at desktop and phone sizes, with the Roblox top bar.
//   node tools/preview/ui-render.mjs build/ui.json build/ui-shots [background.png]
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const { chromium } = createRequire(import.meta.url)("playwright");

const [uiPath, outDir, bgPath] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const ui = fs.readFileSync(uiPath, "utf8");
const bg = bgPath && fs.existsSync(bgPath) ? "data:image/png;base64," + fs.readFileSync(bgPath).toString("base64") : "";

const DESIGN = { w: 900, h: 540 };
const TOPBAR = 58; // Roblox's top bar inset in 2025+ clients
const sizes = [
  ["desktop", 1280, 720],
  ["phone", 844, 390],
];
// Extra screens the HUD overlap check runs on (no screenshots): small/wide phones, tablet, 1080p.
const checkSizes = [
  ["phone-small", 667, 375],
  ["phone-wide", 800, 360],
  ["tablet", 1024, 768],
  ["hd", 1920, 1080],
];
// HUD zones that must never overlap each other, Roblox's top-left buttons, or the screen edge.
const ZONES = ["Cash", "RebirthStrip", "GroupBadge", "Gems", "Daily", "Almanac", "Upgrades", "Shop", "Weather", "Bundle", "Toast", "EggTray", "Water", "NextUp", "BagChip"];

const html = `<!doctype html><html><head><style>
* { box-sizing: border-box; }
body { margin: 0; overflow: hidden; font-family: "Fredoka", "Arial Rounded MT Bold", "Nunito", Arial, sans-serif; }
#screen { position: relative; overflow: hidden; background: #8fc96f center/cover no-repeat; }
#topbar { position: absolute; left: 0; top: 0; right: 0; background: transparent; z-index: 1000; }
#topbar i { position: absolute; top: 4px; height: 38px; border-radius: 19px; background: rgba(0,0,0,.55); }
.g { position: absolute; }
.inner { position: absolute; }
.txt { display: flex; width: 100%; height: 100%; overflow: hidden; line-height: 1.05; white-space: pre-wrap; word-break: break-word; }
.vp { position: absolute; inset: 12%; border-radius: 50% 50% 46% 46% / 58% 58% 42% 42%;
  background: radial-gradient(circle at 35% 30%, #fff8, #aab3 60%, #6672); }
.vp.sil { background: #000d; }
</style></head><body><div id="screen"><div id="topbar"><i style="left:6px;width:36px"></i><i style="left:50px;width:108px"></i></div></div>
<script>
const data = ${ui};
const rgba = (c, t) => c ? \`rgba(\${Math.round(c[0]*255)},\${Math.round(c[1]*255)},\${Math.round(c[2]*255)},\${1-(t??0)})\` : "transparent";
const MODS = new Set(["UICorner","UIStroke","UIPadding","UIListLayout","UIGridLayout","UIScale","UIGradient","UIAspectRatioConstraint","UITextSizeConstraint","UISizeConstraint"]);
const GUI = new Set(["Frame","TextLabel","TextButton","TextBox","ImageLabel","ImageButton","ScrollingFrame","ViewportFrame","CanvasGroup"]);
const dim = (sc, off) => \`calc(\${sc*100}% + \${off}px)\`;

const kids = (n) => Array.isArray(n.children) ? n.children : Object.values(n.children || {});
function build(node, parentInner, parentLayout) {
  if (!GUI.has(node.class)) return;
  const p = Array.isArray(node.props) ? {} : (node.props || {});
  const mods = {};
  for (const c of kids(node)) if (MODS.has(c.class)) mods[c.class] = c.props;
  const el = document.createElement("div");
  el.className = "g";
  el.title = node.name;
  if (p.Visible === false) el.style.display = "none";
  const [sx, ox, sy, oy] = p.Size || [0,100,0,100];
  const [px, pox, py, poy] = p.Position || [0,0,0,0];
  const [ax, ay] = p.AnchorPoint || [0,0];
  const auto = p.AutomaticSize || "None";
  const w = dim(sx, ox), h = dim(sy, oy);
  if (parentLayout) {
    el.style.position = "relative";
    el.style.flex = "0 0 auto";
    if (parentLayout === "grid") { el.style.width = "100%"; el.style.height = "100%"; }
    else { el.style.width = (auto === "X" || auto === "XY") ? "auto" : w; el.style.height = (auto === "Y" || auto === "XY") ? "auto" : h; }
    if (auto === "X" || auto === "XY") el.style.minWidth = ox + "px";
    if (auto === "Y" || auto === "XY") el.style.minHeight = oy + "px";
    el.style.order = p.LayoutOrder || 0;
  } else {
    el.style.left = dim(px, pox); el.style.top = dim(py, poy);
    el.style.width = (auto === "X" || auto === "XY") ? "auto" : w;
    el.style.height = (auto === "Y" || auto === "XY") ? "auto" : h;
    el.style.transform = \`translate(\${-ax*100}%, \${-ay*100}%)\` + (p.Rotation ? \` rotate(\${p.Rotation}deg)\` : "");
  }
  el.style.zIndex = p.ZIndex ?? 1;
  const isText = node.class.startsWith("Text");
  el.style.background = rgba(p.BackgroundColor3, p.BackgroundTransparency ?? 0);
  if (node.class === "ScrollingFrame" || p.ClipsDescendants) el.style.overflow = "hidden";
  if (p.Rotation && parentLayout) el.style.rotate = p.Rotation + "deg";
  if (mods.UICorner) { const [s, o] = mods.UICorner.CornerRadius; el.style.borderRadius = s >= 0.5 ? "9999px" : (s > 0 ? s*100 + "%" : o + "px"); }
  if (mods.UIScale) { el.style.scale = mods.UIScale.Scale; el.style.transformOrigin = \`\${ax*100}% \${ay*100}%\`; }
  if (mods.UIGradient && mods.UIGradient.Color && (p.BackgroundTransparency ?? 0) < 1) {
    const ks = mods.UIGradient.Color.map(k => \`rgb(\${k[1]*255},\${k[2]*255},\${k[3]*255}) \${k[0]*100}%\`).join(",");
    const rot = (mods.UIGradient.Rotation ?? 0) + 90;
    el.style.backgroundImage = \`linear-gradient(\${rot}deg, \${ks})\`;
    el.style.backgroundBlendMode = "multiply";
  }
  if (mods.UIGradient && Array.isArray(mods.UIGradient.Transparency) && !isText) {
    const ks = mods.UIGradient.Transparency.map(k => \`rgba(0,0,0,\${1 - k[1]}) \${k[0]*100}%\`).join(",");
    const rot = (mods.UIGradient.Rotation ?? 0) + 90;
    el.style.maskImage = \`linear-gradient(\${rot}deg, \${ks})\`;
  }
  if (mods.UISizeConstraint && mods.UISizeConstraint.MaxSize) {
    const [mx, my] = mods.UISizeConstraint.MaxSize; if (mx < 1e6) el.style.maxWidth = mx + "px"; if (my < 1e6) el.style.maxHeight = my + "px";
  }
  if (mods.UIAspectRatioConstraint) el.style.aspectRatio = mods.UIAspectRatioConstraint.AspectRatio;
  const strokeMode = mods.UIStroke && (mods.UIStroke.ApplyStrokeMode || "Contextual");
  if (mods.UIStroke && mods.UIStroke.Enabled !== false && (strokeMode === "Border" || !isText)) {
    el.style.boxShadow = \`0 0 0 \${mods.UIStroke.Thickness}px \${rgba(mods.UIStroke.Color, mods.UIStroke.Transparency)}\`;
  }
  parentInner.appendChild(el);

  const inner = document.createElement("div");
  inner.className = "inner";
  const pad = mods.UIPadding || {};
  const pv = (u, size) => u ? \`calc(\${u[0]*100}% + \${u[1]}px)\` : "0px";
  inner.style.left = pv(pad.PaddingLeft); inner.style.right = pv(pad.PaddingRight);
  inner.style.top = pv(pad.PaddingTop); inner.style.bottom = pv(pad.PaddingBottom);
  if (auto !== "None") { inner.style.position = "relative"; inner.style.inset = "auto"; inner.style.height = "100%"; inner.style.display = "flex"; }
  el.appendChild(inner);

  if (isText) {
    const t = document.createElement("div");
    t.className = "txt";
    const xa = p.TextXAlignment || "Center", ya = p.TextYAlignment || "Center";
    t.style.justifyContent = xa === "Left" ? "flex-start" : xa === "Right" ? "flex-end" : "center";
    t.style.textAlign = xa.toLowerCase() === "center" ? "center" : xa.toLowerCase();
    t.style.alignItems = ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center";
    t.style.color = rgba(p.TextColor3, p.TextTransparency ?? 0);
    if (p.Font === "GothamBlack" || p.Font === "GothamBold") { t.style.fontFamily = "Inter, sans-serif"; t.style.fontWeight = p.Font === "GothamBlack" ? "900" : "700"; }
    else if (p.Font && p.Font !== "FredokaOne") t.style.fontFamily = "Arial, sans-serif";
    let text = p.Text || "";
    if (p.RichText) text = text.replace(/<font[^>]*color="([^"]+)"[^>]*>/g, '<span style="color:$1">').replace(/<\\/font>/g, "</span>");
    else text = text.replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
    t.innerHTML = "<span>" + text + "</span>";
    if (mods.UIStroke && strokeMode !== "Border") {
      const c = rgba(mods.UIStroke.Color, mods.UIStroke.Transparency), s = mods.UIStroke.Thickness;
      t.style.textShadow = [[-s,0],[s,0],[0,-s],[0,s],[-s,-s],[s,s],[-s,s],[s,-s]].map(([a,b]) => \`\${a}px \${b}px 0 \${c}\`).join(",");
    }
    t.dataset.scaled = p.TextScaled ? "1" : "";
    t.dataset.max = (mods.UITextSizeConstraint && mods.UITextSizeConstraint.MaxTextSize) || 100;
    t.style.fontSize = (p.TextScaled ? 100 : (p.TextSize || 14)) + "px";
    if (!p.TextScaled && !p.TextWrapped) t.style.whiteSpace = "pre";
    if (auto !== "None") { t.style.position = "relative"; t.style.width = "auto"; t.style.height = "100%"; t.style.whiteSpace = "nowrap"; }
    // A UIGradient on a text object tints the text.
    if (mods.UIGradient && mods.UIGradient.Color && (p.BackgroundTransparency ?? 0) >= 1) {
      const ks = mods.UIGradient.Color.map(k => \`rgb(\${k[1]*255},\${k[2]*255},\${k[3]*255}) \${k[0]*100}%\`).join(",");
      t.firstChild.style.backgroundImage = \`linear-gradient(180deg, \${ks})\`;
      t.firstChild.style.webkitBackgroundClip = "text";
      t.firstChild.style.color = "transparent";
    }
    inner.appendChild(t);
  }
  if (node.class === "ViewportFrame") {
    const v = document.createElement("div");
    v.className = "vp" + (node.attrs && node.attrs.Silhouette ? " sil" : "");
    inner.appendChild(v);
  }

  let layout = null;
  if (mods.UIListLayout) {
    const l = mods.UIListLayout;
    const row = l.FillDirection === "Horizontal";
    layout = "list";
    inner.style.display = "flex";
    inner.style.flexDirection = row ? "row" : "column";
    const gap = l.Padding ? l.Padding[1] : 0;
    inner.style.gap = gap + "px";
    const ha = { Left: "flex-start", Center: "center", Right: "flex-end" }[l.HorizontalAlignment || "Left"];
    const va = { Top: "flex-start", Center: "center", Bottom: "flex-end" }[l.VerticalAlignment || "Top"];
    inner.style.justifyContent = row ? ha : va;
    inner.style.alignItems = row ? va : ha;
  } else if (mods.UIGridLayout) {
    const g = mods.UIGridLayout;
    layout = "grid";
    inner.style.display = "grid";
    const cw = g.CellSize ? g.CellSize[1] : 100, ch = g.CellSize ? g.CellSize[3] : 100;
    inner.style.gridTemplateColumns = \`repeat(auto-fill, \${cw}px)\`;
    inner.style.gridAutoRows = ch + "px";
    inner.style.columnGap = (g.CellPadding ? g.CellPadding[1] : 5) + "px";
    inner.style.rowGap = (g.CellPadding ? g.CellPadding[3] : 5) + "px";
    inner.style.justifyContent = { Left: "start", Center: "center", Right: "end" }[g.HorizontalAlignment || "Left"];
    inner.style.alignContent = "start";
  }
  for (const c of kids(node)) build(c, inner, layout);
}

function fitText() {
  for (const t of document.querySelectorAll(".txt")) {
    if (!t.dataset.scaled || t.offsetParent === null) continue;
    let lo = 4, hi = Math.min(+t.dataset.max || 100, 100);
    t.style.fontSize = hi + "px";
    if (t.scrollHeight <= t.clientHeight + 1 && t.scrollWidth <= t.clientWidth + 1) continue;
    while (hi - lo > 0.5) {
      const mid = (lo + hi) / 2;
      t.style.fontSize = mid + "px";
      if (t.scrollHeight <= t.clientHeight + 1 && t.scrollWidth <= t.clientWidth + 1) lo = mid; else hi = mid;
    }
    t.style.fontSize = lo + "px";
  }
}

window.render = (sceneIndex, W, H) => {
  const screen = document.getElementById("screen");
  screen.style.width = W + "px"; screen.style.height = H + "px";
  screen.style.backgroundImage = ${JSON.stringify(bg ? `url(${bg})` : "none")};
  document.getElementById("topbar").style.height = ${TOPBAR} + "px";
  for (const old of screen.querySelectorAll(".gui")) old.remove();
  // The HUD sits below Roblox's top bar (IgnoreGuiInset off); only the hatch cutscene is full screen.
  const full = data.scenes[sceneIndex].name === "hatch";
  const inset = full ? 0 : ${TOPBAR};
  const usableH = H - inset;
  const scale = Math.min(Math.max(Math.min(W / ${DESIGN.w}, usableH / ${DESIGN.h}), 0.5), 1.4);
  const gui = document.createElement("div");
  gui.className = "gui inner";
  gui.style.left = "0"; gui.style.top = inset + "px";
  gui.style.width = (W / scale) + "px"; gui.style.height = (usableH / scale) + "px";
  gui.style.transformOrigin = "0 0"; gui.style.transform = \`scale(\${scale})\`;
  screen.appendChild(gui);
  const root = data.scenes[sceneIndex].root;
  // The exported root is the scaled Root frame; render its children into the GUI area.
  for (const c of kids(root)) build(c, gui, null);
  fitText();
  return data.scenes[sceneIndex].name;
};
window.sceneCount = data.scenes.length;

// Painted area of a zone: union of its visible descendants that draw something (fill, outline or
// text), so transparent layout containers don't count.
function paintedRect(el) {
  let r = null;
  const add = (b) => {
    if (b.width < 1 || b.height < 1) return;
    r = r ? { left: Math.min(r.left, b.left), top: Math.min(r.top, b.top), right: Math.max(r.right, b.right), bottom: Math.max(r.bottom, b.bottom) }
          : { left: b.left, top: b.top, right: b.right, bottom: b.bottom };
  };
  for (const d of [el, ...el.querySelectorAll("*")]) {
    if (d.offsetParent === null && d !== el) continue;
    const cs = getComputedStyle(d);
    if (cs.visibility === "hidden" || cs.display === "none") continue;
    const bgAlpha = /rgba\\([^)]*,\\s*([\\d.]+)\\)$/.exec(cs.backgroundColor);
    const painted = (cs.backgroundColor !== "transparent" && !(bgAlpha && +bgAlpha[1] === 0)) ||
      cs.boxShadow !== "none" || (d.tagName === "SPAN" && d.textContent.trim() !== "");
    if (painted) {
      // Clip by ancestors that clip (ClipsDescendants / ScrollingFrame), like Roblox draws it.
      let b = d.getBoundingClientRect();
      b = { left: b.left, top: b.top, right: b.right, bottom: b.bottom };
      for (let p = d.parentElement; p && p !== document.body; p = p.parentElement) {
        if (getComputedStyle(p).overflow === "hidden" && p.id !== "screen") {
          const c = p.getBoundingClientRect();
          b = { left: Math.max(b.left, c.left), top: Math.max(b.top, c.top), right: Math.min(b.right, c.right), bottom: Math.min(b.bottom, c.bottom) };
        }
      }
      add({ left: b.left, top: b.top, right: b.right, bottom: b.bottom, width: b.right - b.left, height: b.bottom - b.top });
    }
  }
  return r;
}

window.checkOverlaps = (W, H, touch) => {
  const problems = [];
  const rects = [];
  for (const name of ${JSON.stringify(ZONES)}) {
    const el = document.querySelector(\`.gui [title="\${name}"]\`);
    if (!el) continue;
    const r = paintedRect(el);
    if (r) rects.push({ name, r });
  }
  // Items drawn on the egg tray (tab, 2x Luck badge, cards, HATCH) against each other; the
  // tray's own background layers (Shadow, Tray) are meant to sit under them.
  for (const name of ["EggTray"]) {
    const el = document.querySelector(\`.gui [title="\${name}"]\`);
    if (!el) continue;
    const items = [...el.querySelectorAll(":scope > .inner > *, :scope > *")].filter((c) => c.title && c.offsetParent !== null && !["Shadow", "Tray"].includes(c.title))
      .map((c) => ({ name: name + "/" + c.title, r: paintedRect(c) })).filter((x) => x.r);
    for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) {
      const a = items[i], b = items[j];
      const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
      const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      if (w > 0.5 && h > 0.5) problems.push(\`\${a.name} overlaps \${b.name} (\${w.toFixed(0)}x\${h.toFixed(0)}px)\`);
    }
  }
  for (const b of document.querySelectorAll("#topbar i")) {
    const r = b.getBoundingClientRect();
    rects.push({ name: "RobloxButton", r: { left: r.left, top: r.top, right: r.right, bottom: r.bottom } });
  }
  // Roblox's own UI the HUD must keep clear of (approximate footprints, in screen px):
  //   the chat window, moved to the bottom-left and shrunk (UIController.placeChat), and on touch
  //   screens the thumbstick (bottom-left) and jump button (bottom-right).
  // Chat is configured bottom-left; it's also checked top-left (Roblox's default) in case the
  // new top bar keeps it there.
  const robloxUi = [
    ["Chat", 8, H - 8 - Math.min(190, H * 0.42), 8 + Math.min(215, W * 0.3), H - 8],
    ["ChatTop", 0, 46, Math.min(230, W * 0.3), Math.min(220, H * 0.45)],
  ];
  if (touch) {
    robloxUi.push(["Thumbstick", 30, H - 160, 160, H - 30]);
    robloxUi.push(["JumpButton", W - 120, H - 120, W - 20, H - 20]);
  }
  for (const [name, left, top, right, bottom] of robloxUi) rects.push({ name: "Roblox" + name, r: { left, top, right, bottom } });
  for (let i = 0; i < rects.length; i++) {
    const a = rects[i];
    if (!a.name.startsWith("Roblox") && (a.r.left < 0 || a.r.top < 0 || a.r.right > W || a.r.bottom > H)) {
      problems.push(\`\${a.name} goes off screen\`);
    }
    for (let j = i + 1; j < rects.length; j++) {
      const b = rects[j];
      if (a.name.startsWith("Roblox") && b.name.startsWith("Roblox")) continue;
      const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
      const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      if (w > 0.5 && h > 0.5) problems.push(\`\${a.name} overlaps \${b.name} (\${w.toFixed(0)}x\${h.toFixed(0)}px)\`);
    }
  }
  return problems;
};
</script></body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on("pageerror", (e) => console.error("page error:", e.message));
await page.setContent(html);
const count = await page.evaluate(() => window.sceneCount);
// Scenes named "name@WxH" were exported for one screen size: render only at that size, saved
// as name-<label>.png.
const sceneNames = await page.evaluate(() => data.scenes.map((s) => s.name));
for (let i = 0; i < count; i++) {
  const sized = /^(.*)@(\d+)x(\d+)$/.exec(sceneNames[i]);
  for (const [label, W, H] of sizes) {
    if (sized && (+sized[2] !== W || +sized[3] !== H)) continue;
    await page.setViewportSize({ width: W, height: H });
    let name = await page.evaluate(([i, W, H]) => window.render(i, W, H), [i, W, H]);
    if (sized) name = sized[1];
    const file = path.join(outDir, `${name}-${label}.png`);
    if (process.env.DEBUG_NAME) console.log(await page.evaluate((n) => { const e = document.querySelector(`[title="${n}"]`); if (!e) return "missing"; const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); return JSON.stringify({ r, bg: cs.backgroundColor, z: cs.zIndex, disp: cs.display }); }, process.env.DEBUG_NAME));
    await page.screenshot({ path: file });
    console.log("wrote", file);
  }
}
// Overlap check on every HUD state (hub, plot) at every screen size.
let issues = 0, checked = 0;
const hudScenes = await page.evaluate(() => data.scenes.map((s, i) => [s.name, i]).filter(([n]) => n.startsWith("hud")));
for (const [sceneName, hudIndex] of hudScenes) {
  const sized = /@(\d+)x(\d+)$/.exec(sceneName);
  for (const [label, W, H] of [...sizes, ...checkSizes]) {
    if (sized && (+sized[1] !== W || +sized[2] !== H)) continue;
    checked++;
    await page.setViewportSize({ width: W, height: H });
    await page.evaluate(([i, W, H]) => window.render(i, W, H), [hudIndex, W, H]);
    const problems = await page.evaluate(([W, H, t]) => window.checkOverlaps(W, H, t), [W, H, sceneName.split("@")[0].endsWith("touch")]);
    for (const p of problems) console.log(`[overlap] ${sceneName} ${label} ${W}x${H}: ${p}`);
    issues += problems.length;
  }
}
console.log(`HUD overlap check: ${issues} issue(s) across ${checked} state x screen-size combinations`);
await browser.close();
