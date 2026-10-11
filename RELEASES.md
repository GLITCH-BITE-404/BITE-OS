<div align="center">

# 📦 Releases

### Every BITE-OS build and what changed · `// THE SYSTEM BIT YOU`

</div>

Newest first. Download the current ISO from the **[README](README.md#-download)**;
already installed? `SUPER+U` updates you in place.

---

## 1.1.33 — `20261011`

**Added**
- **BITE-OS Style tab** in settings (`SUPER+H`) — BITE-OS's own glitch look for the shell, with an Off / Subtle / Loud switch
- Popup effects: **Blast** (RGB-split outline and glitch slivers explode outward), **Scan**, **Hex**
- Popup animations: **Drop**, **Zoom**, **Flip** (3D), **Unfold** (old-TV), **Swing**
- Notifications that **bite** onto the screen — the card splits along a row of teeth and the jaws slam shut — plus **Slice**, **Static** and **Pixel**
- New lock screens: **Dedsec** (HUD, hex streams, glitching clock, red `ACCESS DENIED`) and **Matrix** (rain across the whole screen)
- Unlock effects: **Unzip** (the screen tears open while the HUD decrypts) and **CRT off**
- serpantinum **2.2.7**: lyrics on the desktop and in the music popup, right-click desktop menu, widget presets, search in settings, emoji picker, 11 new languages

**Fixed**
- The shell no longer flips right-to-left on Hebrew systems while its text stays English
- Icons sit centred again, and the RAM icon is no longer an empty box

---

## 1.1.31 — `20260915`

**Added**
- Caelestia on stable **2.4.0** with all 27 BITE-OS patches kept; the rice switcher moved to **Nexus → Rice & shell**
- serpantinum **2.1.5**: new battery and usage widgets, dock layer and scale options
- **BITE-OS desktop widgets**: dedsec monitor, matrix rain, rice switcher, rice saves, widget layouts, workspace map, process top — plus a **Widgets** settings tab
- **Widget saves** (named saves and auto-save) and **undo** for widget changes, with automatic layout backups
- `SUPER+U` now updates the **rice** too — only the files you never edited
- Media previous/next keys and `SUPER+M`

**Fixed**
- Logout from serpantinum on plain Hyprland sessions
- The rice list shows your current save on top with real save times; saving an unchanged rice no longer pushes older saves out
- Settings sidebar: the BITE-OS, Keybinds and Widgets tabs are back, and About opens About
- Centred icons
- NVIDIA driver 615.71.09

---

## `20260910`

**Added**
- serpantinum **2.1.4**, merged with every BITE-OS change kept
- A dock with its own settings tab, notification sounds, Portuguese, bar autohide (`SUPER+A`)

**Fixed**
- System-monitor pills read cleanly again (no more smudged icon inside the fill)
- Edge panel could be dragged off screen
- Dock, launcher, bluetooth, Wi-Fi-after-suspend and config race-condition fixes
- The shell's update button still runs the BITE-OS updater, never upstream's installer

---

## `20260909`

**Added**
- **New login screen**, `bite-os-fluid` — the old theme still ships beside it
- A liquid "bottle" password field: characters float as dots, bubble up when revealed, slide off when deleted
- Live CPU, RAM, time-of-day and keyboard-layout gauges before you log in
- Account switcher, session arrows and a settings panel (reveal style, effects, lite mode)

**Fixed**
- Keyboard layouts are read from your system config instead of assumed

---

## `20260907`

**Added**
- **serpantinum** replaces ilyamiro as the second desktop (caelestia stays the default)
- **BITE-OS** settings tab: save the rice, roll back, switch rices
- **Keybinds** settings tab: edit any shortcut in place, with snapshots and JSON checks
- Widget positions save themselves into the rice vault

**Fixed**
- Workspace switching on stock Hyprland
- The shell's updater can no longer wipe your install — it runs the BITE-OS updater
- Media buttons dim when the player can't skip
- quickshell rebuilt for Qt 6.11.2 (neither shell would start before)

---

## `20260906`

**Fixed**
- The wallpaper picker applies the picture you pick (`swww` → `awww`)
- Video wallpapers come back as videos after a reboot
- Video wallpapers no longer duplicate or leave unkillable ghosts
- Switching rices no longer stacks bars and shells
- Spamming the rice-swap key is safe
- The swap shortcut no longer opens the launcher on top of you

---

## `20260903`

**Added**
- Choose which user to log in as (click the name or press ↑/↓)
- **Switch User** in the lock-screen power menu
- `bite-icons-fix` to repair missing icons on an existing system

**Fixed**
- Weather shows real weather again — and no longer needs an API key
- Keyboard layouts no longer duplicate themselves
- Blank placeholder icons in system apps
- A fresh install boots with a top bar
- The caelestia browser key opens Firefox
- Links and credits point at **GLITCH-BITE-404**
