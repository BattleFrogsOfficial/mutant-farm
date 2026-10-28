// Renders build/scene.json (from export.luau) to PNG screenshots with three.js in headless Chromium.
//   node tools/preview/render.mjs build/scene.json build/shots
// Approximates Roblox: flat-shaded primitives, neon = emissive, a sun and sky ambient. No textures.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const { chromium } = createRequire(import.meta.url)("playwright");
const [scenePath, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const scene = fs.readFileSync(scenePath, "utf8");
const three = fs.readFileSync(path.join(here, "node_modules/three/build/three.module.min.js"), "utf8");

// Camera shots: [name, eye, target, fov]
const shots = JSON.parse(process.env.SHOTS || "null") || [
  ["overview", [0, 260, 210], [0, 0, 0], 50],
  ["plot", [104 - 34, 22, 0], [104 + 4, 0, 0], 60],
  ["plot-close", [104 - 20, 9, 6], [104 + 6, 1, 0], 55],
  ["hub", [0, 30, 58], [0, 4, 0], 55],
  ["edge", [120, 14, 60], [180, 4, 90], 60],
];

const html = `<!doctype html><html><body style="margin:0;background:#000">
<script type="module">
const blob = new Blob([${JSON.stringify(three)}], {type: "text/javascript"});
const THREE = await import(URL.createObjectURL(blob));
const data = ${scene};
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(1280, 720);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);
const s = new THREE.Scene();
s.background = new THREE.Color("#cfe6ff");
s.fog = new THREE.Fog("#fff4d6", 220, 700);
s.add(new THREE.HemisphereLight("#ffffff", "#7a6a90", 1.6));
const sun = new THREE.DirectionalLight("#fff6e0", 2.4);
sun.position.set(120, 260, 80);
sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
Object.assign(sun.shadow.camera, { left: -220, right: 220, top: 220, bottom: -220, near: 1, far: 800 });
s.add(sun);

function wedgeGeom() {
  // Roblox WedgePart: high edge at +Z (back), slope faces -Z and up. Unit size.
  const g = new THREE.BufferGeometry();
  const v = [];
  const P = (x, y, z) => [x - 0.5, y - 0.5, z - 0.5];
  const A = P(0,0,0), B = P(0,0,1), C = P(0,1,1), D = P(1,0,0), E = P(1,0,1), F = P(1,1,1);
  const tri = (a,b,c) => v.push(...a,...b,...c);
  tri(A,C,B); tri(D,E,F);            // sides
  tri(A,B,E); tri(A,E,D);            // bottom
  tri(B,C,F); tri(B,F,E);            // back
  tri(A,D,F); tri(A,F,C);            // slope
  g.setAttribute("position", new THREE.Float32BufferAttribute(v, 3));
  g.computeVertexNormals();
  return g;
}
const geoms = {
  Block: new THREE.BoxGeometry(1, 1, 1),
  Ball: new THREE.SphereGeometry(0.5, 24, 16),
  Ellipsoid: new THREE.SphereGeometry(0.5, 24, 16),
  Cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 24).rotateZ(Math.PI / 2),
  Wedge: wedgeGeom(),
  CornerWedge: wedgeGeom(),
};
for (const p of data.parts) {
  const geom = geoms[p.kind] || geoms.Block;
  const neon = p.material === "Neon";
  const mat = new THREE.MeshStandardMaterial({
    color: p.color,
    roughness: p.material === "Foil" || p.material === "Metal" ? 0.3 : 0.85,
    metalness: p.material === "Foil" ? 0.6 : p.material === "Metal" ? 0.4 : 0,
    emissive: neon ? p.color : "#000000",
    emissiveIntensity: neon ? 0.9 : 0,
    transparent: p.transparency > 0,
    opacity: 1 - p.transparency,
    flatShading: p.kind === "Block" || p.kind === "Wedge",
  });
  const m = new THREE.Mesh(geom, mat);
  let [sx, sy, sz] = p.size;
  if (p.kind === "Ball") { const d = Math.min(sx, sy, sz); sx = sy = sz = d; }
  if (p.kind === "Cylinder") { const d = Math.min(sy, sz); sy = sz = d; }
  const c = p.cf;
  const mat4 = new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
  mat4.multiply(new THREE.Matrix4().makeScale(sx, sy, sz));
  m.matrixAutoUpdate = false;
  m.matrix.copy(mat4);
  m.castShadow = p.transparency < 0.5 && !neon;
  m.receiveShadow = true;
  s.add(m);
}
const camera = new THREE.PerspectiveCamera(60, 1280 / 720, 0.5, 2000);
window.shoot = (eye, target, fov) => {
  camera.fov = fov; camera.updateProjectionMatrix();
  camera.position.set(...eye); camera.lookAt(...target);
  renderer.render(s, camera);
  return renderer.domElement.toDataURL("image/png");
};
window.ready = true;
</script></body></html>`;

const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on("console", (m) => m.type() === "error" && console.error(m.text()));
page.on("pageerror", (e) => console.error(e));
await page.setContent(html);
await page.waitForFunction(() => window.ready === true, null, { timeout: 120000 });
for (const [name, eye, target, fov] of shots) {
  const url = await page.evaluate(([e, t, f]) => window.shoot(e, t, f), [eye, target, fov]);
  fs.writeFileSync(path.join(outDir, name + ".png"), Buffer.from(url.split(",")[1], "base64"));
  console.log("wrote", name);
}
await browser.close();
