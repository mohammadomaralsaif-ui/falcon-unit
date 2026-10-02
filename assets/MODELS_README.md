# إضافة موديلات حقيقية (سيارات وشخصيات)

اللعبة بتستخدم أي موديل بتحطه بهدول المجلدين تلقائياً، بدون تعديل كود:

## السيارات → `assets/cars/`
سمِّ الملف بأوله نوع السيارة:

| أول اسم الملف | وين بتطلع باللعبة |
|---|---|
| `taxi` | التكاسي الصفرا بالشوارع |
| `sedan` | سيارات الناس بالشوارع والمصفوفة (فيك تحط أكثر من وحدة: `sedan_elantra.glb`, `sedan_corolla.glb`) |
| `police` | سيارات الشرطة عند الطوق |
| `swat` | سيارتك (سيارة الوحدة) |
| `ambulance` | الإسعاف |
| `cashvan` | فان الأموال اللي بيهرب فيه أبو جاسر |

- الصيغة: `.glb` (الأفضل) أو `.gltf` أو `.fbx`
- **بدون ضغط Draco** (إذا الموقع بيسأل "Draco compression" اختار لا)
- حجم الملف يفضّل أقل من 10 ميغا
- اللعبة بتكبّر/بتصغّر السيارة لحالها وبتحطها على الأرض. إذا طلعت السيارة معكوسة، اكتب بملف `assets/cars/setup.json`:
  `{"taxi_elantra.glb": {"rotate": 180}}`

## الشخصيات → `assets/characters/`
لازم تكون **مركّبة على هيكل Mixamo** (أي شخصية من mixamo.com بتزبط). سمِّ الملف بأوله الدور:
`swat`, `robber`, `hostage`, `civilian`, `officer` — مثلاً `swat_1.fbx`, `robber_hoodie.fbx`, `civilian_woman.fbx`

- من Mixamo: اختار الشخصية ← Download ← Format: FBX ← Pose: T-Pose ← بدون أنيميشن
- اللعبة بتعطيها مشي/ركض/حمل سلاح لحالها، وبتظبط طولها


## Animations and extra props (CC0)

- `assets/models/anim_base.glb`, `assets/models/anim_addon.glb` — crouch, strafes, walking backwards, hit
  reactions, deaths and the grenade throw. Trimmed (tools/trim_anim.mjs) from the Mesh2Motion animation
  library (https://github.com/Mesh2Motion/mesh2motion-app), which is CC0 1.0 — see `assets/models/ANIM_LICENSE-CC0.md`.
  They are retargeted at load time onto every character by `scripts/retarget.gd`.
- `assets/weapons/shotgun.glb` — CC0 prop from the same repository.
