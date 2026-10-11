<div align="center">

# 📦 Releases

### Every BITE-OS build and what changed · `// THE SYSTEM BIT YOU`

</div>

Newest first. Download the current ISO from the **[README](README.md#-download)**;
already installed? `SUPER+U` updates you in place.

---

## ◈ What's new in the next build

> Not in an ISO yet — this is what the next build ships. Once it's released,
> `SUPER+U` brings it to existing installs too.

**BITE-OS gets its own look for the shell.** A new **BITE-OS Style** tab in settings
(`SUPER+H`) dresses serpantinum in glitch. Popups open with a **blast** — an
RGB-split outline and glitch slivers exploding outward while brackets slam onto the
corners — or a neon **scan** or a burst of **hex**, and they can **drop**, **zoom**,
**flip** in 3D, **unfold** like an old TV or **swing** open. Notifications **bite**
their way onto the screen: the card splits along a row of teeth and the jaws slam
shut with a glitch (or they slice, tune in through static, or build out of pixels).
Every effect has versions to pick from and an Off / Subtle / Loud switch.

**Two new lock screens.** **Dedsec** puts a HUD in the corners, streams hex down the
edges, glitches the clock and flashes a red `ACCESS DENIED` when the password is
wrong. **Matrix** rains green code across the whole screen. Unlocking **unzips** the
screen from the middle while the HUD decrypts — or switches it off like a CRT.

**serpantinum is updated to 2.2.7**, merged the same way as before so every BITE-OS
change is kept: lyrics in the music popup and on the desktop, a right-click desktop
menu, widget presets, search in settings, an emoji picker and 11 new languages.

**Fixes**
- On a Hebrew system the shell no longer flips itself right-to-left while its text
  stays English.
- Icons sit centred again, and the RAM icon is no longer an empty box.

## ◈ What's new in 20260915

**Caelestia is on stable 2.4.0 — with every BITE-OS change kept.** The rice moves off
the old pinned git build to the 2.4.0 release (plus libcava 1.0 and qt6-m3shapes).
Like the serpantinum updates, this was a three-way merge: upstream 2.4.0 as the base,
all 27 BITE-OS patches re-applied on top — the frosted lock screen and its fetch,
low-battery toasts, video-wallpaper thumbnails, clickable panels over fullscreen.
Upstream removed the old control center, so the rice switcher now lives in **Nexus**
as a *Rice & shell* page.

**serpantinum is updated to 2.1.5**, merged the same way: new battery and usage
widgets, dock layer and scale options, and bluetooth crash fixes upstream, with the
BITE-OS tabs and patches carried over.

**New BITE-OS desktop widgets.** The widget editor has a **BITE-OS** tab on its top
edge that opens a second row: a **dedsec monitor** (terminal, bars or hex look),
**matrix rain** (katakana, binary or glitch), a **rice switcher**, **rice saves**,
**widget layouts**, a **workspace map** and a live **process top**. Each one's
settings (how many saves, workspaces or processes it shows) are in the new
**Widgets** tab in settings.

**Widget saves and undo.**
- Save your widget layout under a name and load it back later, or turn on
  auto-save. Saves live outside the rice vault, so restoring or switching a rice
  never wipes the list.
- Every widget change is recorded, and the last one can be undone. If widgets
  suddenly disappear, a backup of the layout is kept automatically.

**Super+U now updates the rice too.** Rice changes used to reach only new installs,
because they ship in `/etc/skel`. Now `SUPER+U` also brings each release's rice into
your home — but only the files you never edited; anything you changed is kept. This
needs an install from this ISO or newer (see [Updating](README.md#-updating)).

**Fixes**
- Logout from serpantinum works again on plain Hyprland sessions.
- The rice list shows your current save on top with real save times, and saving
  an unchanged rice no longer pushes older saves out of the list.
- Settings sidebar: the BITE-OS, Keybinds and Widgets tabs have their buttons back,
  and About opens About.
- Icons sit centred again; media previous/next keys and `SUPER+M` added.
- NVIDIA driver 615.71.09.

## ◈ What's new in 20260910

**serpantinum is updated to 2.1.4 — without losing the BITE-OS changes.** Upstream's
updater is still disabled (it re-runs `install.sh`, which removes `quickshell-git`,
wipes the SDDM theme and overwrites the rice), so this update was a three-way merge
instead: the new upstream as the base, every BITE-OS patch re-applied on top. Of the
23 files BITE-OS changes, 11 were untouched upstream and carried over as-is, 10 merged
automatically, and two were rebuilt by hand around upstream's restructuring — including
the About page's update button, which still routes to the BITE-OS updater rather than
upstream's installer. Every added line was checked back against the merged result.

**New from upstream:** a dock (with its own settings tab), the fix for the edge panel
that could be dragged off screen, notification sounds, Portuguese, bar autohide
(`SUPER+A`), and a round of dock, launcher, bluetooth, Wi-Fi-after-suspend and config
race-condition fixes.

**The system-monitor pills read cleanly again.** They draw their liquid fill behind the
text, and the light copy of the text was never clipped to the part above the liquid —
so inside the fill a 75%-opaque dark icon sat on top of a light one and turned into a
smudge that looked like a missing glyph. Each half now gets one ink.

## ◈ What's new in 20260909

**The login screen is new.** `bite-os-fluid` replaces the old greeter as the
default. The original theme still ships beside it — change one word in
`/etc/sddm.conf.d/10-bite-os.conf` and you're back on it.

**It moves like the shell does.** The motion is lifted from serpantinum's overlay
family — the screenshot region-select, the quickactions panel, the network and
volume popups — not from its lock screen. That means `OutExpo` over 350–600ms,
geometry that glides instead of fading, and animations that are switched *off*
during direct manipulation so nothing chases a moving layout. A region-select box
follows your mouse and Tab between the account, the password, the session and the
power buttons, dimming everything outside it and reading out its own size.

**The password field is a bottle.** Hidden characters float as dots inside the
liquid, riding the wave. Press reveal and they surface left to right, one at a
time: the dot swells into a bubble, rises, pops clear of the box, and a green
character drifts back down onto the surface. Turn reveal off and the box is washed
out by the same five-layer bezier wipe that opens the `SUPER+L` lock screen. Delete
a character and the bottle tips right — the character slides down the liquid to the
low lip and falls off the edge. Hold backspace and it stays tipped until you stop.
Leave it alone with liquid in it and soap bubbles drift up at random intervals.

**It tells you about the machine before you log in.** Liquid-fill gauges for CPU,
RAM, the time (the fill is how much of the day has gone) and the keyboard layout.
The greeter has no process API, so CPU and RAM come from `/proc/stat` and
`/proc/meminfo` read through QML's `XMLHttpRequest` — Qt6 blocks `file://` reads
outright, so `GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1` in the SDDM config
hands it to the greeter. Without
it those two gauges read `n/a` and nothing else changes.

**Switching account and session is direct.** Click your name and the avatar shrinks
while a compact account list opens over the top — it's a separate layer, so nothing
below it moves. Arrows either side of the session name cycle sessions, and a
settings panel behind the gear covers reveal style and speed, the ambient effects,
a lite mode that kills every continuous repaint, and the gauges and dimming.

**Keyboard layouts come from your system, not an assumption.** They're read from
`/etc/vconsole.conf`, then xorg's `00-keyboard.conf`, then `/etc/default/keyboard`
— first file that answers wins — so the gauge shows whatever the machine is
actually configured for, along with the key combination that toggles it. If none of
them answer it shows `--` rather than inventing a layout.

Two things worth knowing. SDDM's `SessionModel` returns `undefined` for
`Qt.DisplayRole`; the session name lives at `Qt.UserRole + 4`, and using the
obvious one leaves the label blank. And SDDM's `KeyboardModel` (X11/XKB) reports
`enabled=false` with zero layouts when the greeter runs in test mode inside a
Wayland session, so the theme falls back to reading the config files and XKB's own
group toggle. On the real X11 greeter it may expose layouts directly; the theme
uses them when it does. And SDDM reads its config once, when the daemon starts —
changing the theme needs a reboot, not a logout.

## ◈ What's new in 20260907

The second desktop changed. **ilyamiro is gone; serpantinum replaces it.** BITE-OS
still ships two complete desktops — **caelestia** (default) and **serpantinum** —
swapped with one keypress, same as before.

**serpantinum 2.1.2 is the new second rice.** A Qt6/QuickShell shell with a
movable-widget desktop, a live audio visualiser, weather, clipboard, an equaliser
and its own settings GUI. It handles video wallpapers itself, so the old
`awww` + `mpvpaper` stack no longer runs underneath it decoding a video into a
surface nothing can see.

**Two BITE-OS tabs in its settings.** A **BITE-OS** tab saves the current rice into
the vault, rolls back the last swap, and switches between rices. A **Keybinds** tab
lists every shortcut and lets you edit the modifiers, key and command in place —
it writes `settings.json`, so Hyprland regenerates and reloads on its own. Every
write is snapshotted and refuses to commit invalid JSON, because that file owns
every shortcut you have.

**Your look now saves itself.** Widget positions live in a different place from the
rest of the settings, so a rice swap used to revert them. Both are mirrored into
the vault as you change them — move a widget, swap rices, come back, it's there.

**Workspace switching works on stock Hyprland.** Upstream sends Lua
(`hl.dsp.focus(...)`) to `hyprctl`, which only works with its author's own
Lua-based Hyprland config; plain hyprlang answers `Invalid dispatcher` and nothing
moves. The keybinds, the bar's workspace pills and the CLI all use native
dispatchers now.

**The shell's updater can't wipe your install.** It ran `curl | bash` of upstream's
installer, which removes `quickshell-git` (caelestia needs it too), wipes the SDDM
theme and overwrites your kitty/cava/fastfetch configs. It now runs the BITE-OS
updater, the same thing `SUPER+U` does, and the upstream update check and telemetry
are off.

**Media buttons tell you the truth.** Skip/previous ignored what the player actually
supports, so a dead click looked like broken software. They dim when the player
can't honour them — greyed out means nothing queued, not a bug.

**quickshell rebuilt for Qt 6.11.2.** The shipped build was compiled in May against
an older Qt. Quickshell links Qt's private API, which has no stable ABI, so on a
current system **neither** shell would start — it failed with an undefined-symbol
error. Rebuilt from the same pinned commit against the current Qt, so caelestia
still sees the API it expects.

## ◈ What's new in 20260906

A wallpaper and desktop-stability build. Nothing was redesigned — things that had
been quietly broken for a while now work.

**The wallpaper picker applies the picture you pick.** Arch renamed the `swww`
package to `awww`, and the picker was still calling `swww`. Because it kills the
video wallpaper *before* painting the new one, choosing an image killed your video
and then painted nothing — leaving whatever was on screen before, which looked like
the picker ignoring you and reverting to the default. Every call now targets `awww`.

**Video wallpapers survive a reboot.** The picker caches a still thumbnail for
videos, so nothing on disk remembered the actual video path and every boot restored
a frozen frame that only came alive if you re-picked it. The real source path is now
recorded and replayed, so a video comes back as a video.

**Video wallpapers stop duplicating.** Tearing down `mpvpaper` sent `SIGTERM` and
immediately spawned a replacement without waiting, so the old process could outlive
the new one. Worse, a paused (`SIGSTOP`ped) wallpaper can never act on `SIGTERM` at
all, so it became an unkillable ghost. Teardown is now resume → terminate → wait →
kill, and rapid clicks queue instead of stacking.

**Switching rices stops stacking bars and shells.** The settings watcher had no
single-instance guard and regenerated `autostart.conf` in place, so two copies could
interleave and write every startup entry *twice* — including the shell and the
watcher itself. Each login then started two of each, which doubled the file again:
a compounding loop that ended in several bars drawn over each other. The watcher is
now single-instance and generates the file atomically.

**Spamming the rice-swap bind is safe.** Every press used to run a full concurrent
swap, with kills racing launches. Swapping is now single-instance, waits for the new
shell to actually paint rather than merely exist, and settles before releasing — so
extra presses are dropped instead of melting the session. The `toggle` binds also
resolve directly instead of re-invoking the script.

**The swap chord no longer opens the launcher on top of you.** Caelestia opens its
launcher on Super *release* unless a suppression flag is set — but that flag lives in
the shell process, so killing the shell mid-chord reset it. Releasing Super after a
swap then looked like a bare Super tap and opened a full-screen blurred drawer that
grabbed input. The flag is re-armed on the fresh shell.

## ◈ What's new in 20260903

A bug-fix build. Nothing was redesigned — things that were quietly broken now work.

**Weather actually shows the weather.** The top bar, lock screen and calendar sat on
`--°` regardless of conditions. Two faults stacked: half the weather icons had lost
their nerd-font glyphs, and the parser called `.trim()` on the whole response before
splitting it, so a blank icon line shifted every field out of place and the reading was
discarded. Both fixed — and it no longer depends on an API key at all.

**You can choose which user to log in as.** The greeter was locked to the last account
that logged in, with no way to switch. Click the username (or press ↑/↓) to cycle
accounts. Single-user installs look and behave exactly as before.

**Lock screen: Switch User.** New entry in the power menu. It hands off to the display
manager, so your session stays locked and intact behind the new greeter.

**Keyboard layouts stopped eating themselves.** Adding a language could silently append
a duplicate and leave a malformed entry that broke layout switching. The layout list is
now normalised everywhere it's read or written.

**Blank icons fixed.** Some system apps showed a placeholder square instead of an icon —
it looked random but was deterministic: the rice sets `QT_QPA_PLATFORMTHEME=qt6ct`, and
with no qt6ct config present Qt was handed no icon theme at all, so every generic icon
name failed to resolve. Fresh installs now ship a correct config, and **`bite-icons-fix`**
repairs it on an existing system (`bite-icons-fix --check` to inspect without changing
anything).

**A fresh install now boots with a top bar.** First-boot autostart launched the popup
overlay instead of the shell entrypoint, so a brand-new install came up with no bar and
no floating widgets until something restarted the shell.

**caelestia rice: the browser key works.** It pointed at a browser that isn't installed,
so the bind did nothing. It opens Firefox now.

Links and credits across the project now point at **GLITCH-BITE-404** and the GitHub
repo; the old handle's URLs were dead.
