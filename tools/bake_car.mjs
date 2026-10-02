// Bake every material of a car into vertex colours so the whole car becomes 1–2 draw calls.
// alpha channel of COLOR_0: 0.5 = body paint (recolourable at runtime), 1.0 = everything else.
import { createRequire } from 'module';
const require = createRequire('/home/claude/.npm-global/lib/node_modules/@gltf-transform/cli/');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { flatten, join, weld, simplify, prune, dedup, normals } = require('@gltf-transform/functions');
const { MeshoptSimplifier } = require('meshoptimizer');
const sharp = require('sharp');

const [,, input, output, ratioArg, keepPaint] = process.argv;
const ratio = parseFloat(ratioArg || '0.5');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const s2l = (c) => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);

const texCache = new Map();
async function decode(tex) {
  if (!tex) return null;
  if (texCache.has(tex)) return texCache.get(tex);
  const { data, info } = await sharp(Buffer.from(tex.getImage())).resize(256, 256, { fit: 'fill' }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const r = { data, w: info.width, h: info.height };
  texCache.set(tex, r);
  return r;
}

// material stats: area + mean colour, to find the body paint
const stats = new Map();
const jobs = [];
for (const mesh of root.listMeshes()) for (const prim of mesh.listPrimitives()) jobs.push(prim);
for (const prim of jobs) {
  const mat = prim.getMaterial();
  const pos = prim.getAttribute('POSITION');
  const uv = prim.getAttribute('TEXCOORD_0');
  const n = pos.getCount();
  const f = mat ? mat.getBaseColorFactor() : [0.8, 0.8, 0.8, 1];
  const img = mat ? await decode(mat.getBaseColorTexture()) : null;
  const ti = mat ? mat.getBaseColorTextureInfo() : null;
  const tt = ti ? ti.getExtension('KHR_texture_transform') : null;
  const tOff = tt ? tt.getOffset() : [0, 0], tSc = tt ? tt.getScale() : [1, 1], tRot = tt ? tt.getRotation() : 0;
  let asum = 0;
  const col = new Float32Array(n * 4);
  let mr = 0, mg = 0, mb = 0;
  const tmp = [0, 0];
  for (let i = 0; i < n; i++) {
    let r = f[0], g = f[1], b = f[2];
    if (img && uv) {
      uv.getElement(i, tmp);
      let su = tmp[0] * tSc[0], sv = tmp[1] * tSc[1];
      const cr = Math.cos(tRot), sr = Math.sin(tRot);
      let u = cr * su + sr * sv + tOff[0], v = -sr * su + cr * sv + tOff[1];
      u -= Math.floor(u); v -= Math.floor(v);
      asum += img.data[(Math.min(img.h - 1, Math.floor(v * img.h)) * img.w + Math.min(img.w - 1, Math.floor(u * img.w))) * 4 + 3] / 255;
      const x = Math.min(img.w - 1, Math.floor(u * img.w)), y = Math.min(img.h - 1, Math.floor(v * img.h));
      const o = (y * img.w + x) * 4;
      r *= s2l(img.data[o] / 255); g *= s2l(img.data[o + 1] / 255); b *= s2l(img.data[o + 2] / 255);
    }
    col[i * 4] = r; col[i * 4 + 1] = g; col[i * 4 + 2] = b; col[i * 4 + 3] = 1;
    mr += r; mg += g; mb += b;
  }
  const name = (mat ? mat.getName() : '').toLowerCase();
  const glass = !!mat && /glass|window|vidrio|crist|windshield/.test(name) && !/light|lamp|head|tail/.test(name);
  // see-through decals / shadow cards (blend mode with very low alpha) are dropped entirely
  const alpha = (mat ? f[3] : 1) * (img && uv ? asum / n : 1);
  prim._drop = !!mat && mat.getAlphaMode() === 'BLEND' && !glass && alpha < 0.45;
  prim._col = col; prim._glass = glass; prim._name = name;
  const key = mat || 'none';
  const st = stats.get(key) || { n: 0, r: 0, g: 0, b: 0, glass };
  st.n += n; st.r += mr; st.g += mg; st.b += mb;
  stats.set(key, st);
}
// body paint = every vertex whose hue matches the car's dominant saturated hue (any brightness)
const hueOf = (r, g, b) => { const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; if (d < 1e-5) return -1; let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; return (h * 60 + 360) % 360; };
const hh = new Float64Array(36);
for (const prim of jobs) {
  if (prim._glass || prim._drop) continue;
  const c = prim._col;
  for (let i = 0; i < c.length; i += 4) {
    const mx = Math.max(c[i], c[i + 1], c[i + 2]), mn = Math.min(c[i], c[i + 1], c[i + 2]);
    if (mx < 0.03 || (mx - mn) / mx < 0.5) continue;
    hh[Math.floor(hueOf(c[i], c[i + 1], c[i + 2]) / 10) % 36] += 1;
  }
}
let hb = 0; for (let i = 1; i < 36; i++) if (hh[i] > hh[hb]) hb = i;
const paintHue = hb * 10 + 5;
const paintMean = [0, 0, 0]; let pmn = 0;
for (const prim of jobs) {
  if (prim._glass || prim._drop) continue;
  const c = prim._col;
  for (let i = 0; i < c.length; i += 4) {
    const mx = Math.max(c[i], c[i + 1], c[i + 2]), mn = Math.min(c[i], c[i + 1], c[i + 2]);
    if (mx < 0.03 || (mx - mn) / mx < 0.5) continue;
    let dh = Math.abs(hueOf(c[i], c[i + 1], c[i + 2]) - paintHue); if (dh > 180) dh = 360 - dh;
    if (dh < 28) { paintMean[0] += c[i]; paintMean[1] += c[i + 1]; paintMean[2] += c[i + 2]; pmn++; }
  }
}
for (let k = 0; k < 3; k++) paintMean[k] /= Math.max(pmn, 1);
console.log('paint hue', paintHue, 'verts', hh[hb], 'mean', paintMean.map((x) => x.toFixed(2)).join(' '));
const body = doc.createMaterial('body').setBaseColorFactor([1, 1, 1, 1]).setMetallicFactor(0.12).setRoughnessFactor(0.32);
const glassM = doc.createMaterial('glass').setBaseColorFactor([0.03, 0.035, 0.045, 1]).setMetallicFactor(0.9).setRoughnessFactor(0.08);
for (const prim of jobs) {
  if (prim._drop) { prim.detach ? prim.dispose() : prim.dispose(); continue; }
  const col = prim._col;
  const pname = prim._name || '';
  if (keepPaint !== 'nopaint' && !prim._glass) for (let i = 0; i < col.length; i += 4) {
    if (/carbon/.test(pname)) {            // carbon bonnet / roof panels are painted like the rest of the body
      col[i] = paintMean[0]; col[i + 1] = paintMean[1]; col[i + 2] = paintMean[2]; col[i + 3] = 0.5; continue;
    }
    const mx = Math.max(col[i], col[i + 1], col[i + 2]), mn = Math.min(col[i], col[i + 1], col[i + 2]);
    if (mx < 0.03 || (mx - mn) / mx < 0.5) continue;
    let dh = Math.abs(hueOf(col[i], col[i + 1], col[i + 2]) - paintHue); if (dh > 180) dh = 360 - dh;
    if (dh < 28) col[i + 3] = 0.5;
  }
  const acc = doc.createAccessor().setType('VEC4').setArray(col).setBuffer(root.listBuffers()[0]);
  for (const sem of prim.listSemantics()) if (sem !== 'POSITION' && !(ratio >= 0.999 && sem === 'NORMAL')) prim.setAttribute(sem, null);
  prim.setAttribute('COLOR_0', acc);
  prim.setMaterial(prim._glass ? glassM : body);
}
if (ratio >= 0.999) {
  // full detail: keep the artist's normals (smooth panels, crisp creases); Godot builds the distance LODs
  await doc.transform(dedup(), flatten(), join({ keepNamed: false }), weld(), prune());
} else {
  await doc.transform(dedup(), flatten(), join({ keepNamed: false }), weld(), simplify({ simplifier: MeshoptSimplifier, ratio, error: parseFloat(process.argv[6] || "0.02"), lockBorder: false }), normals({ overwrite: true }), prune());
}
let tris = 0, prims = 0;
for (const mesh of root.listMeshes()) for (const prim of mesh.listPrimitives()) { prims++; tris += (prim.getIndices() ? prim.getIndices().getCount() : prim.getAttribute('POSITION').getCount()) / 3; }
console.log('prims', prims, 'tris', tris);
await io.write(output, doc);
