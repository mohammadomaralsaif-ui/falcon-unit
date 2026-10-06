#!/usr/bin/env python3
"""Pre-record every spoken line of the game with offline neural TTS, one voice per character.

Lines are collected from the story (assets/story.json: Arabic subtitle + the English that is spoken)
and from the game scripts (hud.radio calls, with their English in tools/voice_en.json); each character
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
EN = json.load(open(os.path.join(ROOT, "tools", "voice_en.json"), encoding="utf-8"))   # Arabic template -> English line
EN_NAMES = {"أبو جاسر": "Abu Jasser", "الخال": "Al-Khal", "جبل عمّان": "Jabal Amman", "جبل الحسين": "Jabal Al-Hussein",
            "عبدون": "Abdoun", "ماركا": "Marka", "الذيب": "Al-Theeb", "العقرب": "the Scorpion", "الرائد نضال": "Nidal", "الشميساني": "Shmeisani", "طبربور": "Tabarbour", "دير غبار": "Deir Ghbar", "الصقر ٢": "Falcon Two", "الصقر ٣": "Falcon Three", "الصقر ٤": "Falcon Four", "الصقر ٥": "Falcon Five"}

# The game speaks English (clear, natural neural voices) with Arabic subtitles on screen.
# speaker -> (Piper voice, pitch shift in semitones, pace)
CAST = {
    COLONEL: ("en_GB-alan-medium", 0.0, 1.0),
    PLAYER: ("en_US-ryan-high", 0.0, 1.0),
    "الصقر ٢": ("en_US-joe-medium", 0.0, 1.05), "الصقر ٣": ("en_US-bryce-medium", 0.0, 1.3),
    "الصقر ٤": ("en_US-john-medium", 0.0, 1.15), "الصقر ٥": ("en_US-kusal-medium", 0.0, 1.05),
    "فريق المراقبة": ("en_US-hfc_male-medium", 0.0, 1.05), "القنّاص": ("en_US-hfc_male-medium", -1.0, 1.1),
    "الفريق الأرضي": ("en_US-kusal-medium", 0.0, 1.05),
    "المسعف": ("en_US-sam-medium", 0.0, 1.1), "مسلّح": ("en_US-reza_ibrahim-medium", -1.5, 1.1),
    "مواطن": ("en_US-danny-low", 0.0, 1.0), "رهينة": ("en_US-sam-medium", 2.0, 1.1),
    NEGOTIATOR: ("en_US-lessac-high", 0.0, 1.0), "غرفة العمليات": ("en_US-amy-medium", 0.0, 1.15),
    "نشرة الأخبار": ("en_US-kristin-medium", 0.0, 1.05), "المراسلة": ("en_US-hfc_female-medium", 0.0, 1.05),
    # the brigadier: older, heavier, unhurried
    "العميد منصور": ("en_US-norman-medium", -1.0, 0.95),
    # the man on the hacked channel — one voice under three names as the story finds out who he is
    "صوت مجهول": ("en_GB-northern_english_male-medium", -2.0, 0.92),
    "العقرب": ("en_GB-northern_english_male-medium", -2.0, 0.92),
    "الرائد نضال": ("en_GB-northern_english_male-medium", -2.0, 0.92),
    # the accountant: thin, fast, frightened
    "فارس": ("en_US-hfc_male-medium", 2.0, 1.12),
    # the hired leaders
    "أبو جاسر": ("en_US-reza_ibrahim-medium", -1.5, 1.05), "الخال": ("en_US-reza_ibrahim-medium", -3.5, 0.95),
    "الذيب": ("en_US-reza_ibrahim-medium", 0.5, 1.15),
}

NUM = {0: "صفر", 1: "واحد", 2: "اثنين", 3: "ثلاثة", 4: "أربعة", 5: "خمسة", 6: "ستة", 7: "سبعة", 8: "ثمانية", 9: "تسعة", 10: "عشرة"}
def speakable(t):
    t = re.sub(r"\[[^\]]*\]", "", t)
    for a, b in [("١", " واحد"), ("٢", " اثنين"), ("٣", " ثلاثة"), ("٤", " أربعة"), ("٥", " خمسة"), ("«", ""), ("»", ""), ("…", "، "), ("—", "، "), ("–", "، ")]:
        t = t.replace(a, b)
    t = re.sub(r"\d+", lambda m: NUM.get(int(m.group()), m.group()), t)
    t = re.sub("[ًٌٍَُِّْ]", "", t)          # the diacritiser re-adds vowels consistently
    return re.sub(r"\s+", " ", t).strip()

lines = {}         # (speaker, raw Arabic text shown as subtitle) -> English line that is spoken
def add(who, text, en):
    if who in CAST and text.strip() and re.search("[\u0600-\u06FF]", text):
        lines[(who, text)] = re.sub(r"\[[^\]]*\]", "", en)
def en_of(template):
    if template not in EN:
        raise SystemExit("no English line for: " + template)
    return EN[template]

# ---- the story (assets/story.json): every line carries its own English, per mission
STORY = json.load(open(os.path.join(ROOT, "assets", "story.json"), encoding="utf-8"))
CODES = STORY["cast"]
for m in missions:
    st = STORY["missions"].get(m["id"], {})
    hcount = sum(r.count("H") for r in m["map"]); ecount = sum(r.count("V") for r in m["map"])
    def who(code, m=m):
        w = CODES[code]
        return m["leader"] if w == "@leader" else w
    for l in st.get("intro", []):
        add(who(l[1]), l[2], l[3])
    flat = list(st.get("banter", [])) + list(st.get("outro", [])) + list(st.get("confront", []))
    for ls in st.get("beats", {}).values(): flat += ls
    flat += st.get("chase", {}).get("lines", []) + st.get("chase", {}).get("stop", [])
    for e in st.get("endings", {}).values(): flat += e["lines"]
    for l in flat:
        add(who(l[0]), l[1], l[2])
    # the briefing at the cordon counts gunmen / hostages / files, which change with the difficulty
    for n in m["enemies"]:
        for d in st.get("dialogue", []):
            def fill(t, leader):
                return t.replace("{n}", str(n)).replace("{h}", str(hcount)).replace("{e}", str(ecount)).replace("{leader}", leader)
            add(who(d[0]), fill(d[1], m["leader"]), fill(d[2], EN_NAMES.get(m["leader"], "")))

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
    """All (Arabic, English) versions of a line that has a %s / %d in it."""
    en = en_of(text)
    if "%" not in text:
        return [(text, en)]
    if "M.news" in tail: vals = [(m["news"], en_of(m["news"])) for m in missions]
    elif "M.area" in tail: vals = [(m["area"], EN_NAMES[m["area"]]) for m in missions]
    elif "enemies.size" in tail: vals = [(v, v) for v in range(3, 11)]
    elif "flashbangs" in tail: vals = [(3, 3)]
    elif "smokes" in tail: vals = [(3, 3)]
    elif "LEADER" in tail: vals = [(l, EN_NAMES[l]) for l in LEADERS]
    elif "display_name" in tail: vals = [(t, EN_NAMES[t]) for t in TEAM]
    else: return []
    return [(text % a, en % e) for a, e in vals]
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
            if not re.search("[\u0600-\u06FF]", lm.group(1)):
                continue
            for t, e in expand(lm.group(1), tail):
                for w in whos:
                    add(w, t, e)
for name, who in [("ENEMY_ALERT", "مسلّح"), ("ENEMY_SURRENDER", "مسلّح"), ("HOSTAGE_THANKS", "رهينة"), ("CROWD_LINES", "مواطن"), ("PED_LINES", "مواطن"), ("PLAYER_REPLIES", PLAYER), ("REPORTER_LINES", "المراسلة")]:
    for t in consts.get(name, []):
        add(who, t, en_of(t))

out_dir = os.path.join(ROOT, "assets", "voice")
os.makedirs(out_dir, exist_ok=True)
wanted = set()
index = {}
total = 0.0
for (who, text), en in sorted(lines.items()):
    key = hashlib.md5((who + "|" + text).encode("utf-8")).hexdigest()
    wanted.add(key + ".ogg")
    index[key] = [who, text, en]
    path = os.path.join(out_dir, key + ".ogg")
    if os.path.exists(path):
        continue
    model, st, pace = CAST[who]
    x, sr = vlib.synth(en, model, st, pace, prepared=True)
    sf.write(path, x, sr, format="OGG", subtype="VORBIS")
    total += len(x) / sr
for f in os.listdir(out_dir):
    if f.endswith(".ogg") and f not in wanted:
        os.remove(os.path.join(out_dir, f))
        if os.path.exists(os.path.join(out_dir, f + ".import")): os.remove(os.path.join(out_dir, f + ".import"))
json.dump(index, open(os.path.join(VDIR, "voice_index.json"), "w"), ensure_ascii=False, indent=0)
print("lines:", len(lines), "new audio: %.0f s" % total)
