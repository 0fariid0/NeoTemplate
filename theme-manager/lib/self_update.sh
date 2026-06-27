#!/usr/bin/env bash

self_update() {
    local config_file="$1"

    log_info "Checking for 3x-ui theme manager updates..."

    local registry_file=$(fetch_registry "$config_file")
    if [[ -z "$registry_file" || ! -f "$registry_file" ]]; then
        log_error "Failed to fetch registry for self-update."
        return 1
    fi

    local remote_version=$(jq -r '.manager.version // empty' "$registry_file")
    local install_url=$(jq -r '.manager.installUrl // empty' "$registry_file")

    if [[ -z "$remote_version" || -z "$install_url" || "$install_url" == "null" ]]; then
        log_warn "Manager update info not found in registry."
        return 1
    fi

    log_info "Remote manager version: $remote_version"
    log_info "Updating manager files..."

    curl -fsSL "$install_url" -o /tmp/3x-ui-theme-manager-install.sh || return 1
    chmod +x /tmp/3x-ui-theme-manager-install.sh
    NO_START=1 bash /tmp/3x-ui-theme-manager-install.sh --no-start
}
