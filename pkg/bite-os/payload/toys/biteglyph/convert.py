#!/usr/bin/env python3
"""biteglyph — turn a picture, gif or video into ASCII art.

The engine half. It has no window and no Qt: the QML front-end shells out to
this, and so can you. Everything the GUI can do is reachable from the command
line, which is also what makes it testable without a display.

    convert.py IN --out OUT.png --width 120 --charset ascii
    convert.py IN --out OUT.mp4 --width 160 --cut auto
    convert.py IN --probe                     # JSON: size, frames, animated?

ffmpeg decodes and scales (it handles every format we care about, including
animated gif and webp), numpy does the pixel -> character mapping, and Pillow
renders characters back into pixels through a glyph atlas built once. That
last step is why a 2000-frame video is not 2000x slower than one frame.
"""

import argparse
import json
import time
import os
import shutil
import subprocess
import sys

try:
    import numpy as np
except ImportError:
    sys.stderr.write("biteglyph: numpy is not installed — sudo pacman -S python-numpy\n")
    sys.exit(1)

if not shutil.which("ffmpeg"):
    sys.stderr.write("biteglyph: ffmpeg is not installed — sudo pacman -S ffmpeg\n")
    sys.exit(1)


# ── character ramps, darkest → brightest ──────────────────────────────────────
# Same set bitecam uses, so a look you like in one carries to the other.
RAMPS = {
    "ascii":   " .:-=+*#%@",
    "dense":   " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@",
    "blocks":  " ░▒▓█",
    "minimal": " .*#",
    "solid":   "██",
    "bite":    " .:-=BITE#%@",
}

# A terminal cell is about twice as tall as it is wide, so the pixel grid has to
# be squashed vertically or everything comes out stretched.
CELL_ASPECT = 2.0


def die(msg, hint=""):
    sys.stderr.write("biteglyph: %s\n" % msg)
    if hint:
        sys.stderr.write("  %s\n" % hint)
    sys.exit(1)


# ── probing ───────────────────────────────────────────────────────────────────

def probe(path):
    """Size, frame count and duration. Never raises — callers get a dict."""
    info = {"width": 0, "height": 0, "frames": 1, "fps": 0.0,
            "animated": False, "has_alpha": False}
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height,nb_frames,r_frame_rate,pix_fmt",
             "-of", "json", path],
            capture_output=True, text=True, timeout=20).stdout
        st = json.loads(out)["streams"][0]
        info["width"] = int(st.get("width") or 0)
        info["height"] = int(st.get("height") or 0)
        pix = st.get("pix_fmt", "") or ""
        info["has_alpha"] = "a" in pix.replace("yuva", "a").replace("rgba", "a") \
            or pix in ("rgba", "bgra", "yuva420p", "argb", "abgr", "pal8")
        rate = st.get("r_frame_rate", "0/1") or "0/1"
        num, _, den = rate.partition("/")
        try:
            info["fps"] = float(num) / float(den or 1)
        except (ValueError, ZeroDivisionError):
            info["fps"] = 0.0
        n = st.get("nb_frames")
        info["frames"] = int(n) if n and n.isdigit() else 0
    except Exception:
        pass

    # nb_frames is missing for plenty of formats (animated webp especially), so
    # counting packets is the fallback. It is slower but it is never wrong.
    if info["frames"] in (0, 1):
        try:
            out = subprocess.run(
                ["ffprobe", "-v", "error", "-select_streams", "v:0",
                 "-count_packets", "-show_entries", "stream=nb_read_packets",
                 "-of", "csv=p=0", path],
                capture_output=True, text=True, timeout=30).stdout.strip()
            if out.isdigit():
                info["frames"] = int(out)
        except Exception:
            pass
    info["frames"] = max(1, info["frames"])
    info["animated"] = info["frames"] > 1
    return info


