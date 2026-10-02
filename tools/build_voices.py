#!/usr/bin/env python3
"""Pre-record every spoken line of the game with offline neural TTS, one voice per character.

Lines are collected from the game scripts (hud.radio calls, mission dialogue), each character
is mapped to a voice (model + pitch + pace), and the result is written to assets/voice/<md5>.ogg
where md5 = md5("<speaker>|<raw text>") — the same key the game computes at run time.

Needs: sherpa-onnx, piper-phonemize, soundfile, numpy + the Piper Arabic voices (see VLIB).
Run from the repo root:  python3 tools/build_voices.py <dir with vlib.py and the voice models>
"""
import sys, os, re, json, hashlib, itertools
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VDIR = sys.argv[1]
sys.path.insert(0, VDIR)
os.chdir(VDIR)
import vlib, numpy as np, soundfile as sf

COLONEL = "العقيد سامر الخطيب"
NEGOTIATOR = "المفاوِضة الرائد ليلى"
TEAM = ["الصقر ٢", "الصقر ٣", "الصقر ٤", "الصقر ٥"]
PLAYER = "الصقر ١"
missions = json.load(open(os.path.join(VDIR, "missions.json")))
LEADERS = sorted({m["leader"] for m in missions if m["leader"]})

# speaker -> (voice model, pitch shift in semitones, pace)
CAST = {
    # men: the clearest Arabic voice (Kareem), re-pitched so every character has his own size and age
    COLONEL: ("kareem", -2.7, 0.96), "قائد العمليات": ("kareem", -2.7, 1.0),
    PLAYER: ("kareem", 0.0, 1.06),
    "الصقر ٢": ("kareem", 1.8, 1.1), "الصقر ٣": ("kareem", 3.3, 1.1),
    "الصقر ٤": ("kareem", 4.8, 1.12), "الصقر ٥": ("kareem", -1.3, 1.12),
    "فريق المراقبة": ("kareem", 1.0, 1.08), "القنّاص": ("kareem", 2.6, 1.05), "الفريق الأرضي": ("kareem", -0.7, 1.1),
    "المسعف": ("kareem", 4.2, 1.05), "مسلّح": ("kareem", -4.5, 1.02),
    "مواطن": ("kareem", 2.6, 0.98), "رهينة": ("kareem", 5.8, 1.08),
    # women: the Dii voice
    NEGOTIATOR: ("SA_dii", 0.0, 1.0), "غرفة العمليات": ("SA_dii", -2.5, 1.05),
    "نشرة الأخبار": ("SA_dii", 1.5, 1.05), "المراسلة": ("SA_dii", 2.5, 1.1),
}
for l in LEADERS:
    CAST[l] = ("kareem", -4.5, 1.0)

NUM = {0: "صفر", 1: "واحد", 2: "اثنين", 3: "ثلاثة", 4: "أربعة", 5: "خمسة", 6: "ستة", 7: "سبعة", 8: "ثمانية", 9: "تسعة", 10: "عشرة"}
def speakable(t):
    t = re.sub(r"\[[^\]]*\]", "", t)
    for a, b in [("١", " واحد"), ("٢", " اثنين"), ("٣", " ثلاثة"), ("٤", " أربعة"), ("٥", " خمسة"), ("«", ""), ("»", ""), ("…", "، "), ("—", "، "), ("–", "، ")]:
        t = t.replace(a, b)
    t = re.sub(r"\d+", lambda m: NUM.get(int(m.group()), m.group()), t)
    t = re.sub("[ًٌٍَُِّْ]", "", t)          # the diacritiser re-adds vowels consistently
    return re.sub(r"\s+", " ", t).strip()

lines = set()      # (speaker, raw text)
def add(who, text):
    if who in CAST and text.strip():
        lines.add((who, text))

# ---- mission data
for m in missions:
    hcount = sum(r.count("H") for r in m["map"]); ecount = sum(r.count("V") for r in m["map"])
    add("نشرة الأخبار", m["news_line"])
    add("فريق المراقبة" if m["id"] == "raid" else NEGOTIATOR, m["negotiator_line"])
    add(COLONEL, m["commander_line"])
    add("غرفة العمليات", "نداء عاجل لوحدة الصقر: %s. تحرّكوا فوراً!" % m["news"])
    add("غرفة العمليات", "إلى الصقر ١: الطريق إلى %s مفتوح، الدوريات سكّرت الشوارع الفرعية." % m["area"])
    for b in m["brief"]:
        add(COLONEL, b)
    for who, text in m["banter"]:
        add(who, text)
    names = {"C": COLONEL, "P": PLAYER, "N": NEGOTIATOR, "T": "الصقر ٢"}
    for n in m["enemies"]:
        for d in m["dialogue"]:
            add(names[d[0]], d[1].replace("{n}", str(n)).replace("{h}", str(hcount)).replace("{e}", str(ecount)).replace("{leader}", m["leader"]))

