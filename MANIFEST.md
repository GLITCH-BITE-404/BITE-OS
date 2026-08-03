# BITE-OS — MANIFEST  (Step 1 complete · 2026-05-17)

The single source of truth for what BITE-OS *is*. Everything here must end up
in the `bite-os` package and/or the ISO `/etc/skel` so a fresh install
reproduces the system. Base = CachyOS.

## 1. Packages
- Full explicit set: **275 packages** → `~/bite-os-distro/packages.x86_64`
  (raw list, drop straight into the archiso `packages.x86_64`).
- Identity/desktop core: `hyprland`, `quickshell-git`, `sddm`, `plymouth`,
  `caelestia-meta`, `matugen`, `awww` (rebranded swww), `fastfetch`, `kitty`,
  `nwg-dock-hyprland`, `xdg-desktop-portal-hyprland`, `linux-cachyos(-lts)`.
- CachyOS base pkgs to KEEP: `cachyos-settings`, `cachyos-keyring`,
  `cachyos-*-mirrorlist`, `cachyos-hooks`.

## 2. Custom system files (root-owned → go in the `bite-os` package)
| Path | What |
|---|---|
| `/usr/local/bin/bite-os-rebrand` | restores os-release/lsb-release/issue |
| `/usr/local/bin/bite-os-fix-boot` | HARDENED: boot-entry titles → BITE-OS |
| `/usr/local/bin/bite-os-fix-fastfetch` | enforces BITE-OS fastfetch logo |
| `/etc/pacman.d/hooks/zz-bite-os-boot.hook` | runs fix-boot post-update |
| `/etc/pacman.d/hooks/zz-bite-os-branding.hook` | runs rebrand post-update |
| `/etc/pacman.d/hooks/zz-bite-os-fastfetch.hook` | runs fix-fastfetch post-update |
| `/usr/share/bite-os/{os-release,lsb-release,issue}` | branding source files |
| `/usr/share/plymouth/themes/bite-os` + `glitch-os` | boot splash themes |
| `/usr/share/sddm/themes/bite-os` | login theme |
| `/etc/sddm.conf.d/10-bite-os.conf` | points SDDM at the theme |
| `/etc/os-release`, `/etc/lsb-release`, `/etc/issue` | (copies of /usr/share/bite-os/*) |

## 3. User environment (→ goes in ISO `/etc/skel`, so every user gets it)
| Path | What |
|---|---|
| `~/.config/glitch/bin/` | `rice`, `dots-switch.sh`, `bite-os-healthcheck.sh`, `glitch-update.sh`, `glitch-power.sh`, `glitch-fetch.sh`, `blend-toggle.sh`, `install-glitch-os-system.sh` |
| `~/.config/glitch/{icons,logos,plymouth,templates}` | brand assets, CREDITS.md |
| `~/.config/hypr` + quickshell | the active rice config (rice-managed) |
| `~/.config/{matugen,rofi,cava,foot,kitty,fastfetch,...}` | rice-managed dirs |
| `~/.local/share/bite-os/rices/{caelestia,ilyamiro}` | the dots vault (both rices) |
| `~/.local/share/bite-os/{splash,vault-src}` | splash + ilyamiro source |
| `~/.config/systemd/user/bite-os-healthcheck.service` | first-boot self-repair (must be enabled in skel) |

## 4. Identity
- `os-release`: NAME/PRETTY_NAME=BITE-OS, ID=bite-os, codename `dedsec`,
  HOME_URL tiktok.com/@glitch_bite404, ANSI green.
- **`BUILD_ID=rolling` → change to a real version `1.0` for the ISO.**

## 5. Bugs/leaks to fix before ISO
- [ ] `/etc/hostname` is **`cachyos-x8664`** — should be `bite-os`. (cachyos leak)
- [ ] SDDM/Plymouth `.bak-*` dirs are cruft — exclude from the package.
- [ ] `bite-os-rebrand` references `/usr/share/bite-os/fastfetch.jsonc` which
      doesn't exist — either add it or drop the line.
- [ ] Decide: ship `caelestia-meta` (2nd dot) in the ISO, or ilyamiro-only.

## Next: Step 2 — wrap sections 2+3 into a `bite-os` PKGBUILD; sections 1 feeds
the ISO `packages.x86_64`. See PLAN.md.
