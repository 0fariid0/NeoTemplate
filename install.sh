#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="3x-ui Subscription Theme Manager"
INSTALL_DIR="/opt/3x-ui-theme-manager"
CONFIG_DIR="/etc/3x-ui-theme-manager"
GITHUB_USER="0fariid0"
REPO_NAME="NeoTemplate"
BRANCH="main"
ARCHIVE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"

echo "Installing ${APP_NAME}..."

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run this installer as root."
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }
install_deps() {
  local missing=()
  for c in curl tar jq unzip sha256sum; do
    need_cmd "$c" || missing+=("$c")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Installing dependencies: ${missing[*]}"
    if need_cmd apt-get; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar jq unzip coreutils
    elif need_cmd dnf; then
      dnf install -y curl tar jq unzip coreutils
    elif need_cmd yum; then
      yum install -y curl tar jq unzip coreutils
    else
      echo "Could not install dependencies automatically. Install these manually: ${missing[*]}"
      exit 1
    fi
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USE_LOCAL=false
LOCAL_SRC=""
if [[ -f "$SCRIPT_DIR/theme-manager/manager.sh" ]]; then
  USE_LOCAL=true
  LOCAL_SRC="$SCRIPT_DIR/theme-manager"
elif [[ -f "$SCRIPT_DIR/manager.sh" ]]; then
  USE_LOCAL=true
  LOCAL_SRC="$SCRIPT_DIR"
fi

install_deps
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

TMP_DIR=""
cleanup() { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ "$USE_LOCAL" == true ]]; then
  echo "Using local files from $LOCAL_SRC"
  rsync -a --delete "$LOCAL_SRC/" "$INSTALL_DIR/" 2>/dev/null || { rm -rf "$INSTALL_DIR"/*; cp -a "$LOCAL_SRC"/. "$INSTALL_DIR"/; }
else
  TMP_DIR="$(mktemp -d)"
  echo "Downloading project archive..."
  curl -fsSL "$ARCHIVE_URL" | tar xz -C "$TMP_DIR" --strip-components=1
  rsync -a --delete "$TMP_DIR/theme-manager/" "$INSTALL_DIR/" 2>/dev/null || { rm -rf "$INSTALL_DIR"/*; cp -a "$TMP_DIR/theme-manager"/. "$INSTALL_DIR"/; }
fi

if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  cp "$INSTALL_DIR/config/config.json" "$CONFIG_DIR/config.json"
else
  # Keep user paths, refresh repository/update URLs from the new package.
  # In single-folder mode, activeThemeDirectory is the one fixed folder that 3x-ui should use.
  old_install_dir="$(jq -r '.installDirectory // empty' "$CONFIG_DIR/config.json" 2>/dev/null || true)"
  old_active_dir="$(jq -r '.activeThemeDirectory // empty' "$CONFIG_DIR/config.json" 2>/dev/null || true)"
  old_cache_dir="$(jq -r '.cacheDirectory // empty' "$CONFIG_DIR/config.json" 2>/dev/null || true)"
  cp "$INSTALL_DIR/config/config.json" "$CONFIG_DIR/config.json"
  [[ -n "$old_install_dir" ]] && tmp="$(mktemp)" && jq --arg v "$old_install_dir" '.installDirectory=$v' "$CONFIG_DIR/config.json" > "$tmp" && mv "$tmp" "$CONFIG_DIR/config.json"
  if [[ -n "$old_active_dir" ]]; then
    tmp="$(mktemp)" && jq --arg v "$old_active_dir" '.activeThemeDirectory=$v' "$CONFIG_DIR/config.json" > "$tmp" && mv "$tmp" "$CONFIG_DIR/config.json"
  elif [[ -n "$old_install_dir" ]]; then
    tmp="$(mktemp)" && jq --arg v "$old_install_dir" '.activeThemeDirectory=$v' "$CONFIG_DIR/config.json" > "$tmp" && mv "$tmp" "$CONFIG_DIR/config.json"
  fi
  [[ -n "$old_cache_dir" ]] && tmp="$(mktemp)" && jq --arg v "$old_cache_dir" '.cacheDirectory=$v' "$CONFIG_DIR/config.json" > "$tmp" && mv "$tmp" "$CONFIG_DIR/config.json"
fi

chmod +x "$INSTALL_DIR/manager.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || true
ln -sf "$INSTALL_DIR/manager.sh" /usr/local/bin/neotemplate
ln -sf "$INSTALL_DIR/manager.sh" /usr/local/bin/subtheme
ln -sf "$INSTALL_DIR/manager.sh" /usr/local/bin/3x-ui-theme

echo "Installation complete."
echo "Run: neotemplate"
if [[ -t 0 && -t 1 ]]; then
  echo "Opening manager..."
  neotemplate
fi