def grid_for(src_w, src_h, cols):
    """Character grid that keeps the source's proportions."""
    if src_w <= 0 or src_h <= 0:
        return max(8, cols), max(4, cols // 2)
    rows = int(round(cols * (src_h / src_w) / CELL_ASPECT))
    return max(8, cols), max(4, rows)


# ── decoding ──────────────────────────────────────────────────────────────────

def decode(path, cols, rows, limit=0, fps=0.0):
    """Yield (rows, cols, 4) RGBA frames, already scaled to the character grid.

    Scaling in ffmpeg rather than numpy matters: it is C, it picks a decent
    filter, and it means Python only ever touches one value per character cell.
    """
    vf = []
    if fps > 0:
        vf.append("fps=%g" % fps)
    vf.append("scale=%d:%d:flags=lanczos" % (cols, rows))
    vf.append("format=rgba")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
           "-vf", ",".join(vf)]
    if limit > 0:
        cmd += ["-frames:v", str(limit)]
    cmd += ["-f", "rawvideo", "-pix_fmt", "rgba", "-"]

    n = cols * rows * 4
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, bufsize=0)
    try:
        while True:
            buf = bytearray()
            while len(buf) < n:
                chunk = proc.stdout.read(n - len(buf))
                if not chunk:
                    break
                buf += chunk
            if len(buf) < n:
                break
            yield np.frombuffer(bytes(buf), np.uint8).reshape(rows, cols, 4)
    finally:
        try:
            proc.stdout.close()
        except Exception:
            pass
        err = b""
        try:
            err = proc.stderr.read() or b""
        except Exception:
            pass
        proc.wait()
        if proc.returncode not in (0, None) and err:
            sys.stderr.write("biteglyph: ffmpeg: %s\n"
                             % err.decode("utf-8", "replace").strip().splitlines()[-1])


# ── background removal ────────────────────────────────────────────────────────

