#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="2.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
APP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_FILE="/etc/3x-ui-theme-manager/config.json"
[[ -f "$CONFIG_FILE" ]] || CONFIG_FILE="$APP_DIR/config/config.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }
get_cfg(){ jq -r ".$1 // empty" "$CONFIG_FILE"; }
mkdir_safe(){ mkdir -p "$1"; }
rm_safe(){ [[ -n "$1" && -e "$1" ]] && rm -rf "$1"; }

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

install_package(){
  local req="$1" registry_file="${2:-}" non_interactive="${3:-false}"
  local package_id req_version target_version url checksum cache_dir install_dir zip_file extract_dir target_dir dest name
  package_id="${req%%@*}"; req_version="${req##*@}"; [[ "$package_id" == "$req_version" ]] && req_version="latest"
  [[ -n "$registry_file" ]] || registry_file="$(fetch_registry)"
  jq -e --arg id "$package_id" '.packages[] | select(.id==$id)' "$registry_file" >/dev/null || { err "Package not found: $package_id"; return 1; }
  target_version="$req_version"; [[ "$req_version" == "latest" ]] && target_version="$(latest_version "$registry_file" "$package_id")"
  url="$(package_url "$registry_file" "$package_id" "$target_version")"
  checksum="$(package_checksum "$registry_file" "$package_id" "$target_version")"
  [[ -n "$url" ]] || { err "No download URL for $package_id@$target_version"; return 1; }

  cache_dir="$(get_cfg cacheDirectory)"; install_dir="$(get_cfg installDirectory)"
  mkdir_safe "$cache_dir/archives"; mkdir_safe "$install_dir"
  zip_file="$cache_dir/archives/${package_id}-${target_version}.zip"
  extract_dir="$cache_dir/extract-${package_id}"
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
  dest="$install_dir/$package_id"
  if [[ -d "$dest" ]]; then
    mkdir_safe "$cache_dir/backups"
    cp -a "$dest" "$cache_dir/backups/${package_id}-$(date +%Y%m%d-%H%M%S)"
    rm_safe "$dest"
  fi
  mkdir_safe "$dest"
  cp -a "$target_dir"/. "$dest"/
  name="$(jq -r '.name // .id' "$dest/manifest.json")"
  info "Installed: $name"
  echo "Theme path: $dest/"
}

list_available(){
  local registry_file="$(fetch_registry)"
  jq -r '.packages[] | "\(.id)|\(.name)|\(.latest)|\(.description)"' "$registry_file" | awk -F'|' '{printf "  %-18s %-22s v%-8s %s\n", $1,$2,$3,$4}'
}

list_installed(){
  local install_dir="$(get_cfg installDirectory)" any=false
  echo -e "${BLUE}Installed themes:${NC}"
  if [[ -d "$install_dir" ]]; then
    while IFS= read -r -d '' m; do
      any=true
      local d id name ver
      d="$(dirname "$m")"; id="$(jq -r '.id // empty' "$m")"; name="$(jq -r '.name // empty' "$m")"; ver="$(jq -r '.version // empty' "$m")"
      printf "  %-18s %-22s v%-8s %s/\n" "$id" "$name" "$ver" "$d"
    done < <(find "$install_dir" -mindepth 2 -maxdepth 2 -name manifest.json -print0 2>/dev/null | sort -z)
  fi
  [[ "$any" == true ]] || echo "  No themes installed."
}

remove_package(){
  local id="$1" install_dir dest
  install_dir="$(get_cfg installDirectory)"; dest="$install_dir/$id"
  [[ -d "$dest" ]] || { warn "Not installed: $id"; return 0; }
  rm_safe "$dest"; info "Removed: $id"
}

