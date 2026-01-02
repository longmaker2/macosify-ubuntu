#!/usr/bin/env bash
set -euo pipefail

# macosify-ubuntu.sh
# Make Ubuntu GNOME look/feel macOS-like using GNOME settings + optional themes/icons/extensions.

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    warn "Missing command: $1";
    return 1;
  }
}

has_schema() {
  gsettings list-schemas 2>/dev/null | grep -qx "$1"
}

has_theme_dir() {
  local name="$1"
  [[ -d "$HOME/.themes/$name" || -d "$HOME/.local/share/themes/$name" || -d "/usr/share/themes/$name" ]]
}

has_icon_dir() {
  local name="$1"
  [[ -d "$HOME/.icons/$name" || -d "$HOME/.local/share/icons/$name" || -d "/usr/share/icons/$name" ]]
}

enable_ext() {
  local uuid="$1"
  if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
    gnome-extensions enable "$uuid" 2>/dev/null || true
  fi
}

disable_ext() {
  local uuid="$1"
  if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
    gnome-extensions disable "$uuid" 2>/dev/null || true
  fi
}

install_dash2dock_lite_from_github() {
  local ext_dir="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com"
  if [[ -d "$ext_dir" ]]; then
    return 0
  fi

  if ! need_cmd git; then
    warn "Skipping Dash2Dock Lite install (git not available)."
    return 0
  fi

  log "Installing Dash2Dock Lite extension from GitHub"
  mkdir -p "$HOME/.local/share/gnome-shell/extensions"
  git clone --depth 1 https://github.com/icedman/dash2dock-lite.git "$ext_dir" || {
    warn "Failed to clone dash2dock-lite.";
    return 0;
  }

  # Ensure schemas are compiled for gsettings usage (user-local)
  local schema_dir="$HOME/.local/share/glib-2.0/schemas"
  mkdir -p "$schema_dir"
  if [[ -f "$ext_dir/schemas/org.gnome.shell.extensions.dash2dock-lite.gschema.xml" ]]; then
    cp -f "$ext_dir/schemas/org.gnome.shell.extensions.dash2dock-lite.gschema.xml" "$schema_dir/" || true
    if need_cmd glib-compile-schemas; then
      glib-compile-schemas "$schema_dir" || true
    fi
  fi
}

