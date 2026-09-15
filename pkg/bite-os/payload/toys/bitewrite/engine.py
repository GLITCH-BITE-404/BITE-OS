#!/usr/bin/env python3
"""bitewrite's engine — everything the window cannot do itself.

QML can read and write files but cannot start a process, so this runs beside
it. Two jobs:

  --prep RUNDIR    once, before the window opens: theme + settings into
                   opts.json, the synthesised sound packs (cached), and the
                   code snippets into snippets.json
  --serve RUNDIR   while the window is open: the window writes request.json,
                   we answer in status.json (same shape as bitedig/biteglyph).
                   Songs, lyrics, MPRIS play/pause, saving settings. While a
                   player is being watched its position goes to now.json.
"""

import glob, json, math, os, re, shutil, subprocess, sys, time
import urllib.parse, urllib.request

HOME = os.path.expanduser("~")
E = os.environ.get
CACHE = os.path.join(E("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "bite-os")
LYR_CACHE = os.path.join(CACHE, "lyrics")          # shared with bitebeat
SFX_DIR = os.path.join(CACHE, "bitewrite-sfx", "v1")
SERP_SND = os.path.join(HOME, ".local/share/serpantinum/src/assets/sounds")
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = (".mp3", ".flac", ".ogg", ".m4a", ".opus", ".wav", ".aac")


def load(p):
    try:
        with open(os.path.expanduser(p), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def dump(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def run(cmd, timeout=4):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


# ── sound packs ───────────────────────────────────────────────────────────────
# Synthesised, not sampled: nothing to license, nothing to download, and a
# musical pack can have a different note for every letter. Generated once into
# the cache; delete ~/.cache/bite-os/bitewrite-sfx to regenerate.

SR = 44100
PENTA = [0, 2, 4, 7, 9]                           # major pentatonic


def note(semi, base=523.25):                      # semitones above C5
    return base * 2 ** (semi / 12)


def penta(n, base=523.25):
    return [note(12 * (i // 5) + PENTA[i % 5], base) for i in range(n)]


def synth_packs():
    import numpy as np
    import wave
    rng = np.random.default_rng(404)

    def t(d): return np.arange(int(d * SR)) / SR
    def dec(d, tau): return np.exp(-t(d) / tau)
    def smooth(x, k):
        return np.convolve(x, np.ones(k) / k, mode="same") if k > 1 else x
    def hp(x, k=6): return x - smooth(x, k)
    def pad(x, d):
        out = np.zeros(int(d * SR)); out[:min(len(x), len(out))] += x[:len(out)]
        return out
    def mix(*xs):
        n = max(len(x) for x in xs); out = np.zeros(n)
        for x in xs: out[:len(x)] += x
        return out
    def at(x, sec, total):
        out = np.zeros(int(total * SR)); i = int(sec * SR)
        out[i:i + len(x)] += x[:max(0, len(out) - i)]
        return out
    def square(f, d, duty=0.5):
        return np.where((t(d) * f) % 1 < duty, 1.0, -1.0)

    def save(path, x, gain):
        x = np.asarray(x, dtype=float)
        n = min(len(x), 96)
        if n: x[-n:] *= np.linspace(1, 0, n)            # no click at the end
        peak = np.max(np.abs(x)) or 1
        data = (x / peak * gain * 32000).astype("<i2")
        with wave.open(path, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes(data.tobytes())

    def bell(f, d=0.6, tau=0.22):
        x = (np.sin(2 * np.pi * f * t(d)) + 0.35 * np.sin(2 * np.pi * 2 * f * t(d))
             + 0.12 * np.sin(2 * np.pi * 3.01 * f * t(d))) * dec(d, tau)
        x[:int(0.003 * SR)] *= np.linspace(0, 1, int(0.003 * SR))
        return x

    def arp(fs, gap=0.085, tone=bell):
        parts = [at(tone(f), i * gap, gap * len(fs) + 0.6) for i, f in enumerate(fs)]
        return mix(*parts)

    shared = {
        "error": mix(square(110, 0.13) * dec(0.13, 0.06), square(117, 0.13) * dec(0.13, 0.06)),
        "done": arp([note(0), note(4), note(7), note(12), note(16)], 0.09),
        "run": np.sin(2 * np.pi * np.cumsum(np.linspace(180, 1400, int(0.4 * SR))) / SR)
               * np.linspace(0.2, 1, int(0.4 * SR)) * dec(0.4, 0.3),
    }

    packs = {}

    def tw_key(k):
        n = hp(rng.uniform(-1, 1, int(0.006 * SR)), 3) * dec(0.006, 0.0015)
        body = np.sin(2 * np.pi * (150 + 30 * k) * t(0.03)) * dec(0.03, 0.008) * 0.6
        ret = hp(rng.uniform(-1, 1, int(0.004 * SR)), 3) * dec(0.004, 0.001) * 0.35
        return mix(n, body, at(ret, 0.045 + 0.004 * k, 0.06))
    ratchet = mix(*[at(hp(rng.uniform(-1, 1, 200), 3) * np.linspace(1, 0, 200) * 0.5,
                       0.022 * i, 0.3) for i in range(11)])
    packs["typewriter"] = {
        "label": "typewriter — clack, and a bell on Enter",
        "key": [tw_key(k) for k in range(6)],
        "space": [mix(np.sin(2 * np.pi * 95 * t(0.05)) * dec(0.05, 0.012),
                      hp(rng.uniform(-1, 1, 300), 4) * np.linspace(0.6, 0, 300))],
        "enter": [mix(ratchet, at(bell(2093, 0.9, 0.3), 0.26, 1.2))],
        "back": [tw_key(0)[::-1] * 0.6],
    }

    def thock(f):
        d = 0.06
        fr = f * np.linspace(1.25, 0.9, int(d * SR))
        tone = np.sin(2 * np.pi * np.cumsum(fr) / SR) * dec(d, 0.014)
        n = smooth(rng.uniform(-1, 1, int(0.012 * SR)), 8) * dec(0.012, 0.004) * 1.5
        return mix(tone, n)
    packs["thock"] = {
        "label": "thock — deep mechanical keys",
        "key": [thock(f) for f in (130, 138, 146, 124, 152, 141)],
        "space": [thock(92) * 1.2],
        "enter": [mix(thock(105), at(thock(118), 0.035, 0.1))],
        "back": [thock(170) * 0.7],
    }

    def pop(f):
        d = 0.07
        fr = np.linspace(f, f * 1.9, int(d * SR))
        return np.sin(2 * np.pi * np.cumsum(fr) / SR) * dec(d, 0.018)
    packs["bubble"] = {
        "label": "bubble — every letter a different pop",
        "pitched": True,
        "key": [pop(f) for f in penta(12, 330)],
        "space": [pop(220) * 0.6],
        "enter": [arp([392, 523, 659], 0.05, pop)],
        "back": [pop(260)[::-1] * 0.7],
    }

    packs["musicbox"] = {
        "label": "music box — letters are notes, typing makes melodies",
        "pitched": True,
        "key": [bell(f) for f in penta(15)],
        "space": [bell(note(-12), 0.4, 0.12) * 0.35],
        "enter": [arp([note(0), note(7), note(12)], 0.06)],
        "back": [bell(note(-5), 0.4, 0.1) * 0.5],
    }

    def chip(f):
        d = 0.07
        return square(f, d, 0.25) * np.linspace(1, 0, int(d * SR)) ** 1.5
    packs["chiptune"] = {
        "label": "chiptune — 8-bit blips, a note per letter",
        "pitched": True,
        "key": [chip(f) for f in penta(12, 440)],
        "space": [chip(220) * 0.6],
        "enter": [mix(at(chip(523), 0, 0.2), at(chip(784), 0.06, 0.2), at(chip(1046), 0.12, 0.2))],
        "back": [chip(196)],
    }

    def gl(k):
        d = 0.03 + 0.006 * k
        f = rng.uniform(600, 3200)
        x = square(f, d, 0.5) * 0.5 + rng.uniform(-1, 1, int(d * SR)) * 0.5
        x = np.round(x * 3) / 3                                   # bitcrush
        hold = 1 + k % 4                                          # sample-and-hold
        x = np.repeat(x[::hold], hold)[:int(d * SR)]
        return x * dec(d, d / 2.5)
    burst = np.concatenate([square(f, 0.022, 0.5) for f in rng.uniform(300, 2600, 12)])
    packs["glitch"] = {
        "label": "glitch — bitcrushed chirps, dedsec style",
        "key": [gl(k) for k in range(8)],
        "space": [gl(9) * 0.6],
        "enter": [np.round(burst * 2) / 2 * np.linspace(1, 0.2, len(burst))],
        "back": [gl(3)[::-1]],
    }

    def tap(k):
        d = 0.03
        return smooth(rng.uniform(-1, 1, int(d * SR)), 10 + 2 * k) * dec(d, 0.006)
    packs["rain"] = {
        "label": "rain — soft taps for calm writing",
        "gain": 0.4,
        "key": [tap(k) for k in range(6)],
        "space": [tap(8)],
        "enter": [mix(tap(2), at(tap(4), 0.05, 0.1))],
        "back": [tap(6)],
    }

    for name, p in packs.items():
        d = os.path.join(SFX_DIR, name)
        os.makedirs(d, exist_ok=True)
        g = p.get("gain", 0.8)
        for ev in ("key", "space", "enter", "back"):
            for i, x in enumerate(p[ev]):
                save(os.path.join(d, "%s-%02d.wav" % (ev, i)), x, g)
        for ev, x in shared.items():
            save(os.path.join(d, ev + ".wav"), x, g * (0.7 if ev == "error" else 0.8))
        with open(os.path.join(d, "pack.json"), "w") as f:
            json.dump({"label": p["label"], "pitched": p.get("pitched", False)}, f)


def sfx_manifest(type_override=""):
    """-> {pack: {label, pitched, key:[...], space, enter, back, error, done, run}}"""
    if not os.path.isfile(os.path.join(SFX_DIR, "rain", "pack.json")):
        try:
            synth_packs()
        except Exception as e:                  # numpy missing: launcher pack only
            print("bitewrite: could not synthesise sound packs (%s)" % e, file=sys.stderr)
    out = {}
    for d in sorted(glob.glob(os.path.join(SFX_DIR, "*"))):
        meta = load(os.path.join(d, "pack.json"))
        if not meta:
            continue
        ev = {k: sorted(glob.glob(os.path.join(d, k + "-*.wav"))) for k in ("key", "space", "enter", "back")}
        for k in ("error", "done", "run"):
            ev[k] = [os.path.join(d, k + ".wav")]
        ev.update(meta)
        out[os.path.basename(d)] = ev

    # the launcher's own samples, referenced where they live (serpantinum is AGPL)
    t = type_override if type_override and os.path.isfile(type_override) else \
        os.path.join(SERP_SND, "reusables/input/type.wav")
    if os.path.isfile(t):
        base = out.get("thock") or {}
        click = os.path.join(SERP_SND, "reusables/clickbutton/click.wav")
        out["launcher"] = {
            "label": "launcher — the shell's own click", "pitched": False,
            "key": [t], "space": [t], "back": [t],
            "enter": [click if os.path.isfile(click) else t],
            "error": base.get("error", [t]), "done": base.get("done", [t]), "run": base.get("run", [t]),
        }
    return out


# ── snippets ──────────────────────────────────────────────────────────────────

def snippets():
    """Each snippets/*.js starts with `// name:` and `// about:` lines; the rest
    is the code you type. Drop your own in ~/.local/share/bite-os/bitewrite/snippets."""
    dirs = [os.path.join(HERE, "snippets"),
            os.path.join(E("DATA") or "", "snippets")]
    out = []
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(d, "*.js"))):
            try:
                raw = open(p, encoding="utf-8").read().replace("\t", "    ")
            except OSError:
                continue
            meta, body = {}, []
            for line in raw.splitlines():
                m = re.match(r"^//\s*(name|about|level):\s*(.*)$", line)
                if m and not body:
                    meta[m.group(1)] = m.group(2).strip()
                elif body or line.strip():
                    body.append(line.rstrip())
            while body and not body[-1]:
                body.pop()
            out.append({"name": meta.get("name") or os.path.basename(p)[:-3],
                        "about": meta.get("about", ""), "level": meta.get("level", ""),
                        "code": "\n".join(body)})
    return out


# ── opts ──────────────────────────────────────────────────────────────────────

def prep(rundir):
    def num(key, default, lo, hi):
        try: return max(lo, min(hi, int(float(E("TOY_" + key) or default))))
        except ValueError: return default
    def on(key, default="on"):
        return (E("TOY_" + key) or default).lower() not in ("off", "0", "false", "no")

    pal = {"base": "#221a0f", "surface0": "#312618", "surface1": "#423423",
           "text": "#eddcd2", "subtext0": "#a89386", "mauve": "#b5838d",
           "blue": "#8cb369", "peach": "#f4a261", "teal": "#2a9d8f", "red": "#e76f51",
           "pink": "#e0a96d", "yellow": "#e9c46a", "green": "#a3b18a", "sapphire": "#71a39d"}
    pal.update({k: v for k, v in load("~/.local/state/serpantinum/qs_colors.json").items()
                if isinstance(v, str) and v.startswith("#")})
    st = load("~/.config/serpantinum/settings.json")
    theme, gen = st.get("theme", {}) or {}, st.get("general", {}) or {}
    try:
        shell_vol = 0.0 if gen.get("muteSfx") is True else float(gen.get("sfxVolume", 100)) / 100
    except (TypeError, ValueError):
        shell_vol = 1.0

    sfx = sfx_manifest(E("TOY_TYPE_SOUND") or "")
    pack = E("TOY_SOUNDPACK") or "launcher"
    if pack not in sfx and pack != "none":
        pack = "launcher" if "launcher" in sfx else (next(iter(sfx), "none"))

    opts = {
        "pal": pal,
        "accentKey": E("TOY_ACCENT") or "mauve",
        "font": theme.get("fontFamily") or "JetBrainsMono Nerd Font",
        "radius": theme.get("borderRadius", 10),
        "size": num("SIZE", 28, 12, 72),
        "cols": num("WIDTH", 60, 20, 160),
        "bounce": num("BOUNCE", 5, 0, 10),
        "enter": E("TOY_ENTRANCE") or "launcher",
        "exit": E("TOY_EXIT") or "launcher",
        "colour": E("TOY_COLOUR") or "theme",
        "caret": E("TOY_CARET") or "bar",
        "sparks": on("SPARKS", "on"),
        "combo": on("COMBO", "on"),
        "shake": E("TOY_SHAKE") or "enter",
        "ripple": on("RIPPLE", "off"),
        "pack": pack,
        "shellVolume": shell_vol,
        "volume": num("VOLUME", 10, 0, 10),
        "ghost": num("GHOST", 3, 0, 10),
        "strict": on("STRICT", "off"),
        "flow": E("TOY_FLOW") or "follow",
        "lead": num("LEAD", 0, 0, 3),
        "autoline": on("AUTOLINE", "on"),
        "grace": num("GRACE", 15, 3, 60),
        "speedTime": E("TOY_SPEED_TIME") or "60",
        "speedCustom": num("SPEED_CUSTOM", 90, 10, 600),
        "speedText": E("TOY_SPEED_TEXT") or "words",
        "bests": os.path.join(E("DATA"), "speed-best.json"),
        "defaults": config_defaults(),
        "window": E("TOY_WINDOW") or "window",
        "keep": on("KEEP", "on"),
        "draft": os.path.join(E("DATA"), "page.txt"),
        "docs": E("DOCS") or HOME,
        "home": HOME,
        "sfx": sfx,
    }
    dump(os.path.join(rundir, "opts.json"), opts)
    dump(os.path.join(rundir, "snippets.json"), snippets())
    dump(os.path.join(rundir, "speed.json"), speed_lists())


def config_defaults():
    """config.def's own values, for the panel's reset — first one wins."""
    out = {}
    try:
        for line in open(os.path.join(HERE, "config.def"), encoding="utf-8"):
            m = re.match(r"^([a-z_]+)=(.*)$", line.strip())
            if m:
                out.setdefault(m.group(1), m.group(2))
    except OSError:
        pass
    return out


def speed_lists():
    def lines(name):
        try:
            with open(os.path.join(HERE, name), encoding="utf-8") as f:
                return [l.strip() for l in f if l.strip() and not l.startswith("#")]
        except OSError:
            return []
    words = [w for w in lines("words.txt") if w.isalpha()]
    return {"words": words or "the of and to in is you that it he was for on are with as".split(),
            "sentences": lines("sentences.txt") or ["The quick brown fox jumps over the lazy dog."]}


# ── songs & lyrics ────────────────────────────────────────────────────────────

def players():
    out = []
    for p in run(["playerctl", "-l"]).splitlines():
        p = p.strip()
        if not p:
            continue
        md = run(["playerctl", "-p", p, "metadata", "--format",
                  "{{status}}\t{{artist}}\t{{title}}\t{{album}}\t{{mpris:length}}"]).split("\t")
        if len(md) < 5 or not md[2]:
            continue
        out.append({"kind": "player", "player": p, "status": md[0], "artist": md[1],
                    "title": md[2], "album": md[3],
                    "length": int(md[4]) // 1_000_000 if md[4].isdigit() else 0})
    return out


def local_songs():
    music = run(["xdg-user-dir", "MUSIC"]) or os.path.join(HOME, "Music")
    roots = [r for r in (music, os.path.join(E("DATA") or "", "songs")) if os.path.isdir(r) and r != HOME]
    out = []
    for root in roots:
        base = root.rstrip("/").count("/")
        for d, subs, files in os.walk(root):
            if d.count("/") - base >= 4:
                subs[:] = []
            for f in sorted(files):
                if not f.lower().endswith(AUDIO):
                    continue
                p = os.path.join(d, f)
                stem = os.path.splitext(f)[0]
                artist, title = ("", stem)
                if " - " in stem:
                    artist, title = [s.strip() for s in stem.split(" - ", 1)]
                side = any(os.path.isfile(os.path.splitext(p)[0] + x) for x in (".lrc", ".txt"))
                out.append({"kind": "file", "path": p, "artist": artist, "title": title,
                            "local": side})
                if len(out) >= 400:
                    return out
    return out


def file_meta(p):
    raw = run(["ffprobe", "-v", "error", "-show_entries", "format=duration:format_tags",
               "-of", "json", p], timeout=6)
    try:
        fmt = json.loads(raw).get("format", {})
    except Exception:
        fmt = {}
    tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
    stem = os.path.splitext(os.path.basename(p))[0]
    artist, title = ("", stem)
    if " - " in stem:
        artist, title = [s.strip() for s in stem.split(" - ", 1)]
    return {"artist": tags.get("artist") or artist, "title": tags.get("title") or title,
            "album": tags.get("album", ""), "length": int(float(fmt.get("duration") or 0)),
            "lyrics": tags.get("lyrics") or tags.get("unsyncedlyrics") or ""}


TAG = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
WORD = re.compile(r"<\d+:\d+(?:[.:]\d+)?>")


def parse_lyrics(text):
    """-> (lines [{t, text}], synced). LRC stamps become seconds; plain text
    keeps t = -1. Blank lines and [ar:]-style headers go."""
    lines, synced = [], False
    for raw in text.splitlines():
        stamps = TAG.findall(raw)
        body = WORD.sub("", TAG.sub("", raw)).strip()
        if re.match(r"^\[[a-z]+:.*\]$", raw.strip(), re.I):
            continue
        if stamps:
            synced = True
            for m, s in stamps:
                if body:
                    lines.append({"t": int(m) * 60 + float(s.replace(":", ".")), "text": body})
        elif body:
            lines.append({"t": -1, "text": body})
    if synced:
        lines = sorted((l for l in lines if l["t"] >= 0), key=lambda l: l["t"])
    return lines, synced


def safe(s):
    return re.sub(r'[/\\:*?"<>|]', "_", s).strip()


JUNK = re.compile(
    r"\((?:[^()]*\b(?:official|video|audio|lyric|lyrics|visuali[sz]er|remaster"
    r"|remastered|hd|hq|4k|8k|mv|explicit|clean|extended|full|colou?r)\b[^()]*)\)"
    r"|\[[^\]]*\]", re.I)


def candidates(meta):
    artist = (meta.get("artist") or "").strip()
    title = (meta.get("title") or "").strip()
    ct = re.sub(r"\s+", " ", re.sub(r"\s*[|·]\s*.*$", "", JUNK.sub(" ", title))).strip(" -–—·")
    out = []
    if artist and ct: out.append((artist, ct))
    for sep in (" - ", " – ", " — "):
        if sep in ct:
            a, t = ct.split(sep, 1)
            if a.strip() and t.strip(): out.append((a.strip(), t.strip()))
            break
    if ct: out.append(("", ct))
    seen, res = set(), []
    for c in out:
        if c not in seen:
            seen.add(c); res.append(c)
    return res


def _api(path, params):
    try:
        req = urllib.request.Request(
            "https://lrclib.net/api/%s?%s" % (path, urllib.parse.urlencode(params)),
            headers={"User-Agent": "bitewrite (BITE-OS toy)"})
        with urllib.request.urlopen(req, timeout=7) as r:
            return json.load(r)
    except Exception:
        return None


def lrclib(meta):
    plain = None
    for artist, title in candidates(meta):
        p = {"artist_name": artist, "track_name": title}
        if meta.get("length"): p["duration"] = meta["length"]
        for params in (p, {"artist_name": artist, "track_name": title}):
            d = _api("get", params)
            if isinstance(d, dict):
                if (d.get("syncedLyrics") or "").strip(): return d["syncedLyrics"]
                plain = plain or (d.get("plainLyrics") or "").strip() or None
    for artist, title in candidates(meta)[:2]:
        d = _api("search", {"q": ("%s %s" % (artist, title)).strip()})
        if isinstance(d, list):
            for hit in d[:5]:
                if (hit.get("syncedLyrics") or "").strip(): return hit["syncedLyrics"]
                plain = plain or (hit.get("plainLyrics") or "").strip() or None
    return plain


def lyrics(req):
    meta = file_meta(req["path"]) if req.get("kind") == "file" else dict(req)
    text, source = None, None
    if req.get("kind") == "file":
        for ext in (".lrc", ".txt"):
            c = os.path.splitext(req["path"])[0] + ext
            if os.path.isfile(c):
                text, source = open(c, encoding="utf-8", errors="replace").read(), "next to the song"
                break
        if not text and meta.get("lyrics"):
            text, source = meta["lyrics"], "the file's tags"
    name = "%s - %s.lrc" % (safe(meta.get("artist", "")), safe(meta.get("title", "")))
    if not text and os.path.isfile(os.path.join(LYR_CACHE, name)):
        text, source = open(os.path.join(LYR_CACHE, name), encoding="utf-8").read(), "cache"
    if not text and meta.get("title"):
        text = lrclib(meta)
        if text:
            source = "lrclib.net"
            try:
                os.makedirs(LYR_CACHE, exist_ok=True)
                with open(os.path.join(LYR_CACHE, name), "w", encoding="utf-8") as f:
                    f.write(text)
            except OSError:
                pass
    if not text:
        return {"ok": False, "error": "no lyrics found for %s" % (meta.get("title") or "that"),
                "meta": meta}
    lines, synced = parse_lyrics(text)
    return {"ok": True, "lines": lines, "synced": synced, "source": source,
            "meta": {k: meta.get(k, "") for k in ("artist", "title", "album", "length")}}


# ── MPRIS ─────────────────────────────────────────────────────────────────────

def player_op(p, op):
    """play/pause, with a short volume fade where the player supports it —
    typing stopping should feel like the song drifting off, not a hard cut."""
    if not p:
        return {"ok": False}
    if op == "play":
        run(["playerctl", "-p", p, "play"])
        v = run(["playerctl", "-p", p, "volume"])
        if v:
            try:
                target = float(PLAYER_VOL.get(p, v))
                for i in range(1, 6):
                    run(["playerctl", "-p", p, "volume", "%.3f" % (target * i / 5)]); time.sleep(0.04)
            except ValueError:
                pass
    elif op == "pause":
        v = run(["playerctl", "-p", p, "volume"])
        try:
            PLAYER_VOL.setdefault(p, float(v))
            for i in range(4, 0, -1):
                run(["playerctl", "-p", p, "volume", "%.3f" % (PLAYER_VOL[p] * i / 5)]); time.sleep(0.05)
        except ValueError:
            pass
        run(["playerctl", "-p", p, "pause"])
        if p in PLAYER_VOL:
            run(["playerctl", "-p", p, "volume", "%.3f" % PLAYER_VOL[p]])
    elif op in ("next", "previous"):
        run(["playerctl", "-p", p, op])
    return {"ok": True}


PLAYER_VOL = {}


def player_now(p):
    md = run(["playerctl", "-p", p, "metadata", "--format",
              "{{status}}\t{{position}}\t{{artist}}\t{{title}}"], timeout=2).split("\t")
    if len(md) < 4:
        return {"ok": False}
    return {"ok": True, "status": md[0],
            "pos": int(md[1]) / 1_000_000 if md[1].isdigit() else 0,
            "artist": md[2], "title": md[3], "at": time.time()}


# ── settings ──────────────────────────────────────────────────────────────────

def set_setting(key, value):
    if not re.match(r"^[a-z_]+$", key or ""):
        return {"ok": False, "error": "bad key"}
    if shutil.which("bite-toys"):
        r = subprocess.run(["bite-toys", "config", "bitewrite", key, str(value)],
                           capture_output=True, text=True, timeout=20)
        if r.returncode == 0:
            return {"ok": True}
    # standalone, or the hub refused: edit the file ourselves, last line wins
    conf = os.path.join(E("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"),
                        "bite-os", "toys", "bitewrite.conf")
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    try:
        lines = open(conf, encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    lines = [l for l in lines if not l.startswith(key + "=")] + ["%s=%s" % (key, value)]
    with open(conf, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return {"ok": True}


# ── serve ─────────────────────────────────────────────────────────────────────

def serve(rundir):
    reqf, statf = os.path.join(rundir, "request.json"), os.path.join(rundir, "status.json")
    nowf = os.path.join(rundir, "now.json")
    last, watch, next_poll = None, "", 0
    parent = os.getppid()
    while True:
        try:
            if os.getppid() != parent:                 # the window went away
                return 0
            if os.path.exists(reqf) and os.path.getmtime(reqf) != last:
                last = os.path.getmtime(reqf)
                try:
                    req = json.load(open(reqf, encoding="utf-8"))
                except Exception:
                    time.sleep(0.03); last = None; continue
                a = req.get("action")
                if a == "quit":
                    return 0
                if a == "songs":
                    res = {"ok": True, "songs": players() + local_songs()}
                elif a == "lyrics":
                    res = lyrics(req)
                elif a == "player":
                    res = player_op(req.get("player", ""), req.get("op", ""))
                elif a == "watch":
                    watch = req.get("player", ""); res = {"ok": True}
                elif a == "set":
                    # a batch, so arrowing through the panel can't outrun us
                    pairs = req.get("pairs") or {req.get("key", ""): req.get("value", "")}
                    res = {"ok": all(set_setting(k, v).get("ok") for k, v in pairs.items())}
                else:
                    res = {"ok": False, "error": "unknown action"}
                res["seq"] = req.get("seq", 0)
                res["action"] = a
                dump(statf, res)
            if watch and time.time() >= next_poll:
                dump(nowf, player_now(watch))
                next_poll = time.time() + 0.25
            time.sleep(0.04)
        except KeyboardInterrupt:
            return 0
        except Exception as e:
            try:
                dump(statf, {"ok": False, "error": str(e)[:200], "seq": -1})
            except Exception:
                pass
            time.sleep(0.2)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--prep":
        prep(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "--serve":
        sys.exit(serve(sys.argv[2]))
    else:
        print("usage: engine.py --prep RUNDIR | --serve RUNDIR", file=sys.stderr)
        sys.exit(2)
