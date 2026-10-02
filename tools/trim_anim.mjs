// Keep only the named clips of a Mesh2Motion (CC0) animation file; everything else is pruned.
import { createRequire } from 'module';
const require = createRequire('/home/claude/.npm-global/lib/node_modules/@gltf-transform/cli/');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { prune, dedup, resample, simplify, weld } = require('@gltf-transform/functions');
const { MeshoptSimplifier } = require('meshoptimizer');
const [,, input, output, ...keep] = process.argv;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
for (const a of doc.getRoot().listAnimations()) if (!keep.includes(a.getName())) { for (const ch of a.listChannels()) ch.dispose(); for (const sm of a.listSamplers()) sm.dispose(); a.dispose(); }
const joints = new Set(['root','pelvis','spine_01','spine_02','spine_03','neck_01','head','clavicle_l','upperarm_l','lowerarm_l','hand_l','clavicle_r','upperarm_r','lowerarm_r','hand_r','thigh_l','calf_l','foot_l','ball_l','thigh_r','calf_r','foot_r','ball_r']);
for (const a of doc.getRoot().listAnimations()) for (const ch of a.listChannels()) {
  const n = ch.getTargetNode(); const path = ch.getTargetPath();
  const ok = n && joints.has(n.getName()) && (path === 'rotation' || (path === 'translation' && (n.getName() === 'pelvis' || n.getName() === 'root')));
  if (!ok) { const sm = ch.getSampler(); ch.dispose(); if (sm) sm.dispose(); }
}
for (const t of doc.getRoot().listTextures()) t.dispose();
await doc.transform(resample(), weld(), simplify({ simplifier: MeshoptSimplifier, ratio: 0.05, error: 0.05 }), dedup(), prune());
console.log(output, doc.getRoot().listAnimations().map((a) => a.getName()).join(', '));
await io.write(output, doc);
