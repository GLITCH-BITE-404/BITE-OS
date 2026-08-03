#!/usr/bin/env python3
"""Builds the museum's catalogue: one JSON file describing the exhibits.

Kept separate from the QML so the slow part (walking a very large home
directory) runs once with a progress bar and is cached, while the app itself
starts instantly on every later visit.

Strictly read-only. Nothing here opens a file for writing except the cache.
"""

import json
import os
import re
import sqlite3
import shutil
import sys
import time

HOME = os.path.expanduser("~")
CACHE = os.path.expanduser("~/.cache/bite-os")
OUT = os.path.join(CACHE, "museum.json")

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".heic", ".avif"}
VIDEO_EXT = {".mp4", ".mkv", ".mov", ".webm", ".avi"}

# Directories that are noise, not history: caches, package trees, VM images,
# build output. Skipping these is the difference between a 30-second scan and
# one that never finishes.
SKIP_NAMES = {
    ".cache", ".git", "node_modules", "__pycache__", ".venv", "venv",
    ".rustup", ".cargo", ".npm", ".gradle", ".m2", ".nuget", ".pub-cache",
    "Trash", ".Trash", ".local/share/Trash", "site-packages", ".mypy_cache",
    ".pytest_cache", ".tox", "target", "dist-newstyle", ".stack-work",
    ".steam", ".steampath", "Steam", ".wine", ".var", ".flatpak",
    ".thumbnails", "thumbnails", ".mozilla", ".config", ".local",
    "vendor", ".terraform", ".conda", "miniconda3", "anaconda3",
}


def human(n):
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return "%.0f %s" % (n, u) if u == "B" else "%.1f %s" % (n, u)
        n /= 1024.0
    return "%.1f PB" % n


def install_date():
    """First line of pacman.log is the moment this system was created."""
    for path in ("/var/log/pacman.log",):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = re.match(r"\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})", line)
                    if m:
                        return m.group(1), m.group(2)
        except OSError:
            pass
    return None, None


def walk(root, progress=None):
    """Iterative scandir walk that prunes noise and never follows symlinks."""
    stack = [root]
    seen = 0
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_symlink():
                            continue
                        if e.is_dir(follow_symlinks=False):
                            if e.name in SKIP_NAMES or e.name.startswith(".cache"):
                                continue
                            stack.append(e.path)
                        elif e.is_file(follow_symlinks=False):
                            seen += 1
                            if progress and seen % 20000 == 0:
                                progress(seen)
                            yield e
                    except OSError:
                        continue
        except (OSError, PermissionError):
            continue


# Sign-in pages and bare search engines are not places you *went* — they are
# plumbing, and they crowd out the sites that actually say something about you.
NOISE_HOSTS = {
    "google.com", "www.google.com", "accounts.google.com", "myaccount.google.com",
    "bing.com", "duckduckgo.com", "search.brave.com", "t.co", "l.facebook.com",
    "localhost", "127.0.0.1", "newtab", "about:blank",
}
NOISE_PREFIX = ("accounts.", "login.", "auth.", "sso.", "signin.", "oauth.",
                "static.", "cdn.", "api.")


def interesting(host):
    if not host or host in NOISE_HOSTS:
        return False
    if host.startswith(NOISE_PREFIX):
        return False
    return "." in host