def cut_background(rgba, mode, tol=32):
    """Return an alpha mask (rows, cols) where 0 = drop the cell.

    Three tiers, cheapest first, because they suit different sources:

      alpha    the file already says what is transparent — always right
      flood    flood-fill inward from the corners; ideal for logos and icons
               sitting on a flat colour, useless on a photo
      grabcut  OpenCV's foreground extraction with a centred rectangle hint.
               Handles photos, costs a dependency, and will not be perfect on
               hair or fine edges — it is a good guess, not a matte.
    """
    rows, cols = rgba.shape[:2]
    if mode in ("off", "", None):
        return np.full((rows, cols), 255, np.uint8)

    alpha = rgba[:, :, 3]
    if mode in ("auto", "alpha") and alpha.min() < 250:
        return alpha                      # the source already knows
    if mode == "alpha":
        return np.full((rows, cols), 255, np.uint8)

    if mode in ("auto", "flood"):
        rgb = rgba[:, :, :3].astype(np.int16)
        corners = np.array([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]],
                           dtype=np.int16)
        # Only treat it as a flat backdrop if the corners actually agree.
        if corners.ptp(axis=0).max() <= tol:
            bg = corners.mean(axis=0)
            close = (np.abs(rgb - bg).max(axis=2) <= tol)
            mask = _flood_from_edges(close)
            return np.where(mask, 0, 255).astype(np.uint8)
        if mode == "flood":
            return np.full((rows, cols), 255, np.uint8)

    if mode in ("auto", "grabcut"):
        try:
            import cv2
        except ImportError:
            if mode == "grabcut":
                die("background=grabcut needs OpenCV",
                    "sudo pacman -S python-opencv opencv")
            return np.full((rows, cols), 255, np.uint8)
        # grabCut is slow and pointless on a tiny grid, so it runs on a larger
        # copy and the result is scaled back down to the character grid.
        w = max(cols, 160)
        h = max(rows, int(w * rows / max(cols, 1)))
        big = cv2.resize(rgba[:, :, :3], (w, h), interpolation=cv2.INTER_LINEAR)
        m = np.zeros((h, w), np.uint8)
        rect = (int(w * 0.08), int(h * 0.08), int(w * 0.84), int(h * 0.84))
        try:
            bgd = np.zeros((1, 65), np.float64)
            fgd = np.zeros((1, 65), np.float64)
            cv2.grabCut(big, m, rect, bgd, fgd, 3, cv2.GC_INIT_WITH_RECT)
            fg = np.where((m == cv2.GC_FGD) | (m == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
            return cv2.resize(fg, (cols, rows), interpolation=cv2.INTER_NEAREST)
        except Exception:
            pass

    return np.full((rows, cols), 255, np.uint8)


def _flood_from_edges(close):
    """Cells matching the backdrop AND reachable from an edge, iteratively.

    Matching the colour is not enough on its own — a white shape inside the
    subject would vanish too. Only what connects to the border is background.
    """
    rows, cols = close.shape
    reach = np.zeros((rows, cols), bool)
    reach[0, :] |= close[0, :]
    reach[-1, :] |= close[-1, :]
    reach[:, 0] |= close[:, 0]
    reach[:, -1] |= close[:, -1]
    for _ in range(rows + cols):
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= close
        if np.array_equal(grown, reach):
            break
        reach = grown
    return reach


# ── pixels → characters ───────────────────────────────────────────────────────

def to_cells(rgba, ramp, invert=False, contrast=1.0, cut="off"):
    """-> (index grid, rgb grid, visible mask)."""
    rgb = rgba[:, :, :3]
    lum = (rgb[:, :, 0].astype(np.uint16) * 77 +
           rgb[:, :, 1].astype(np.uint16) * 150 +
           rgb[:, :, 2].astype(np.uint16) * 29) >> 8

    if contrast != 1.0:
        centred = (lum.astype(np.float32) - 128.0) * float(contrast) + 128.0
        lum = np.clip(centred, 0, 255).astype(np.uint16)

    n = len(ramp)
    idx = (lum * (n - 1) // 255).astype(np.uint8)
    if invert:
        idx = (n - 1) - idx

    mask = cut_background(rgba, cut)
    idx = np.where(mask < 128, 0, idx)     # dropped cells become the blank glyph
    return idx, rgb, mask


def to_text(idx, rgb, ramp, colour=True):
    """ANSI text — what you would `cat` in a terminal."""
    rows, cols = idx.shape
    lines = []
    if not colour:
        for y in range(rows):
            lines.append("".join(ramp[i] for i in idx[y]))
        return "\n".join(lines)
    q = rgb & 0xF8                        # quantise so runs of colour collapse
    for y in range(rows):
        parts = []
        prev = None
        for x in range(cols):
            c = tuple(int(v) for v in q[y, x])
            if c != prev:
                parts.append("\x1b[38;2;%d;%d;%dm" % c)
                prev = c
            parts.append(ramp[idx[y, x]])
        parts.append("\x1b[0m")
        lines.append("".join(parts))
    return "\n".join(lines)


class Rasteriser:
    """Character grid -> RGB pixels, through a glyph atlas rendered once.

    Building the atlas per frame would dominate everything else; built once, a
    whole frame is a single numpy indexing operation, so an animation costs
    about the same per frame as a still.
    """

    def __init__(self, cols, rows, ramp, cell):
        from PIL import Image, ImageDraw, ImageFont
        self.cw = cell
        self.ch = cell * 2                # match the terminal's cell shape
        self.w = (cols * self.cw) // 2 * 2     # even dimensions for h264
        self.h = (rows * self.ch) // 2 * 2
        self.cols, self.rows, self.ramp = cols, rows, ramp

        font = self._font(ImageFont)
        atlas = np.zeros((len(ramp), self.ch, self.cw), np.uint8)
        for i, ch in enumerate(ramp):
            img = Image.new("L", (self.cw, self.ch), 0)
            d = ImageDraw.Draw(img)
            try:
                bb = d.textbbox((0, 0), ch, font=font)
                d.text(((self.cw - (bb[2] - bb[0])) / 2 - bb[0],
                        (self.ch - (bb[3] - bb[1])) / 2 - bb[1]), ch, 255, font=font)
            except Exception:
                d.text((0, 0), ch, 255, font=font)
            atlas[i] = np.asarray(img, np.uint8)
        self.atlas = atlas

    def _font(self, ImageFont):
        want = int(self.ch * 0.8)
        try:
            p = subprocess.run(["fc-match", "-f", "%{file}", "monospace"],
                               capture_output=True, text=True, timeout=5).stdout.strip()
            if p:
                return ImageFont.truetype(p, want)
        except Exception:
            pass
        for p in ("/usr/share/fonts/TTF/JetBrainsMonoNLNerdFontMono-Regular.ttf",
                  "/usr/share/fonts/TTF/DejaVuSansMono.ttf"):
            if os.path.exists(p):
                return ImageFont.truetype(p, want)
        return ImageFont.load_default()

    def coverage(self, idx):
        """Per-pixel glyph coverage — the honest alpha for a cut-out png.

        Deriving transparency from the rendered colour instead punches holes
        through any glyph that happens to be drawn in a very dark colour, which
        is most of them on a dark source.
        """
        m = self.atlas[idx]
        m = m.transpose(0, 2, 1, 3).reshape(self.rows * self.ch, self.cols * self.cw)
        return m[:self.h, :self.w]

    def frame(self, idx, rgb, colour=True, bg=(0, 0, 0)):
        mask = self.atlas[idx]
        col = rgb.astype(np.uint16) if colour else \
            np.full((self.rows, self.cols, 3), 210, np.uint16)
        f = (mask[:, :, :, :, None].astype(np.uint16) * col[:, :, None, None, :]) // 255
        f = f.astype(np.uint8).transpose(0, 2, 1, 3, 4)
        f = f.reshape(self.rows * self.ch, self.cols * self.cw, 3)
        f = f[:self.h, :self.w]
        if bg != (0, 0, 0):
            back = np.array(bg, np.uint8)
            lit = f.max(axis=2, keepdims=True) > 0
            f = np.where(lit, f, back)
        return f


# ── writers ───────────────────────────────────────────────────────────────────

def write_png(path, frames, rast, colour, bg, alpha_bg):
    from PIL import Image
    idx, rgb, _ = frames[0]
    px = rast.frame(idx, rgb, colour=colour, bg=bg)
    img = Image.fromarray(px, "RGB")
    if alpha_bg:
        # A logo wants a transparent backdrop, not a black rectangle. Alpha
        # comes from where glyphs actually landed, not from how bright they
        # came out — see Rasteriser.coverage.
        arr = np.dstack([px, rast.coverage(idx)])
        img = Image.fromarray(arr, "RGBA")
    img.save(path)
    return img.size


def write_text(path, frames, ramp, colour):
    idx, rgb, _ = frames[0]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(to_text(idx, rgb, ramp, colour) + "\n")


def write_cast(path, frames, ramp, colour, fps):
    """asciinema v2 — replays as real, selectable text."""
    rows, cols = frames[0][0].shape
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"version": 2, "width": cols, "height": rows,
                             "timestamp": 0, "env": {"TERM": "xterm-256color"}}) + "\n")
        for i, (idx, rgb, _) in enumerate(frames):
            body = "\x1b[H" + to_text(idx, rgb, ramp, colour)
            fh.write(json.dumps([round(i / max(fps, 1.0), 3), "o", body]) + "\n")


