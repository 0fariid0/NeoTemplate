#!/usr/bin/env bash

validate_theme_structure() {
    local theme_dir="$1"
    
    if [[ ! -f "$theme_dir/manifest.json" ]]; then
        log_error "manifest.json missing."
        return 1
    fi
    
    if [[ ! -f "$theme_dir/index.html" ]]; then
        log_error "index.html missing."
        return 1
    fi
    

    
    # Check if manifest is valid JSON
    if ! jq -e . "$theme_dir/manifest.json" >/dev/null 2>&1; then
        log_error "manifest.json is not valid JSON."
        return 1
    fi
    
    return 0
}

validate_checksum() {
    local file="$1"
    local expected_hash="$2"
    
    if [[ -z "$expected_hash" ]]; then
        # If no expected hash is provided, skip validation
        return 0
    fi
    
    local actual_hash=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        log_error "Checksum mismatch. Expected: $expected_hash, Actual: $actual_hash"
        return 1
    fi
    
    return 0
}

validate_permissions() {
    local theme_dir="$1"
    # Basic permission fix/check, ensure no execution bits for static files
    find "$theme_dir" -type f -exec chmod 644 {} \;
    find "$theme_dir" -type d -exec chmod 755 {} \;
    return 0
}
