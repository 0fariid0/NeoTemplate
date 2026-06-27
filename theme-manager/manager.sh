#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="2.1.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
APP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_DIR="/etc/3x-ui-theme-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
[[ -f "$CONFIG_FILE" ]] || CONFIG_FILE="$APP_DIR/config/config.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }
get_cfg(){ jq -r ".$1 // empty" "$CONFIG_FILE"; }
mkdir_safe(){ mkdir -p "$1"; }
rm_safe(){ [[ -n "${1:-}" && -e "$1" ]] && rm -rf "$1" || true; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then err "Please run as root."; exit 1; fi
}
require_deps(){
  local missing=()
  for c in curl jq unzip tar sha256sum; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing dependencies: ${missing[*]}"
    echo "Install them first, for example: apt-get update && apt-get install -y curl jq unzip tar coreutils"
    exit 1
  fi
}

ensure_writable_config(){
  require_root
  mkdir_safe "$CONFIG_DIR"
  if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    cp "$APP_DIR/config/config.json" "$CONFIG_DIR/config.json"
  fi
  CONFIG_FILE="$CONFIG_DIR/config.json"
}

set_cfg_value(){
  local key="$1" value="$2" tmp
  ensure_writable_config
  tmp="$(mktemp)"
  jq --arg v "$value" ".$key=\$v" "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

active_theme_dir(){
  local d
  d="$(get_cfg activeThemeDirectory)"
  [[ -n "$d" ]] || d="$(get_cfg installDirectory)"
  echo "$d"
}

safe_target_dir(){
  local d="$1"
  [[ -n "$d" && "$d" != "/" && "$d" != "/etc" && "$d" != "/usr" && "$d" != "/var" && "$d" != "/opt" ]]
}

set_theme_path(){
  local requested="${1:-}"
  [[ -n "$requested" ]] || { err "Usage: neotemplate set-path /path/to/fixed/template-folder"; return 1; }
  local resolved
  resolved="$(readlink -m "$requested")"
  safe_target_dir "$resolved" || { err "Unsafe target path: $resolved"; return 1; }
  set_cfg_value activeThemeDirectory "$resolved"
  set_cfg_value installDirectory "$resolved"
  mkdir_safe "$resolved"
  info "Fixed theme path saved: $resolved"
  echo "Set this same folder once in 3x-ui panel. After that, installing another theme only overwrites this folder."
}

fetch_registry(){
  local cache_dir repo_url registry_file
  cache_dir="$(get_cfg cacheDirectory)"; repo_url="$(get_cfg repositoryUrl)"
  registry_file="$cache_dir/registry.json"
  mkdir_safe "$cache_dir"
  curl -fsSL "${repo_url}?t=$(date +%s)" -o "$registry_file"
  jq -e . "$registry_file" >/dev/null
  echo "$registry_file"
}

semver_cmp(){
  local a b IFS=. i
  read -r -a a <<< "${1:-0.0.0}"; read -r -a b <<< "${2:-0.0.0}"
  for ((i=0;i<3;i++)); do
    local ai="${a[$i]:-0}" bi="${b[$i]:-0}"
    ai="${ai%%-*}"; bi="${bi%%-*}"
    ((10#$ai > 10#$bi)) && return 1
    ((10#$ai < 10#$bi)) && return 2
  done
  return 0
}

validate_theme(){
  local d="$1"
  [[ -f "$d/manifest.json" ]] || { err "manifest.json missing"; return 1; }
  [[ -f "$d/index.html" || -f "$d/sub.html" ]] || { err "index.html/sub.html missing"; return 1; }
  jq -e . "$d/manifest.json" >/dev/null || { err "manifest.json is invalid"; return 1; }
  find "$d" -type f -exec chmod 644 {} \;
  find "$d" -type d -exec chmod 755 {} \;
}

package_url(){
  local registry="$1" package_id="$2" target_version="$3"
  jq -r --arg id "$package_id" --arg v "$target_version" '
    .packages[] | select(.id==$id) | .versions[$v].url // empty
  ' "$registry"
}
package_checksum(){
  local registry="$1" package_id="$2" target_version="$3"
  jq -r --arg id "$package_id" --arg v "$target_version" '
    .packages[] | select(.id==$id) | .versions[$v].checksum // empty
  ' "$registry"
}
latest_version(){
  local registry="$1" package_id="$2"
  jq -r --arg id "$package_id" '.packages[] | select(.id==$id) | .latest // empty' "$registry"
}

backup_active_theme(){
  local active_dir="$1" cache_dir="$2" package_id="${3:-theme}" old_id backup_dir
  [[ -d "$active_dir" ]] || return 0
  if [[ -z "$(find "$active_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then return 0; fi
  mkdir_safe "$cache_dir/backups"
  old_id="$package_id"
  [[ -f "$active_dir/manifest.json" ]] && old_id="$(jq -r '.id // "theme"' "$active_dir/manifest.json" 2>/dev/null || echo theme)"
  backup_dir="$cache_dir/backups/${old_id}-$(date +%Y%m%d-%H%M%S)"
  cp -a "$active_dir" "$backup_dir"
  info "Previous active theme backup: $backup_dir"
}

install_package(){
  local req="$1" registry_file="${2:-}" non_interactive="${3:-false}"
  local package_id req_version target_version url checksum cache_dir active_dir zip_file extract_dir target_dir tmp_active name
  package_id="${req%%@*}"; req_version="${req##*@}"; [[ "$package_id" == "$req_version" ]] && req_version="latest"
  [[ -n "$registry_file" ]] || registry_file="$(fetch_registry)"
  jq -e --arg id "$package_id" '.packages[] | select(.id==$id)' "$registry_file" >/dev/null || { err "Package not found: $package_id"; return 1; }
  target_version="$req_version"; [[ "$req_version" == "latest" ]] && target_version="$(latest_version "$registry_file" "$package_id")"
  url="$(package_url "$registry_file" "$package_id" "$target_version")"
  checksum="$(package_checksum "$registry_file" "$package_id" "$target_version")"
  [[ -n "$url" ]] || { err "No download URL for $package_id@$target_version"; return 1; }

  cache_dir="$(get_cfg cacheDirectory)"; active_dir="$(active_theme_dir)"
  safe_target_dir "$active_dir" || { err "Unsafe or empty active theme path: $active_dir"; return 1; }
  mkdir_safe "$cache_dir/archives"; mkdir_safe "$(dirname "$active_dir")"
  zip_file="$cache_dir/archives/${package_id}-${target_version}.zip"
  extract_dir="$cache_dir/extract-${package_id}"
  tmp_active="${active_dir}.tmp.$$"

  info "Downloading $package_id v$target_version"
  curl -fsSL "${url}?t=$(date +%s)" -o "$zip_file"
  if [[ -n "$checksum" ]]; then
    local actual; actual="$(sha256sum "$zip_file" | awk '{print $1}')"
    [[ "$actual" == "$checksum" ]] || { err "Checksum mismatch for $package_id"; return 1; }
  fi

  rm_safe "$extract_dir"; mkdir_safe "$extract_dir"; unzip -q -o "$zip_file" -d "$extract_dir"
  target_dir="$extract_dir"
  if [[ ! -f "$target_dir/manifest.json" ]]; then
    local dirs=("$extract_dir"/*/)
    [[ ${#dirs[@]} -eq 1 ]] && target_dir="${dirs[0]}"
  fi
  validate_theme "$target_dir"

  rm_safe "$tmp_active"; mkdir_safe "$tmp_active"
  cp -a "$target_dir"/. "$tmp_active"/
  printf '{"theme":"%s","version":"%s","installedAt":"%s"}\n' "$package_id" "$target_version" "$(date -Iseconds)" > "$tmp_active/.neotemplate-active.json"
  validate_theme "$tmp_active"

  backup_active_theme "$active_dir" "$cache_dir" "$package_id"
  rm_safe "$active_dir"
  mv "$tmp_active" "$active_dir"
  name="$(jq -r '.name // .id' "$active_dir/manifest.json")"
  info "Active theme changed: $name"
  echo "Fixed theme path: $active_dir/"
}

list_available(){
  local registry_file="$(fetch_registry)"
  jq -r '.packages[] | "\(.id)|\(.name)|\(.latest)|\(.description)"' "$registry_file" | awk -F'|' '{printf "  %-18s %-22s v%-8s %s\n", $1,$2,$3,$4}'
}

list_installed(){
  local active_dir id name ver
  active_dir="$(active_theme_dir)"
  echo -e "${BLUE}Active theme folder:${NC} $active_dir"
  if [[ -f "$active_dir/manifest.json" ]]; then
    id="$(jq -r '.id // empty' "$active_dir/manifest.json")"
    name="$(jq -r '.name // empty' "$active_dir/manifest.json")"
    ver="$(jq -r '.version // empty' "$active_dir/manifest.json")"
    printf "  %-18s %-22s v%-8s %s/\n" "$id" "$name" "$ver" "$active_dir"
  else
    echo "  No active theme installed."
  fi
}

remove_package(){
  local id="${1:-}" active_dir active_id
  active_dir="$(active_theme_dir)"
  [[ -f "$active_dir/manifest.json" ]] || { warn "No active theme installed."; return 0; }
  active_id="$(jq -r '.id // empty' "$active_dir/manifest.json")"
  if [[ -n "$id" && "$id" != "active" && "$id" != "$active_id" ]]; then
    warn "Active theme is '$active_id', not '$id'. Nothing removed."
    return 0
  fi
  safe_target_dir "$active_dir" || { err "Unsafe active theme path: $active_dir"; return 1; }
  rm_safe "$active_dir"
  info "Active theme removed from: $active_dir"
}

upgrade_packages(){
  local ask="${1:-false}" registry_file active_dir id cur latest cmp
  registry_file="$(fetch_registry)"; active_dir="$(active_theme_dir)"
  [[ -f "$active_dir/manifest.json" ]] || { warn "No active theme found in $active_dir"; return 0; }
  id="$(jq -r '.id // empty' "$active_dir/manifest.json")"; cur="$(jq -r '.version // "0.0.0"' "$active_dir/manifest.json")"
  latest="$(latest_version "$registry_file" "$id")"
  if [[ -z "$latest" ]]; then warn "Active theme is not in registry: $id"; return 0; fi
  semver_cmp "$cur" "$latest"; cmp=$?
  if [[ $cmp -eq 2 ]]; then
    info "Update available: $id $cur -> $latest"
    if [[ "$ask" == true ]]; then
      read -r -p "Update active theme now? [Y/n] " ans
      [[ "$ans" =~ ^[Nn]$ ]] && return 0
    fi
    install_package "$id@latest" "$registry_file" true
  else
    info "Active theme is up to date: $id v$cur"
  fi
}

self_update(){
  require_root
  local url tmp new_version config_dir old_install old_cache old_active
  url="$(get_cfg repoArchiveUrl)"; [[ -n "$url" ]] || url="https://github.com/0fariid0/NeoTemplate/archive/refs/heads/main.tar.gz"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  info "Updating manager files..."
  curl -fsSL "$url" | tar xz -C "$tmp" --strip-components=1
  [[ -f "$tmp/theme-manager/manager.sh" ]] || { err "Downloaded archive does not contain theme-manager/manager.sh"; return 1; }
  old_install="$(get_cfg installDirectory)"; old_cache="$(get_cfg cacheDirectory)"; old_active="$(get_cfg activeThemeDirectory)"
  rsync -a --delete "$tmp/theme-manager/" "$APP_DIR/" 2>/dev/null || { rm -rf "$APP_DIR"/*; cp -a "$tmp/theme-manager"/. "$APP_DIR"/; }
  chmod +x "$APP_DIR/manager.sh" "$APP_DIR/install.sh" 2>/dev/null || true
  config_dir="$CONFIG_DIR"; mkdir_safe "$config_dir"
  cp "$APP_DIR/config/config.json" "$config_dir/config.json"
  [[ -n "$old_install" ]] && jq --arg v "$old_install" '.installDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  [[ -n "$old_active" ]] && jq --arg v "$old_active" '.activeThemeDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  [[ -z "$old_active" && -n "$old_install" ]] && jq --arg v "$old_install" '.activeThemeDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  [[ -n "$old_cache" ]] && jq --arg v "$old_cache" '.cacheDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/neotemplate
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/subtheme
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/3x-ui-theme
  new_version="$($APP_DIR/manager.sh version 2>/dev/null || true)"
  info "Manager updated. ${new_version:-}"
}

install_all(){
  warn "Single-folder mode is active. Installing all themes is disabled because every install overwrites the fixed folder."
  echo "Use: neotemplate install <theme-id>"
}

draw_menu(){
  clear
  echo -e "${BOLD}3x-ui Subscription Theme Manager${NC}  v$VERSION"
  echo "────────────────────────────────────────"
  echo "1) Change active theme"
  echo "2) Update active theme"
  echo "3) Update manager + active theme"
  echo "4) Show active theme"
  echo "5) Remove active theme"
  echo "6) Show/change fixed theme path"
  echo "0) Exit"
  echo
}

interactive(){
  while true; do
    draw_menu
    read -r -p "Select: " choice
    case "$choice" in
      1)
        registry_file="$(fetch_registry)"
        mapfile -t rows < <(jq -r '.packages[] | "\(.id)|\(.name)|\(.description)"' "$registry_file")
        echo
        for i in "${!rows[@]}"; do IFS='|' read -r id name desc <<< "${rows[$i]}"; printf "%2d) %-18s %s\n    %s\n" "$((i+1))" "$name" "$id" "$desc"; done
        echo
        read -r -p "Theme number or ID: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#rows[@]} )); then IFS='|' read -r id _ <<< "${rows[$((sel-1))]}"; else id="$sel"; fi
        [[ -n "$id" ]] && install_package "$id@latest" "$registry_file" true
        read -r -p "Press Enter..." _ ;;
      2) upgrade_packages false; read -r -p "Press Enter..." _ ;;
      3) self_update; upgrade_packages false; read -r -p "Press Enter..." _ ;;
      4) list_installed; read -r -p "Press Enter..." _ ;;
      5) list_installed; echo; read -r -p "Remove active theme? Type yes: " ans; [[ "$ans" == "yes" ]] && remove_package active; read -r -p "Press Enter..." _ ;;
      6) echo "Current fixed path: $(active_theme_dir)"; echo; read -r -p "New path, or empty to keep: " p; [[ -n "$p" ]] && set_theme_path "$p"; read -r -p "Press Enter..." _ ;;
      0) exit 0 ;;
      *) warn "Invalid option"; sleep 1 ;;
    esac
  done
}

main(){
  require_deps
  case "${1:-}" in
    version) echo "v$VERSION" ;;
    list-available|search) list_available ;;
    install) [[ -n "${2:-}" ]] || { err "Usage: neotemplate install <theme-id>[@version]"; exit 1; }; install_package "$2" ;;
    install-all) install_all ;;
    list|active) list_installed ;;
    remove) remove_package "${2:-active}" ;;
    upgrade|update-themes) upgrade_packages false ;;
    self-update) self_update ;;
    update) self_update; upgrade_packages false ;;
    path|show-path) echo "$(active_theme_dir)" ;;
    set-path) set_theme_path "${2:-}" ;;
    "") interactive ;;
    *) err "Unknown command: $1"; echo "Commands: install, list, remove, upgrade, self-update, update, path, set-path, version"; exit 1 ;;
  esac
}
main "$@"
