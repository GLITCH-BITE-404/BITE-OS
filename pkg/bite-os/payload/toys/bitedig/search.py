#!/usr/bin/env python3
"""bitedig — search that goes deeper the further out you go.

The engine half. No Qt, works headless, and everything the window can do is a
command-line flag — same split as biteglyph.

Search runs in DEPTHS, and each depth is a different engine:

    1 names      file and folder names           fd, or find
    2 contents   inside text files               ripgrep
    3 media      pictures, audio, video by tag   ffprobe
    4 web        the open web, many engines      SearxNG (JSON API)
    5 onion      Tor-reachable sites             tor + Ahmia

A depth whose engine is missing is not an error — it reports itself as
unavailable with the package that would provide it, and the front-end offers
to install it. Nothing is installed behind your back.

    search.py "wolf" --depth names,contents
    search.py "wolf" --engines            # JSON: what's installed, what isn't
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")

# command -> (package, what the depth is called, one-line why)
ENGINES = {
    "fd":       ("fd",            "names",    "fast file-name search"),
    "find":     ("findutils",     "names",    "always there; slower fallback"),
    "rg":       ("ripgrep",       "contents", "searches inside text files"),
    "ffprobe":  ("ffmpeg",        "media",    "reads tags out of media files"),
    "curl":     ("curl",          "web",      "talks to the search API"),
    "tor":      ("tor",           "onion",    "routes onion requests"),
}

DEPTHS = ["names", "contents", "media", "web", "onion"]

# Sites worth reaching over Tor. Deliberately a short, named list rather than a
# crawler: a general onion index mostly surfaces markets and stolen data, and
# that is not a thing worth building. These are the legitimate ones people
# actually want — press freedom, mirrors of real services, archives.
ONION_KNOWN = [
    ("SecureDrop directory", "https://securedrop.org/directory/",
     "leak to newsrooms, run by Freedom of the Press Foundation"),
    ("Ahmia search",         "https://ahmia.fi/search/?q=%s",
     "clearnet-indexed onion search; filters abuse material"),
    ("Tor Project",          "https://www.torproject.org/",
     "the software itself"),
    ("Internet Archive",     "https://archive.org/",
     "onion mirror exists for censored regions"),
]


def have(cmd):
    return shutil.which(cmd) is not None


# The embedded viewer is a QML module, not a command, so `which` cannot see it.
WEBENGINE_QML = "/usr/lib/qt6/qml/QtWebEngine"


def have_webengine():
    return os.path.isdir(WEBENGINE_QML)


def set_setting(key, value):
    """Persist a setting through the hub, so its validation still applies."""
    if not shutil.which("bite-toys"):
        return {"ok": False, "error": "bite-toys is not on PATH"}
    r = subprocess.run(["bite-toys", "config", "bitedig", key, str(value)],
                       capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        tail = (r.stderr or "").strip().splitlines()
        return {"ok": False, "error": tail[-1] if tail else "could not save"}
    return {"ok": True, "saved": key + "=" + str(value)}


def engines_status():
    """What each depth needs, and whether this machine has it."""
    out = []
    for depth in DEPTHS:
        need = [c for c, (_, d, _) in ENGINES.items() if d == depth]
        primary = need[0] if need else ""
        ok = any(have(c) for c in need)
        missing = [c for c in need if not have(c)]
        pkgs = sorted({ENGINES[c][0] for c in missing})
        out.append({
            "depth": depth,
            "ready": ok,
            "uses": primary,
            "why": ENGINES.get(primary, ("", "", ""))[2],
            "missing": missing,
            "packages": pkgs,
        })
    return out


# ── depth 1: names ────────────────────────────────────────────────────────────

def dig_names(q, root, limit):
    hits = []
    if have("fd"):
        cmd = ["fd", "--hidden", "--follow", "--color", "never",
               "--max-results", str(limit), "--", q, root]
    else:
        cmd = ["find", root, "-iname", "*%s*" % q]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
        for line in r.stdout.splitlines()[:limit]:
            p = line.strip()
            if not p:
                continue
            try:
                st = os.stat(p)
                size, mtime = st.st_size, st.st_mtime
            except OSError:
                size, mtime = 0, 0
            hits.append({"depth": "names", "path": p,
                         "name": os.path.basename(p),
                         "size": size, "mtime": mtime,
                         "dir": os.path.isdir(p)})
    except Exception:
        pass
    return hits


# ── depth 2: contents ─────────────────────────────────────────────────────────

def dig_contents(q, root, limit):
    if not have("rg"):
        return []
    hits = []
    cmd = ["rg", "--json", "--max-count", "2", "--smart-case",
           "--max-filesize", "4M", "--", q, root]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        for line in r.stdout.splitlines():
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") != "match":
                continue
            d = ev["data"]
            path = d["path"].get("text", "")
            text = (d["lines"].get("text") or "").strip()[:160]
            hits.append({"depth": "contents", "path": path,
                         "name": os.path.basename(path),
                         "line": d.get("line_number", 0),
                         "excerpt": text})
            if len(hits) >= limit:
                break
    except Exception:
        pass
    return hits


# ── depth 3: media ────────────────────────────────────────────────────────────

MEDIA_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".mp3", ".flac", ".ogg",
             ".wav", ".m4a", ".opus", ".jpg", ".jpeg", ".png", ".gif", ".webp"}


def dig_media(q, root, limit):
    """Media whose NAME or embedded tags match. ffprobe is the slow part, so it
    only runs on files that are plausibly media in the first place."""
    if not have("ffprobe"):
        return []
    ql = q.lower()
    cands, hits = [], []
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for f in files:
            if os.path.splitext(f)[1].lower() in MEDIA_EXT:
                cands.append(os.path.join(dirpath, f))
        if len(cands) > 4000:
            break

    for p in cands:
        if len(hits) >= limit:
            break
        name_hit = ql in os.path.basename(p).lower()
        tags = {}
        if not name_hit:
            continue                       # tag-probing everything is far too slow
        try:
            r = subprocess.run(
                ["ffprobe", "-v", "error", "-show_entries",
                 "format=duration:format_tags=title,artist,album",
                 "-of", "json", p],
                capture_output=True, text=True, timeout=6)
            fmt = json.loads(r.stdout).get("format", {})
            tags = fmt.get("tags", {}) or {}
            dur = float(fmt.get("duration") or 0)
        except Exception:
            dur = 0.0
        hits.append({"depth": "media", "path": p, "name": os.path.basename(p),
                     "duration": round(dur, 1),
                     "title": tags.get("title", ""), "artist": tags.get("artist", "")})
    return hits


# ── depth 4: web ──────────────────────────────────────────────────────────────

def _searx(q, limit, instance):
    """A SearxNG instance, if you have one. Best results by far — it aggregates
    real engines and returns clean JSON.

    Public instances almost all block this: they answer a `format=json` query
    with a captcha page, a 403 or a 429, because bots hammer them. Measured on
    searx.be, searxng.site, priv.au — none of them serve the API to a stranger.
    So this is the path for YOUR instance, not a promise about someone else's.
    """
    if not instance or not have("curl"):
        return []
    try:
        r = subprocess.run(
            ["curl", "-fsSL", "--connect-timeout", "8", "--max-time", "20",
             "-G", instance.rstrip("/") + "/search",
             "--data-urlencode", "q=" + q, "--data-urlencode", "format=json"],
            capture_output=True, text=True, timeout=25)
        data = json.loads(r.stdout or "{}")
    except Exception:
        return []
    out = []
    for it in (data.get("results") or [])[:limit]:
        out.append({"depth": "web", "title": it.get("title", ""),
                    "url": it.get("url", ""),
                    "excerpt": (it.get("content") or "")[:200],
                    "engine": it.get("engine", "searx")})
    return out


def _open_apis(q, limit):
    """No key, no scraping, no terms violated — but narrower than a real engine.

    DuckDuckGo's Instant Answer API gives you the summary and related topics
    rather than a ranked page of links, and Wikipedia gives you articles. That
    is the honest ceiling without either an API key or scraping someone's
    results page against their terms.
    """
    out = []
    if not have("curl"):
        return out
    try:
        r = subprocess.run(
            ["curl", "-fsSL", "--connect-timeout", "8", "--max-time", "15",
             "-G", "https://api.duckduckgo.com/",
             "--data-urlencode", "q=" + q,
             "--data-urlencode", "format=json",
             "--data-urlencode", "no_html=1",
             "--data-urlencode", "t=bitedig"],
            capture_output=True, text=True, timeout=20)
        d = json.loads(r.stdout or "{}")
        if d.get("AbstractText"):
            out.append({"depth": "web", "title": d.get("Heading") or q,
                        "url": d.get("AbstractURL", ""),
                        "excerpt": d["AbstractText"][:220],
                        "engine": "duckduckgo"})
        for t in (d.get("RelatedTopics") or []):
            if len(out) >= limit:
                break
            if isinstance(t, dict) and t.get("Text"):
                out.append({"depth": "web", "title": t["Text"].split(" - ")[0][:80],
                            "url": (t.get("FirstURL") or ""),
                            "excerpt": t["Text"][:200], "engine": "duckduckgo"})
    except Exception:
        pass

    try:
        r = subprocess.run(
            ["curl", "-fsSL", "--connect-timeout", "8", "--max-time", "15",
             "-G", "https://en.wikipedia.org/w/api.php",
             "--data-urlencode", "action=opensearch",
             "--data-urlencode", "search=" + q,
             "--data-urlencode", "limit=5",
             "--data-urlencode", "format=json"],
            capture_output=True, text=True, timeout=20)
        d = json.loads(r.stdout or "[]")
        for title, url in zip(d[1], d[3]):
            if len(out) >= limit:
                break
            out.append({"depth": "web", "title": title, "url": url,
                        "excerpt": "", "engine": "wikipedia"})
    except Exception:
        pass
    return out[:limit]


def dig_web(q, limit, instance):
    """Your own Searx if it answers, the open APIs otherwise."""
    hits = _searx(q, limit, instance)
    if hits:
        return hits
    return _open_apis(q, limit)


# ── depth 5: onion ────────────────────────────────────────────────────────────

def dig_onion(q, limit):
    """Deliberately a curated list, not an index.

    There is no crawler here and there will not be one. A general onion index
    mostly surfaces markets and stolen data; these are the legitimate services
    people actually have a reason to reach. Opening any of them is gated behind
    a confirmation in the front-end, and Tor has to be installed first.
    """
    ready = have("tor")
    out = []
    for name, url, why in ONION_KNOWN:
        out.append({"depth": "onion", "title": name,
                    "url": url % q if "%s" in url else url,
                    "excerpt": why, "needs_tor": True, "tor_ready": ready})
    return out[:limit]


# ── driver ────────────────────────────────────────────────────────────────────

def dig(q, depths, root, limit, instance):
    res = {"query": q, "depths": {}, "took": 0.0}
    t0 = time.time()
    for d in depths:
        s = time.time()
        if d == "names":
            hits = dig_names(q, root, limit)
        elif d == "contents":
            hits = dig_contents(q, root, limit)
        elif d == "media":
            hits = dig_media(q, root, limit)
        elif d == "web":
            hits = dig_web(q, limit, instance)
        elif d == "onion":
            hits = dig_onion(q, limit)
        else:
            continue
        res["depths"][d] = {"hits": hits, "took": round(time.time() - s, 2)}
    res["took"] = round(time.time() - t0, 2)
    return res


# ── installing an engine ──────────────────────────────────────────────────────

def _installed(pkg):
    return subprocess.run(["pacman", "-Q", pkg],
                          capture_output=True).returncode == 0


def install(packages):
    """Offer to install a missing engine. Never silent, never automatic.

    The hard part is the password. Plain `sudo` with captured output prompts on
    the terminal bitedig was launched from — invisible if you are looking at the
    window, and it simply hangs there forever. pkexec asks through the desktop's
    own polkit agent, which is the only place a GUI can honestly ask.
    """
    packages = [p for p in packages if p]
    if not packages:
        return {"ok": True, "note": "nothing to install"}
    if not shutil.which("pacman"):
        return {"ok": False,
                "error": "not an Arch system — install by hand: " + " ".join(packages)}

    already = [p for p in packages if _installed(p)]
    want = [p for p in packages if p not in already]
    if not want:
        return {"ok": True, "installed": already, "note": "already present"}

    graphical = bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
    tried = []

    if graphical and shutil.which("pkexec"):
        tried.append("pkexec")
        try:
            r = subprocess.run(
                ["pkexec", "pacman", "-S", "--needed", "--noconfirm"] + want,
                capture_output=True, text=True, timeout=1800)
        except Exception as e:
            r = None
            err = str(e)[:160]
        if r is not None and r.returncode == 0:
            return {"ok": True, "installed": want}

    # passwordless sudo, if the machine happens to allow it
    tried.append("sudo -n")
    try:
        r = subprocess.run(["sudo", "-n", "pacman", "-S", "--needed",
                            "--noconfirm"] + want,
                           capture_output=True, text=True, timeout=1800)
    except Exception:
        r = None

    # Whatever route ran, believe pacman rather than a return code.
    done = [p for p in want if _installed(p)]
    if len(done) == len(want):
        return {"ok": True, "installed": want}

    missing = [p for p in want if p not in done]
    return {"ok": False,
            "error": "could not install " + " ".join(missing) +
                     " — run:  sudo pacman -S " + " ".join(missing),
            "installed": done,
            "tried": tried}


# ── serve mode (the QML front-end talks to this) ──────────────────────────────

def serve(rundir):
    """QML can read and write files but cannot start a process, so the window
    writes request.json and we answer in status.json. Same shape as biteglyph."""
    rundir = os.path.abspath(rundir)
    os.makedirs(rundir, exist_ok=True)
    reqf = os.path.join(rundir, "request.json")
    statf = os.path.join(rundir, "status.json")
    last = None
    while True:
        try:
            if os.path.exists(reqf):
                stamp = os.path.getmtime(reqf)
                if stamp != last:
                    last = stamp
                    try:
                        with open(reqf, encoding="utf-8") as fh:
                            req = json.load(fh)
                    except Exception:
                        time.sleep(0.05)
                        continue
                    if req.get("quit"):
                        return 0

                    if req.get("action") == "engines":
                        res = {"ok": True, "engines": engines_status(),
                               "webengine": have_webengine()}
                    elif req.get("action") == "setting":
                        res = set_setting(req.get("key", ""), req.get("value", ""))
                    elif req.get("action") == "install":
                        res = install(req.get("packages") or [])
                        res["engines"] = engines_status()
                        res["webengine"] = have_webengine()
                    elif req.get("action") == "open":
                        res = open_target(req.get("target", ""), req.get("tor", False))
                    else:
                        res = {"ok": True}
                        res.update(dig(req.get("q", ""),
                                       req.get("depths") or ["names"],
                                       os.path.expanduser(req.get("root") or HOME),
                                       int(req.get("limit", 40)),
                                       req.get("web_instance") or DEFAULT_SEARX))
                    res["seq"] = req.get("seq", 0)
                    tmp = statf + ".tmp"
                    with open(tmp, "w", encoding="utf-8") as fh:
                        json.dump(res, fh)
                    os.replace(tmp, statf)
            time.sleep(0.08)
        except KeyboardInterrupt:
            return 0
        except Exception as e:
            try:
                with open(statf, "w", encoding="utf-8") as fh:
                    json.dump({"ok": False, "error": str(e)[:200]}, fh)
            except Exception:
                pass
            time.sleep(0.2)


DEFAULT_SEARX = ""   # your own instance; blank = use the open APIs


def open_target(target, over_tor=False):
    """Open a file, a folder or a URL. Onion routing is opt-in and explicit."""
    if not target:
        return {"ok": False, "error": "nothing to open"}
    if over_tor:
        if shutil.which("torbrowser-launcher"):
            subprocess.Popen(["torbrowser-launcher", target],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {"ok": True, "opened": target, "via": "tor browser"}
        if not shutil.which("tor"):
            return {"ok": False,
                    "error": "tor is not installed — install it first",
                    "packages": ["tor", "torbrowser-launcher"]}
        return {"ok": False,
                "error": "tor is running but Tor Browser is not installed",
                "packages": ["torbrowser-launcher"]}
    try:
        subprocess.Popen(["xdg-open", target],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        return {"ok": False, "error": str(e)[:160]}
    return {"ok": True, "opened": target}


# ── cli ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(prog="bitedig")
    ap.add_argument("query", nargs="?", default="")
    ap.add_argument("--depth", default="names",
                    help="comma list: " + ",".join(DEPTHS) + ", or 'all'")
    ap.add_argument("--root", default=HOME)
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--web-instance", default="",
                    help="your own SearxNG; blank falls back to open APIs")
    ap.add_argument("--engines", action="store_true",
                    help="JSON: which depths are ready and what is missing")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--serve", metavar="DIR")
    a = ap.parse_args()

    if a.serve:
        return serve(a.serve)
    if a.engines:
        print(json.dumps(engines_status(), indent=2))
        return 0
    if not a.query:
        ap.error("give me something to look for")

    depths = DEPTHS if a.depth == "all" else \
        [d.strip() for d in a.depth.split(",") if d.strip() in DEPTHS]
    res = dig(a.query, depths, os.path.expanduser(a.root), a.limit, a.web_instance)

    if a.json:
        print(json.dumps(res, indent=2))
        return 0

    for d in depths:
        block = res["depths"].get(d) or {}
        hits = block.get("hits") or []
        st = [e for e in engines_status() if e["depth"] == d][0]
        head = "\x1b[1m%s\x1b[0m \x1b[2m(%.2fs)\x1b[0m" % (d, block.get("took", 0))
        if not st["ready"]:
            print("%s  \x1b[33mneeds %s\x1b[0m" % (head, " ".join(st["packages"])))
            continue
        print("%s  %d" % (head, len(hits)))
        for h in hits[:12]:
            if d in ("web", "onion"):
                print("   \x1b[36m%s\x1b[0m" % (h.get("title") or h.get("url")))
                print("     \x1b[2m%s\x1b[0m" % h.get("url", ""))
            elif d == "contents":
                print("   %s\x1b[2m:%s\x1b[0m  %s"
                      % (h["path"], h.get("line", 0), h.get("excerpt", "")[:90]))
            else:
                print("   %s" % h["path"])
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
