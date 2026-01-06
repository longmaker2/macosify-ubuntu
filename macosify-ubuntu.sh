#!/usr/bin/env bash
set -euo pipefail

# macosify-ubuntu.sh
# Make Ubuntu GNOME look/feel macOS-like using GNOME settings + optional themes/icons/extensions.

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*"; }

gsettings_has_key() {
  local schema="$1"
  local key="$2"
  gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key"
}

gsettings_set_if_key_exists() {
  local schema="$1"
  local key="$2"
  local value="$3"
  if has_schema "$schema" && gsettings_has_key "$schema" "$key"; then
    gsettings set "$schema" "$key" "$value" 2>/dev/null || true
  fi
}

to_file_uri() {
  # Print a file:// URI for a local path. Returns non-zero if path doesn't exist.
  local p="$1"
  python3 - <<'PY' "$p"
import pathlib, sys
from urllib.parse import quote

p = sys.argv[1]
path = pathlib.Path(p).expanduser().resolve()
if not path.exists():
    raise SystemExit(1)
print('file://' + quote(str(path)))
PY
}

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

apply_mac_typography() {
  if [[ "$DO_FONTS_INTER" != "true" ]]; then
    return 0
  fi

  # Inter is a good, legally-safe approximation of SF Pro feel.
  log "Applying macOS-like typography (Inter)"
  gsettings set org.gnome.desktop.interface font-name 'Inter 11' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface document-font-name 'Inter 11' 2>/dev/null || true
  # Leave monospace alone unless explicitly requested in the future.
}

apply_cursor_settings() {
  if [[ -z "${CURSOR_SIZE:-}" ]]; then
    return 0
  fi
  if [[ ! "$CURSOR_SIZE" =~ ^[0-9]+$ ]]; then
    warn "Invalid --cursor-size: $CURSOR_SIZE (expected integer)"
    return 0
  fi

  log "Setting cursor size to $CURSOR_SIZE"
  gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
}

apply_finder_like_files() {
  if [[ "$DO_FINDER_FILES" != "true" ]]; then
    return 0
  fi

  log "Applying Finder-like defaults for Files (Nautilus)"

  # Prefer list view
  gsettings_set_if_key_exists org.gnome.nautilus.preferences default-folder-viewer "'list-view'"

  # Type-ahead search
  gsettings_set_if_key_exists org.gnome.nautilus.preferences type-ahead-search true

  # Reasonable default columns (name/size/type/modified)
  gsettings_set_if_key_exists org.gnome.nautilus.list-view default-visible-columns "['name','size','type','modified']"
  gsettings_set_if_key_exists org.gnome.nautilus.list-view default-column-order "['name','size','type','modified']"
}

apply_topbar_cleanup() {
  if [[ "$DO_CLEAN_TOPBAR" != "true" ]]; then
    return 0
  fi

  log "Applying minimal top bar cleanup"

  # More macOS-ish clock (date, no seconds)
  gsettings_set_if_key_exists org.gnome.desktop.interface clock-show-date true
  gsettings_set_if_key_exists org.gnome.desktop.interface clock-show-seconds false

  # Reduce visual noise
  gsettings_set_if_key_exists org.gnome.desktop.interface show-battery-percentage false
}

apply_wallpaper() {
  if [[ -z "${WALLPAPER_PATH:-}" && -z "${WALLPAPER_DARK_PATH:-}" ]]; then
    return 0
  fi

  log "Setting wallpaper"

  if [[ -n "${WALLPAPER_PATH:-}" ]]; then
    local uri
    if uri=$(to_file_uri "$WALLPAPER_PATH" 2>/dev/null); then
      gsettings set org.gnome.desktop.background picture-uri "$uri" 2>/dev/null || true
    else
      warn "Wallpaper not found: $WALLPAPER_PATH"
    fi
  fi

  if [[ -n "${WALLPAPER_DARK_PATH:-}" ]]; then
    local urid
    if urid=$(to_file_uri "$WALLPAPER_DARK_PATH" 2>/dev/null); then
      gsettings set org.gnome.desktop.background picture-uri-dark "$urid" 2>/dev/null || true
    else
      warn "Dark wallpaper not found: $WALLPAPER_DARK_PATH"
    fi
  fi
}