def write_video(path, frames, rast, colour, bg, fps, fmt):
    """mp4 or gif, encoded straight from the rasterised frames."""
    tmp = path if fmt == "mp4" else path + ".mp4"
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", "%dx%d" % (rast.w, rast.h), "-r", str(max(fps, 1)), "-i", "-",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-pix_fmt", "yuv420p", tmp]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for idx, rgb, _ in frames:
            p.stdin.write(rast.frame(idx, rgb, colour=colour, bg=bg).tobytes())
        p.stdin.close()
    except BrokenPipeError:
        pass
    p.wait()
    if p.returncode not in (0, None):
        err = (p.stderr.read() or b"").decode("utf-8", "replace").strip()
        die("encoding failed", err.splitlines()[-1] if err else "")

    if fmt == "gif":
        # Two-pass palette, or it looks like 1998.
        pal = path + ".png"
        try:
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                            "-i", tmp, "-vf", "palettegen", pal],
                           check=True, timeout=180)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                            "-i", tmp, "-i", pal, "-lavfi", "paletteuse", path],
                           check=True, timeout=300)
        finally:
            for f in (pal, tmp):
                try:
                    os.remove(f)
                except OSError:
                    pass



# ── serve mode (what the QML front-end talks to) ──────────────────────────────
#
# QML can read and write files but cannot start a process, so the GUI and the
# engine talk through a directory: the window writes request.json, this loop
# notices, renders, and writes status.json back. Same trick bitemuseum uses to
# get its data in, just in both directions.

def _render_preview(req, rundir):
    path = req.get("input") or ""
    if not path or not os.path.exists(path):
        return {"ok": False, "error": "no such file"}
    info = probe(path)
    cols, rows = grid_for(info["width"], info["height"],
                          max(8, min(int(req.get("width", 100)), 400)))
    ramp = RAMPS.get(req.get("charset", "ascii"), RAMPS["ascii"])
    colour = bool(req.get("colour", True))

    frame_no = int(req.get("frame", 0))
    got = None
    for i, rgba in enumerate(decode(path, cols, rows, 0, 0.0)):
        if i < frame_no:
            continue
        got = rgba
        break
    if got is None:
        return {"ok": False, "error": "could not decode a frame"}

    cells = to_cells(got, ramp, bool(req.get("invert", False)),
                     float(req.get("contrast", 1.0)), req.get("cut", "off"))
    # The preview is drawn small on purpose: it only has to look right in a
    # window, and a big cell size makes every keystroke feel slow.
    rast = Rasteriser(cols, rows, ramp, 8)
    from PIL import Image
    px = rast.frame(cells[0], cells[1], colour=colour)
    tmp = os.path.join(rundir, "preview.tmp.png")
    out = os.path.join(rundir, "preview.png")
    Image.fromarray(px, "RGB").save(tmp)
    os.replace(tmp, out)          # atomic, so QML never loads a half-written file
    return {"ok": True, "cols": cols, "rows": rows,
            "frames": info["frames"], "animated": info["animated"],
            "src_w": info["width"], "src_h": info["height"]}