# ---- hud.radio(...) calls in the scripts
def split_args(s):
    out, depth, cur, q = [], 0, "", None
    for ch in s:
        if q:
            cur += ch
            if ch == q: q = None
            continue
        if ch == '"': q = ch; cur += ch; continue
        if ch in "([{": depth += 1
        if ch in ")]}": depth -= 1
        if ch == "," and depth == 0: out.append(cur); cur = ""; continue
        cur += ch
    out.append(cur)
    return [a.strip() for a in out]
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
def who_candidates(expr):
    c = LIT.findall(expr)
    if "COLONEL" in expr: c.append(COLONEL)
    if "NEGOTIATOR" in expr: c.append(NEGOTIATOR)
    if re.search(r"\bLEADER\b", expr): c += LEADERS
    if "display_name" in expr: c += TEAM
    if expr.strip() == "who": c += [PLAYER] + TEAM
    return c
def expand(text, tail):
    if "%" not in text: return [text]
    if "M.news" in tail: vals = [m["news"] for m in missions]
    elif "M.area" in tail: vals = [m["area"] for m in missions]
    elif "enemies.size" in tail: vals = list(range(3, 10))
    elif "flashbangs" in tail: vals = [3]
    elif "LEADER" in tail: vals = LEADERS
    elif "display_name" in tail: vals = TEAM
    else: return []
    return [text % v for v in vals]
consts = {}
for fn in ["main.gd", "vehicle.gd", "actor.gd", "hud.gd"]:
    src = open(os.path.join(ROOT, "scripts", fn), encoding="utf-8").read()
    for name, body in re.findall(r"^const (\w+) := \[(.*)\]\s*$", src, re.M):
        consts[name] = LIT.findall(body)
    for ln in src.split("\n"):
        m = re.search(r"hud\.radio\((.*)\)\s*$", ln)
        if not m: continue
        args = split_args(m.group(1))
        if len(args) < 2: continue
        whos = who_candidates(args[0])
        for lm in LIT.finditer(args[1]):
            tail = args[1][lm.end():lm.end() + 40]
            tail = tail if tail.lstrip().startswith("%") else ""
            for t in expand(lm.group(1), tail) if "%" in lm.group(1) else [lm.group(1)]:
                for w in whos:
                    add(w, t)
for name, who in [("ENEMY_ALERT", "مسلّح"), ("ENEMY_SURRENDER", "مسلّح"), ("HOSTAGE_THANKS", "رهينة"), ("CROWD_LINES", "مواطن"), ("PED_LINES", "مواطن"), ("PLAYER_REPLIES", PLAYER), ("REPORTER_LINES", "المراسلة")]:
    for t in consts.get(name, []):
        add(who, t)

out_dir = os.path.join(ROOT, "assets", "voice")
os.makedirs(out_dir, exist_ok=True)
wanted = set()
index = {}
total = 0.0
for who, text in sorted(lines):
    key = hashlib.md5((who + "|" + text).encode("utf-8")).hexdigest()
    wanted.add(key + ".ogg")
    index[key] = [who, text]
    path = os.path.join(out_dir, key + ".ogg")
    if os.path.exists(path):
        continue
    model, st, pace = CAST[who]
    x, sr = vlib.synth(speakable(text), model, st, pace)
    sf.write(path, x, sr, format="OGG", subtype="VORBIS")
    total += len(x) / sr
for f in os.listdir(out_dir):
    if f.endswith(".ogg") and f not in wanted:
        os.remove(os.path.join(out_dir, f))
        if os.path.exists(os.path.join(out_dir, f + ".import")): os.remove(os.path.join(out_dir, f + ".import"))
json.dump(index, open(os.path.join(VDIR, "voice_index.json"), "w"), ensure_ascii=False, indent=0)
print("lines:", len(lines), "new audio: %.0f s" % total)