apply_laptop_touchpad_defaults() {
  if [[ "$DO_LAPTOP" != "true" ]]; then
    return 0
  fi

  log "Applying laptop touchpad defaults"

  # macOS-like basics
  gsettings_set_if_key_exists org.gnome.desktop.peripherals.touchpad tap-to-click true
  gsettings_set_if_key_exists org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
  gsettings_set_if_key_exists org.gnome.desktop.peripherals.touchpad disable-while-typing true
  gsettings_set_if_key_exists org.gnome.desktop.peripherals.touchpad click-method "'fingers'"
  # Gentle speed bump; safe fallback if unsupported
  gsettings_set_if_key_exists org.gnome.desktop.peripherals.touchpad speed 0.2

  # Note: On GNOME Wayland, 3-finger gestures (workspaces/overview) are built-in.
}

apply_mac_shortcuts() {
  if [[ "$DO_MAC_SHORTCUTS" != "true" ]]; then
    return 0
  fi

  log "Applying macOS-like keyboard shortcuts"

  # Cmd+` equivalent: cycle windows in the current app.
  # Use Above_Tab (works across many keyboard layouts) rather than 'grave'.
  gsettings_set_if_key_exists org.gnome.desktop.wm.keybindings switch-group "['<Alt>Above_Tab']"
  gsettings_set_if_key_exists org.gnome.desktop.wm.keybindings switch-group-backward "['<Shift><Alt>Above_Tab']"
}

apply_quiet_notifications() {
  if [[ "$DO_QUIET_NOTIFICATIONS" != "true" ]]; then
    return 0
  fi

  log "Reducing notification noise"
  gsettings_set_if_key_exists org.gnome.desktop.notifications show-banners false
  gsettings_set_if_key_exists org.gnome.desktop.notifications show-in-lock-screen false
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
  # Avoid duplicate docks/taskbars (common source of a "taskbar under the dock")
  disable_ext ubuntu-dock@ubuntu.com
  disable_ext dash-to-dock@micxgx.gmail.com
  disable_ext dash-to-panel@jderose9.github.com

  disable_ext arcmenu@arcmenu.com
  disable_ext apps-menu@gnome-shell-extensions.gcampax.github.com
  disable_ext places-menu@gnome-shell-extensions.gcampax.github.com
  disable_ext window-list@gnome-shell-extensions.gcampax.github.com
  disable_ext launch-new-instance@gnome-shell-extensions.gcampax.github.com

  # Extra extensions that commonly make GNOME feel less "macOS-like"
  disable_ext Vitals@CoreCoding.com
  disable_ext gnome-ui-tune@itstime.tech
  disable_ext auto-move-windows@gnome-shell-extensions.gcampax.github.com
  disable_ext drive-menu@gnome-shell-extensions.gcampax.github.com
  disable_ext native-window-placement@gnome-shell-extensions.gcampax.github.com
  disable_ext screenshot-window-sizer@gnome-shell-extensions.gcampax.github.com
  disable_ext light-style@gnome-shell-extensions.gcampax.github.com
  disable_ext system-monitor@gnome-shell-extensions.gcampax.github.com
  disable_ext windowsNavigator@gnome-shell-extensions.gcampax.github.com
  disable_ext workspace-indicator@gnome-shell-extensions.gcampax.github.com
  if [[ "$DO_TILING_ASSISTANT" == "true" ]]; then
    enable_ext tiling-assistant@ubuntu.com
  else
    disable_ext tiling-assistant@ubuntu.com
  fi
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

  # Running indicators (macOS-like dot/underline). Keys are typed; only set if present.
  # Note: In Dash2Dock Lite:
  # - 1 = "Dots" (multiple)
  # - 2 = "Dot"  (single; closest to macOS)
  # - 9 = "Triangles" (avoid)
  gsettings_set_if_key_exists "$schema" running-indicator-style 2
  # Size is a dropdown (Normal=0, Small=1, Big=2). Use Normal for a less-tiny macOS-like dot.
  gsettings_set_if_key_exists "$schema" running-indicator-size 0

  # macOS-like proportions & behavior (keys vary by version; only set if present)
  gsettings_set_if_key_exists "$schema" icon-size 48
  gsettings_set_if_key_exists "$schema" dock-location "'BOTTOM'"
  gsettings_set_if_key_exists "$schema" panel-mode false

  # Allow hover text (icon labels/tooltips)
  gsettings_set_if_key_exists "$schema" hide-labels false
  gsettings_set_if_key_exists "$schema" favorites-only false

  # Autohide behavior
  gsettings_set_if_key_exists "$schema" autohide-dash true
  gsettings_set_if_key_exists "$schema" autohide-dodge true
  gsettings_set_if_key_exists "$schema" autohide-speed 0.25

  # Spacing/padding (subtle)
  gsettings_set_if_key_exists "$schema" icon-spacing 6
  gsettings_set_if_key_exists "$schema" dock-padding 6
  gsettings_set_if_key_exists "$schema" edge-distance 6

  # Keep icons from shrinking when crowded
  gsettings_set_if_key_exists "$schema" shrink-icons false

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
Usage: $0 [--light|--dark]
  [--macos-max]
  [--keep-desktop-icons] [--no-packages] [--no-extensions]
  [--show-apps-colored]
  [--fonts-inter] [--cursor-size N] [--finder-files] [--clean-topbar]
  [--wallpaper PATH] [--wallpaper-dark PATH]
  [--laptop] [--mac-shortcuts] [--quiet-notifications] [--tiling-assistant]

Defaults:
  --light

EOF
}