def browser_history(limit=20):
    """Earliest and most-visited pages, read from a COPY of the database.

    The live file is locked while the browser runs, and it is never written to
    here — the copy is made in the cache and deleted straight after.
    """
    first, top = [], []
    tmp = os.path.join(CACHE, "_hist.tmp")

    def pull(src, query, scale, epoch=0):
        try:
            shutil.copy2(src, tmp)
            con = sqlite3.connect("file:%s?immutable=1" % tmp, uri=True)
            rows = con.execute(query).fetchall()
            con.close()
            return rows
        except Exception:
            return []
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass

    import glob
    for ff in glob.glob(os.path.join(HOME, ".mozilla/firefox/*/places.sqlite")):
        rows = pull(ff, """
            SELECT url, title, visit_count, last_visit_date
            FROM moz_places WHERE visit_count > 0 AND url LIKE 'http%'
            ORDER BY visit_count DESC LIMIT 40""", 1e6)
        for url, title, vc, _ in rows:
            top.append({"url": url, "title": title or "", "visits": vc or 0})
        rows = pull(ff, """
            SELECT p.url, p.title, MIN(v.visit_date)
            FROM moz_historyvisits v JOIN moz_places p ON p.id = v.place_id
            WHERE p.url LIKE 'http%'
            GROUP BY p.id ORDER BY MIN(v.visit_date) ASC LIMIT 40""", 1e6)
        for url, title, when in rows:
            if when:
                first.append({"url": url, "title": title or "",
                              "when": int(when / 1e6)})

    for ch in glob.glob(os.path.join(HOME, ".config/google-chrome/*/History")) + \
              glob.glob(os.path.join(HOME, ".config/chromium/*/History")):
        rows = pull(ch, """
            SELECT url, title, visit_count, last_visit_time
            FROM urls WHERE visit_count > 0 AND url LIKE 'http%'
            ORDER BY visit_count DESC LIMIT 40""", 1e6)
        for url, title, vc, _ in rows:
            top.append({"url": url, "title": title or "", "visits": vc or 0})
        rows = pull(ch, """
            SELECT url, title, MIN(last_visit_time) FROM urls
            WHERE url LIKE 'http%' AND last_visit_time > 0
            GROUP BY id ORDER BY MIN(last_visit_time) ASC LIMIT 40""", 1e6)
        for url, title, when in rows:
            if when:      # chrome epoch: microseconds since 1601
                first.append({"url": url, "title": title or "",
                              "when": int(when / 1e6 - 11644473600)})

    def host(u):
        m = re.match(r"https?://([^/]+)", u or "")
        return (m.group(1) if m else u or "").replace("www.", "")

    for row in first + top:
        row["host"] = host(row["url"])

    first = [r for r in first
             if r.get("when", 0) > 946684800 and interesting(r["host"])]
    first.sort(key=lambda r: r["when"])
    top = [r for r in top if interesting(r["host"])]
    top.sort(key=lambda r: -r["visits"])

    # One row per host in both columns — the same sign-in page listed nine times
    # is noise, not history.
    def by_host(rows):
        seen, out = set(), []
        for r in rows:
            if r["host"] in seen:
                continue
            seen.add(r["host"])
            out.append(r)
            if len(out) >= limit:
                break
        return out

    return by_host(first), by_host(top)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else HOME
    want_history = "--no-history" not in sys.argv
    os.makedirs(CACHE, exist_ok=True)

    t0 = time.time()
    files = []

    def progress(n):
        sys.stderr.write("\r  reading the archives… %d files" % n)
        sys.stderr.flush()

    for e in walk(root, progress):
        try:
            st = e.stat(follow_symlinks=False)
        except OSError:
            continue
        files.append((e.path, e.name, st.st_size, st.st_mtime, st.st_atime))
    sys.stderr.write("\r  read %d files in %.1fs%s\n"
                     % (len(files), time.time() - t0, " " * 20))

    now = time.time()
    year_ago = now - 365 * 86400

    def pack(rec, extra=None):
        path, name, size, mtime, atime = rec
        d = {"path": path, "name": name, "size": size, "human": human(size),
             "mtime": int(mtime), "atime": int(atime),
             "dir": os.path.dirname(path).replace(HOME, "~"),
             "age_years": round((now - mtime) / (365 * 86400), 1)}
        if extra:
            d.update(extra)
        return d

    by_old = sorted((f for f in files if f[3] > 946684800), key=lambda f: f[3])
    by_big = sorted(files, key=lambda f: -f[2])
    images = [f for f in files if os.path.splitext(f[1])[1].lower() in IMAGE_EXT
              and f[2] > 20000]
    images.sort(key=lambda f: f[3])
    videos = [f for f in files if os.path.splitext(f[1])[1].lower() in VIDEO_EXT]

    forgotten = sorted((f for f in files if f[2] > 5_000_000 and f[4] < year_ago),
                       key=lambda f: f[4])

    longest = max(files, key=lambda f: len(f[1])) if files else None
    deepest = max(files, key=lambda f: f[0].count(os.sep)) if files else None

    idate, itime = install_date()
    first_web, top_web = browser_history() if want_history else ([], [])

    total_bytes = sum(f[2] for f in files)
    data = {
        "generated": int(now),
        "root": root,
        "user": os.environ.get("USER") or os.path.basename(HOME),
        "host": os.uname().nodename,
        "install_date": idate, "install_time": itime,
        "install_age_days": (int((now - time.mktime(time.strptime(idate, "%Y-%m-%d"))) / 86400)
                             if idate else None),
        "totals": {
            "files": len(files), "bytes": total_bytes, "human": human(total_bytes),
            "images": len(images), "videos": len(videos),
            "span_years": round((now - by_old[0][3]) / (365 * 86400), 1) if by_old else 0,
        },
        "oldest": [pack(f) for f in by_old[:40]],
        "biggest": [pack(f) for f in by_big[:40]],
        "forgotten": [pack(f) for f in forgotten[:40]],
        "photos": [pack(f) for f in images[:40]],
        "curiosities": {
            "longest_name": pack(longest) if longest else None,
            "deepest": pack(deepest) if deepest else None,
        },
        "first_web": first_web,
        "top_web": top_web,
    }

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    sys.stderr.write("  catalogue written: %s\n" % OUT)


main()
