# BITE-OS — core source

The full system payload (rices, themes, Quickshell UI) is large and staged from
a running BITE-OS install, so it isn't committed to this repo. The scripts here
are the **core engineered logic** of BITE-OS — readable and auditable on their
own, with no build step required.

| File | What it does |
|---|---|
| `dots-switch.sh` | Hot-swaps between the two complete desktops (`caelestia` ⇄ `ilyamiro`). Backs up the live config before every swap and arms a 30-second watchdog that auto-reverts if the new desktop fails to come up — so you can't get locked out. |
| `bite-os-healthcheck.sh` | Self-repair. Runs at every login, detects a wiped or broken config and rebuilds it from the vault automatically. |
| `settings_watcher.sh` | Backs the live GUI settings panel. Watches `settings.json` and regenerates the Hyprland config (keybinds, language, weather, startup apps) from templates, then hot-reloads — no text-file editing. |
| `rice` | The rice vault tool. `rice save` persists edits into the vault; dot-switching restores from it. |
| `blend-toggle.sh` | Toggles the `SUPER + B` hacker-aesthetic overlay. |

These are copies of the live scripts shipped inside the ISO. They are MIT
licensed — see [`../LICENSE`](../LICENSE).

`// THE SYSTEM BIT YOU` — GLITCH-BITE-404