COLOR_SCHEME="light"
DO_MACOS_MAX="false"
KEEP_DESKTOP_ICONS="false"
DO_PACKAGES="true"
DO_EXTENSIONS="true"
DO_SHOW_APPS_COLORED="false"
DO_FONTS_INTER="false"
CURSOR_SIZE=""
DO_FINDER_FILES="false"
DO_CLEAN_TOPBAR="false"
WALLPAPER_PATH=""
WALLPAPER_DARK_PATH=""
DO_LAPTOP="false"
DO_MAC_SHORTCUTS="false"
DO_QUIET_NOTIFICATIONS="false"
DO_TILING_ASSISTANT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --light) COLOR_SCHEME="light"; shift ;;
    --dark) COLOR_SCHEME="dark"; shift ;;
    --macos-max)
      # Opinionated, safe "most macOS-like" preset.
      DO_MACOS_MAX="true"
      DO_FONTS_INTER="true"
      DO_FINDER_FILES="true"
      DO_CLEAN_TOPBAR="true"
      DO_LAPTOP="true"
      DO_MAC_SHORTCUTS="true"
      DO_QUIET_NOTIFICATIONS="true"
      shift
      ;;
    --keep-desktop-icons) KEEP_DESKTOP_ICONS="true"; shift ;;
    --no-packages) DO_PACKAGES="false"; shift ;;
    --no-extensions) DO_EXTENSIONS="false"; shift ;;
    --show-apps-colored) DO_SHOW_APPS_COLORED="true"; shift ;;
    --fonts-inter) DO_FONTS_INTER="true"; shift ;;
    --cursor-size) CURSOR_SIZE="${2:-}"; shift 2 ;;
    --finder-files) DO_FINDER_FILES="true"; shift ;;
    --clean-topbar) DO_CLEAN_TOPBAR="true"; shift ;;
    --wallpaper) WALLPAPER_PATH="${2:-}"; shift 2 ;;
    --wallpaper-dark) WALLPAPER_DARK_PATH="${2:-}"; shift 2 ;;
    --laptop) DO_LAPTOP="true"; shift ;;
    --mac-shortcuts) DO_MAC_SHORTCUTS="true"; shift ;;
    --quiet-notifications) DO_QUIET_NOTIFICATIONS="true"; shift ;;
    --tiling-assistant) DO_TILING_ASSISTANT="true"; shift ;;
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
    $( [[ "$DO_FONTS_INTER" == "true" ]] && echo fonts-inter ) \
    || true
fi

install_dash2dock_lite_from_github

apply_gnome_defaults

apply_mac_typography
apply_cursor_settings
apply_finder_like_files
apply_topbar_cleanup
apply_wallpaper
apply_laptop_touchpad_defaults
apply_mac_shortcuts
apply_quiet_notifications

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