apply_gnome_defaults() {
  log "Applying GNOME macOS-like defaults"

  # Left-side window controls (macOS-like)
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' || true

  # Natural scrolling
  gsettings set org.gnome.desktop.peripherals.mouse natural-scroll true 2>/dev/null || true
  gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true 2>/dev/null || true

  # Hot corners (Overview)
  gsettings set org.gnome.desktop.interface enable-hot-corners true 2>/dev/null || true

  # Light/dark preference (does not force all apps, but helps)
  if [[ "$COLOR_SCHEME" == "light" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
  else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
  fi
}

pick_theme() {
  # Prefer Tahoe, then WhiteSur, then Yaru.
  if [[ "$COLOR_SCHEME" == "light" ]]; then
    for t in "Tahoe-Light" "WhiteSur-Light" "Yaru"; do
      if has_theme_dir "$t"; then echo "$t"; return 0; fi
    done
  else
    for t in "Tahoe-Dark" "WhiteSur-Dark" "Yaru-dark" "Yaru"; do
      if has_theme_dir "$t"; then echo "$t"; return 0; fi
    done
  fi
  echo "Yaru"
}

pick_shell_theme() {
  # Shell themes are under ~/.themes/<name>/gnome-shell; but we just reuse the same name if present.
  pick_theme
}

pick_icons() {
  # Prefer MacTahoe, then WhiteSur, then Yaru.
  if [[ "$COLOR_SCHEME" == "light" ]]; then
    for i in "MacTahoe-light" "MacTahoe" "WhiteSur-light" "Yaru"; do
      if has_icon_dir "$i"; then echo "$i"; return 0; fi
    done
  else
    for i in "MacTahoe-dark" "MacTahoe" "WhiteSur-dark" "Yaru-dark" "Yaru"; do
      if has_icon_dir "$i"; then echo "$i"; return 0; fi
    done
  fi
  echo "Yaru"
}

pick_cursor() {
  # Prefer MacTahoe cursor set if present, otherwise keep current.
  if [[ "$COLOR_SCHEME" == "light" ]]; then
    for c in "MacTahoe-light" "MacTahoe" "WhiteSur-cursors" "Yaru"; do
      if has_icon_dir "$c"; then echo "$c"; return 0; fi
    done
  else
    for c in "MacTahoe-dark" "MacTahoe" "WhiteSur-cursors" "Yaru"; do
      if has_icon_dir "$c"; then echo "$c"; return 0; fi
    done
  fi
  echo "Yaru"
}

apply_theme_and_icons() {
  log "Applying themes/icons (if available)"

  local gtk_theme
  local shell_theme
  local icon_theme
  local cursor_theme

  gtk_theme="$(pick_theme)"
  shell_theme="$(pick_shell_theme)"
  icon_theme="$(pick_icons)"
  cursor_theme="$(pick_cursor)"

  gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" || true
  gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" || true
  gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" || true

  # Shell theme requires User Themes extension
  if has_schema org.gnome.shell.extensions.user-theme; then
    gsettings set org.gnome.shell.extensions.user-theme name "$shell_theme" 2>/dev/null || true
  else
    warn "User Themes schema not found; install/enable the user-theme extension to theme GNOME Shell."
  fi

  log "Selected: GTK=$gtk_theme Shell=$shell_theme Icons=$icon_theme Cursor=$cursor_theme"
}

apply_extensions() {
  log "Enabling/disabling extensions for macOS-like UI"

  # Keep / enable mac-feel
  enable_ext user-theme@gnome-shell-extensions.gcampax.github.com
  enable_ext dash2dock-lite@icedman.github.com
  enable_ext blur-my-shell@aunetx
  enable_ext compiz-alike-magic-lamp-effect@hermes83.github.com

  # Disable non-mac clutter
  disable_ext arcmenu@arcmenu.com
  disable_ext apps-menu@gnome-shell-extensions.gcampax.github.com
  disable_ext places-menu@gnome-shell-extensions.gcampax.github.com
  disable_ext window-list@gnome-shell-extensions.gcampax.github.com
  disable_ext tiling-assistant@ubuntu.com
  disable_ext tilingshell@ferrarodomenico.com
  disable_ext space-bar@luchrioh

  if [[ "$KEEP_DESKTOP_ICONS" == "false" ]]; then
    disable_ext ding@rastersoft.com
  fi
}

configure_dash2dock_lite() {
  local schema='org.gnome.shell.extensions.dash2dock-lite'
  if ! has_schema "$schema"; then
    warn "Dash2Dock Lite schema not found in gsettings; skipping dock tuning."
    return 0
  fi

  log "Configuring dock (Dash2Dock Lite)"

  # Running indicators
  gsettings set "$schema" running-indicator-style 1 2>/dev/null || true
  gsettings set "$schema" running-indicator-size 6 2>/dev/null || true

  # Reduce GPU-heavy effects a bit while keeping the look
  gsettings set "$schema" animate-icons true 2>/dev/null || true
}

setup_spotlight_shortcut() {
  if ! command -v ulauncher-toggle >/dev/null 2>&1; then
    warn "ulauncher-toggle not found; skipping Spotlight shortcut."
    return 0
  fi

  log "Setting Super+Space to open Spotlight-like launcher (Ulauncher)"

  local base='org.gnome.settings-daemon.plugins.media-keys'
  local list_key='custom-keybindings'

  local cur
  cur=$(gsettings get "$base" "$list_key" 2>/dev/null || echo "[]")

  # Find a free slot
  local i=0
  local new_path=""
  while [[ $i -lt 50 ]]; do
    local p="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${i}/"
    if ! grep -q "custom${i}/" <<<"$cur"; then
      new_path="$p"
      break
    fi
    i=$((i+1))
  done

  if [[ -z "$new_path" ]]; then
    warn "Could not allocate a custom keybinding slot.";
    return 0
  fi

  python3 - <<PY
import ast, subprocess
base='$base'
key='$list_key'
cur=subprocess.check_output(['gsettings','get',base,key], text=True).strip()
arr=ast.literal_eval(cur) if cur.startswith('[') else []
new_path='$new_path'
if new_path not in arr:
    arr.append(new_path)
subprocess.check_call(['gsettings','set',base,key,str(arr)])
PY

  local entry="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${new_path}"
  gsettings set "$entry" name 'Spotlight' || true
  gsettings set "$entry" command 'ulauncher-toggle' || true
  gsettings set "$entry" binding '<Super>space' || true
}

install_colored_show_apps_icon() {
  # Optional customization: colored Show Apps icon and patch dock to prefer non-symbolic icon.
  local theme
  theme="$(pick_icons)"
  local icon_file="$HOME/.local/share/icons/$theme/apps/scalable/view-app-grid.svg"

  log "Installing custom Show Apps icon (colored squares, no background)"
  mkdir -p "$(dirname "$icon_file")"
  if [[ -f "$icon_file" ]]; then
    cp -f "$icon_file" "$icon_file.backup.$(date +%Y%m%d-%H%M%S)" || true
  fi

  cat > "$icon_file" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <!-- Transparent background; 9 colored rounded squares -->
  <g>
    <rect x="18" y="18" width="24" height="24" rx="7" fill="#60a5fa"/>
    <rect x="52" y="18" width="24" height="24" rx="7" fill="#93c5fd"/>
    <rect x="86" y="18" width="24" height="24" rx="7" fill="#a78bfa"/>

    <rect x="18" y="52" width="24" height="24" rx="7" fill="#34d399"/>
    <rect x="52" y="52" width="24" height="24" rx="7" fill="#fbbf24"/>
    <rect x="86" y="52" width="24" height="24" rx="7" fill="#fb7185"/>

    <rect x="18" y="86" width="24" height="24" rx="7" fill="#22d3ee"/>
    <rect x="52" y="86" width="24" height="24" rx="7" fill="#f472b6"/>
    <rect x="86" y="86" width="24" height="24" rx="7" fill="#94a3b8"/>
  </g>
</svg>
SVG

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/$theme" 2>/dev/null || true
  fi

  # Patch dash2dock-lite to prefer view-app-grid (non-symbolic)
  local ext_js="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/dock.js"
  if [[ -f "$ext_js" ]]; then
    if ! grep -q "Prefer full-color app grid icon" "$ext_js"; then
      cp -f "$ext_js" "$ext_js.backup.$(date +%Y%m%d-%H%M%S)" || true
      python3 - <<'PY'
import pathlib
p = pathlib.Path.home() / '.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/dock.js'
text = p.read_text(errors='ignore').splitlines(True)
needle = "c._icon = c.icon.icon;"
insert = [
    "        // Prefer full-color app grid icon for Show Apps (Launchpad-like)\n",
    "        try { c._icon.icon_name = 'view-app-grid'; } catch (e) {}\n",
]
idx=None
for i,line in enumerate(text):
    if needle in line:
        idx=i
        break
if idx is None:
    raise SystemExit('Insertion point not found')
text[idx+1:idx+1]=insert
p.write_text(''.join(text))
PY
    fi

    disable_ext dash2dock-lite@icedman.github.com
    sleep 1
    enable_ext dash2dock-lite@icedman.github.com
  else
    warn "dash2dock-lite dock.js not found; icon override installed but dock patch skipped."
  fi
}

ensure_power_profiles() {
  # Keep it conservative: enable Ubuntu's default power profiles if available.
  if systemctl show -p UnitFileState power-profiles-daemon 2>/dev/null | grep -q masked; then
    warn "power-profiles-daemon is masked; leaving it unchanged (could be intentional)."
    return 0
  fi

  if need_cmd systemctl; then
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null || true
  fi
}

usage() {
  cat <<EOF
Usage: $0 [--light|--dark] [--keep-desktop-icons] [--no-packages] [--no-extensions] [--show-apps-colored]

Defaults:
  --light

EOF
}

COLOR_SCHEME="light"
KEEP_DESKTOP_ICONS="false"
DO_PACKAGES="true"
DO_EXTENSIONS="true"
DO_SHOW_APPS_COLORED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --light) COLOR_SCHEME="light"; shift ;;
    --dark) COLOR_SCHEME="dark"; shift ;;
    --keep-desktop-icons) KEEP_DESKTOP_ICONS="true"; shift ;;
    --no-packages) DO_PACKAGES="false"; shift ;;
    --no-extensions) DO_EXTENSIONS="false"; shift ;;
    --show-apps-colored) DO_SHOW_APPS_COLORED="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if ! need_cmd gsettings || ! need_cmd gnome-extensions; then
  warn "This script requires GNOME + gsettings + gnome-extensions.";
  exit 1
fi

log "macosify-ubuntu starting (scheme=$COLOR_SCHEME)"

if [[ "$DO_PACKAGES" == "true" ]]; then
  log "Installing packages (safe defaults)"
  sudo apt update
  sudo apt install -y \
    gnome-tweaks gnome-shell-extensions dconf-editor \
    git curl unzip \
    ulauncher \
    power-profiles-daemon \
    || true
fi

install_dash2dock_lite_from_github

apply_gnome_defaults

if [[ "$DO_EXTENSIONS" == "true" ]]; then
  apply_extensions
fi

apply_theme_and_icons
configure_dash2dock_lite
setup_spotlight_shortcut

if [[ "$DO_SHOW_APPS_COLORED" == "true" ]]; then
  install_colored_show_apps_icon
fi

ensure_power_profiles

log "Done. On Wayland, log out/in if shell/icons don’t refresh."