def _run_export(req, rundir):
    """Re-invoke ourselves so an export is exactly the CLI path, not a copy."""
    out = req.get("export_path") or ""
    if not out:
        return {"ok": False, "error": "no output path"}
    out = os.path.expanduser(out)
    cmd = [sys.executable, os.path.abspath(__file__), req.get("input", ""),
           "--out", out,
           "--width", str(int(req.get("width", 120))),
           "--charset", req.get("charset", "ascii"),
           "--colour", "on" if req.get("colour", True) else "off",
           "--invert", "on" if req.get("invert", False) else "off",
           "--contrast", str(float(req.get("contrast", 1.0))),
           "--cut", req.get("cut", "off"),
           "--cell", str(int(req.get("cell", 10))),
           "--transparent", "on" if req.get("transparent", False) else "off"]
    if req.get("fps"):
        cmd += ["--fps", str(float(req["fps"]))]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr.strip().splitlines() or ["failed"])[-1]}
    return {"ok": True, "saved": out}


def serve(rundir):
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
                    if req.get("export_path"):
                        res = _run_export(req, rundir)
                    else:
                        res = _render_preview(req, rundir)
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


# ── cli ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(prog="biteglyph", add_help=True)
    ap.add_argument("input", nargs="?", default="")
    ap.add_argument("--out", "-o", help="output file; the extension picks the format")
    ap.add_argument("--width", "-w", type=int, default=120, help="characters across")
    ap.add_argument("--charset", "-c", default="ascii", choices=sorted(RAMPS))
    ap.add_argument("--colour", "--color", dest="colour", default="on",
                    choices=("on", "off"))
    ap.add_argument("--invert", default="off", choices=("on", "off"))
    ap.add_argument("--contrast", type=float, default=1.0)
    ap.add_argument("--cut", default="off",
                    choices=("off", "auto", "alpha", "flood", "grabcut"),
                    help="background removal")
    ap.add_argument("--cell", type=int, default=10, help="pixels per character when rendering")
    ap.add_argument("--fps", type=float, default=0.0, help="0 = keep the source rate")
    ap.add_argument("--max-frames", type=int, default=600)
    ap.add_argument("--frame", type=int, default=0, help="still: which frame to take")
    ap.add_argument("--transparent", default="off", choices=("on", "off"),
                    help="png only: make the background see-through")
    ap.add_argument("--probe", action="store_true", help="print JSON and exit")
    ap.add_argument("--serve", metavar="DIR", help="run as the QML front-end's engine")
    a = ap.parse_args()

    if a.serve:
        return serve(a.serve)

    if not os.path.exists(a.input):
        die("no such file: %s" % a.input)

    info = probe(a.input)
    if a.probe:
        print(json.dumps(info))
        return 0

    cols, rows = grid_for(info["width"], info["height"], max(8, a.width))
    ramp = RAMPS[a.charset]
    colour = a.colour == "on"
    fmt = (os.path.splitext(a.out)[1].lstrip(".").lower() if a.out else "txt") or "txt"
    still = fmt in ("png", "txt")

    # A still only needs one frame, so do not decode a whole film for it.
    limit = 1 if (still and not info["animated"]) else a.max_frames
    want_from = a.frame if still else 0

    frames = []
    for i, rgba in enumerate(decode(a.input, cols, rows, 0 if still else limit,
                                    a.fps if not still else 0.0)):
        if still and i < want_from:
            continue
        frames.append(to_cells(rgba, ramp, a.invert == "on", a.contrast, a.cut))
        if still or len(frames) >= limit:
            break
    if not frames:
        die("could not read any frames from %s" % a.input,
            "is it really an image or a video?")

    if not a.out:
        print(to_text(frames[0][0], frames[0][1], ramp, colour))
        return 0

    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    fps = a.fps or info["fps"] or 12.0

    if fmt == "txt":
        write_text(a.out, frames, ramp, colour)
    elif fmt == "cast":
        write_cast(a.out, frames, ramp, colour, fps)
    elif fmt in ("png", "mp4", "gif"):
        rast = Rasteriser(cols, rows, ramp, max(4, a.cell))
        if fmt == "png":
            write_png(a.out, frames, rast, colour, (0, 0, 0), a.transparent == "on")
        else:
            write_video(a.out, frames, rast, colour, (0, 0, 0), fps, fmt)
    else:
        die("don't know how to write '%s'" % fmt,
            "use .png .txt .cast .mp4 or .gif")

    n = len(frames)
    sys.stderr.write("biteglyph: %s  %dx%d chars  %d frame%s\n"
                     % (a.out, cols, rows, n, "" if n == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
