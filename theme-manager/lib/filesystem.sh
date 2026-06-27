#!/usr/bin/env bash

safe_create_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

safe_copy() {
    cp -r "$@"
}

safe_remove_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
    fi
}

extract_zip() {
    local zip_file="$1"
    local dest_dir="$2"
    unzip -q -o "$zip_file" -d "$dest_dir"
}

backup_theme() {
    local current_dir="$1"
    local backup_dir="$2"
    if [[ -d "$current_dir" ]]; then
        safe_create_dir "$backup_dir"
        local timestamp=$(date +%s)
        safe_copy "$current_dir" "${backup_dir}/backup_${timestamp}"
        log_info "Backed up current theme to ${backup_dir}/backup_${timestamp}"
    fi
}