upgrade_packages(){
  local ask="${1:-false}" registry_file install_dir found=false
  registry_file="$(fetch_registry)"; install_dir="$(get_cfg installDirectory)"
  [[ -d "$install_dir" ]] || { warn "No install directory found."; return 0; }
  while IFS= read -r -d '' m; do
    found=true
    local id cur latest cmp
    id="$(jq -r '.id // empty' "$m")"; cur="$(jq -r '.version // "0.0.0"' "$m")"
    latest="$(latest_version "$registry_file" "$id")"
    if [[ -z "$latest" ]]; then warn "Not in registry: $id"; continue; fi
    semver_cmp "$cur" "$latest"; cmp=$?
    if [[ $cmp -eq 2 ]]; then
      info "Update available: $id $cur -> $latest"
      if [[ "$ask" == true ]]; then
        read -r -p "Update $id now? [Y/n] " ans
        [[ "$ans" =~ ^[Nn]$ ]] && continue
      fi
      install_package "$id@latest" "$registry_file" true
    else
      info "$id is up to date (v$cur)."
    fi
  done < <(find "$install_dir" -mindepth 2 -maxdepth 2 -name manifest.json -print0 2>/dev/null | sort -z)
  [[ "$found" == true ]] || warn "No installed themes found."
}

self_update(){
  require_root
  local url tmp new_version config_dir old_install old_cache
  url="$(get_cfg repoArchiveUrl)"; [[ -n "$url" ]] || url="https://github.com/0fariid0/NeoTemplate/archive/refs/heads/main.tar.gz"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  info "Updating manager files..."
  curl -fsSL "$url" | tar xz -C "$tmp" --strip-components=1
  [[ -f "$tmp/theme-manager/manager.sh" ]] || { err "Downloaded archive does not contain theme-manager/manager.sh"; return 1; }
  old_install="$(get_cfg installDirectory)"; old_cache="$(get_cfg cacheDirectory)"
  rsync -a --delete "$tmp/theme-manager/" "$APP_DIR/" 2>/dev/null || { rm -rf "$APP_DIR"/*; cp -a "$tmp/theme-manager"/. "$APP_DIR"/; }
  chmod +x "$APP_DIR/manager.sh" "$APP_DIR/install.sh" 2>/dev/null || true
  config_dir="/etc/3x-ui-theme-manager"; mkdir_safe "$config_dir"
  cp "$APP_DIR/config/config.json" "$config_dir/config.json"
  [[ -n "$old_install" ]] && jq --arg v "$old_install" '.installDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  [[ -n "$old_cache" ]] && jq --arg v "$old_cache" '.cacheDirectory=$v' "$config_dir/config.json" > "$config_dir/config.json.tmp" && mv "$config_dir/config.json.tmp" "$config_dir/config.json"
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/neotemplate
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/subtheme
  ln -sf "$APP_DIR/manager.sh" /usr/local/bin/3x-ui-theme
  new_version="$($APP_DIR/manager.sh version 2>/dev/null || true)"
  info "Manager updated. ${new_version:-}"
}

install_all(){
  local registry_file="$(fetch_registry)"
  mapfile -t ids < <(jq -r '.packages[].id' "$registry_file")
  for id in "${ids[@]}"; do install_package "$id@latest" "$registry_file" true; done
}

draw_menu(){
  clear
  echo -e "${BOLD}3x-ui Subscription Theme Manager${NC}  v$VERSION"
  echo "────────────────────────────────────────"
  echo "1) Install theme"
  echo "2) Update installed themes"
  echo "3) Update manager + themes"
  echo "4) List installed themes"
  echo "5) Remove theme"
  echo "6) Install all themes"
  echo "7) Show install path"
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
      5) list_installed; echo; read -r -p "Theme ID to remove: " id; [[ -n "$id" ]] && remove_package "$id"; read -r -p "Press Enter..." _ ;;
      6) install_all; read -r -p "Press Enter..." _ ;;
      7) echo "Install directory: $(get_cfg installDirectory)"; read -r -p "Press Enter..." _ ;;
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
    list) list_installed ;;
    remove) [[ -n "${2:-}" ]] || { err "Usage: neotemplate remove <theme-id>"; exit 1; }; remove_package "$2" ;;
    upgrade|update-themes) upgrade_packages false ;;
    self-update) self_update ;;
    update) self_update; upgrade_packages false ;;
    "") interactive ;;
    *) err "Unknown command: $1"; echo "Commands: install, install-all, list, remove, upgrade, self-update, update, version"; exit 1 ;;
  esac
}
main "$@"
