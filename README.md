# macosify-ubuntu

Make Ubuntu (GNOME) look and feel like macOS (Sequoia-style), using GNOME settings, themes/icons if present, and a small set of extensions.

This repo is designed to be **safe and repeatable**:

- It only changes user-level settings (via `gsettings`) and GNOME extensions.
- It won’t install any Apple-proprietary assets.
- If a theme/icon pack is missing, it falls back to the closest available option.

## Supported environment

- Ubuntu with **GNOME Shell** (Wayland or Xorg)
- Tested against GNOME 49-ish setups (Ubuntu 25 series)

## Quick start

```bash
chmod +x macosify-ubuntu.sh
./macosify-ubuntu.sh --light
```

If you prefer a darker setup:

```bash
./macosify-ubuntu.sh --dark
```

## What it changes

- GNOME settings: left-side window buttons, natural scrolling, hot corners, light/dark preference
- Enables/disables GNOME extensions to reduce “non-mac” UI
- Applies theme/icon/cursor/shell theme **if available**

## Optional flags

- `--keep-desktop-icons` — keep desktop icons visible (does not disable DING)
- `--no-packages` — skip `apt install` steps
- `--no-extensions` — skip extension enable/disable steps
- `--show-apps-colored` — optional: custom colored “Show Apps” icon (Launchpad-like)
- `--fonts-inter` — install and apply the Inter font (safe SF Pro–like feel)
- `--cursor-size N` — set cursor size (example: `--cursor-size 24`)
- `--finder-files` — Finder-like defaults for Files (prefer list view + useful columns)
- `--clean-topbar` — minimal top bar cleanup (show date, hide seconds/battery percent)
- `--wallpaper PATH` — set wallpaper from a local file path
- `--wallpaper-dark PATH` — set dark-mode wallpaper from a local file path
- `--laptop` — apply touchpad tweaks (tap-to-click, two-finger scroll, disable-while-typing)
- `--mac-shortcuts` — set mac-like window cycling (Alt+` equivalent via Alt+Above_Tab)
- `--quiet-notifications` — reduce notification noise (disable banners + lock screen)
- `--tiling-assistant` — enable Ubuntu’s tiling assistant (optional; avoid multiple tilers)

Example “enhanced” run:

```bash
./macosify-ubuntu.sh --light \
	--fonts-inter \
	--cursor-size 24 \
	--finder-files \
	--clean-topbar \
	--laptop \
	--mac-shortcuts
```

## Notes

- On **Wayland**, some shell/theme/icon changes may require a **log out / log in**.
- If something looks wrong, re-run the script; it’s idempotent.

## Pushing to GitHub

From this folder:

```bash
git init
git add .
git commit -m "Initial macosify script"
```

Then either:

- GitHub CLI: `gh repo create macosify-ubuntu --public --source=. --remote=origin --push`
- Or create a repo on GitHub and follow the “push existing repo” instructions.
