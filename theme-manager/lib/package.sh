#!/usr/bin/env bash

# Source other dependencies within manager.sh

install_package() {
    local package_req="$1"
    local config_file="$2"
    
    # Parse package@version
    local package_id="${package_req%%@*}"
    local req_version="${package_req##*@}"
    if [[ "$package_id" == "$req_version" ]]; then
        req_version="latest"
    fi

    local install_dir=$(get_config_val "installDirectory" "$config_file")
    local cache_dir=$(get_config_val "cacheDirectory" "$config_file")

    log_info "Fetching registry for $package_id..."
    local registry_file=$(fetch_registry "$config_file")
    
    if [[ -z "$registry_file" || ! -f "$registry_file" ]]; then
        log_error "Failed to load registry."
        return 1
    fi

    # Extract specific package from the single registry
    local package_data=$(jq -c ".packages[] | select(.id == \"$package_id\")" "$registry_file")

    if [[ -z "$package_data" ]]; then
        log_error "Package '$package_id' not found in registry."
        return 1
    fi

    local package_type=$(echo "$package_data" | jq -r '.type')
    if [[ "$package_type" != "theme" ]]; then
        log_error "Unsupported package type: $package_type"
        return 1
    fi

    # Determine which version to install
    local target_version="$req_version"
    if [[ "$req_version" == "latest" ]]; then
        target_version=$(echo "$package_data" | jq -r '.latest')
    fi

    local package_url=$(echo "$package_data" | jq -r ".versions[\"$target_version\"].url")
    local package_checksum=$(echo "$package_data" | jq -r ".versions[\"$target_version\"].checksum // empty")

    if [[ "$package_url" == "null" || -z "$package_url" ]]; then
        log_error "Version '$target_version' not found for package '$package_id'."
        return 1
    fi

    log_info "Downloading $package_id v$target_version..."
    safe_create_dir "$cache_dir/archives"
    local zip_file="$cache_dir/archives/${package_id}-${target_version}.zip"
    download_theme "$package_url" "$zip_file" || return 1

    log_info "Validating checksum..."
    validate_checksum "$zip_file" "$package_checksum" || return 1

    local extract_dir="$cache_dir/$package_id"
    safe_remove_dir "$extract_dir"
    safe_create_dir "$extract_dir"

    log_info "Extracting..."
    extract_zip "$zip_file" "$extract_dir"

    # Assume root folder might exist in zip
    local target_dir="$extract_dir"
    if [[ ! -f "$target_dir/manifest.json" ]]; then
        local dirs=("$extract_dir"/*/)
        if [[ ${#dirs[@]} -eq 1 ]]; then
            target_dir="${dirs[0]}"
        fi
    fi

    log_info "Validating structure..."
    validate_theme_structure "$target_dir" || return 1
    validate_permissions "$target_dir"

    local theme_install_dir="$install_dir/$package_id"

    log_info "Installing to $theme_install_dir..."
    safe_create_dir "$theme_install_dir"
    
    backup_theme "$theme_install_dir" "$cache_dir/backups"

    safe_copy "$target_dir/"* "$theme_install_dir/"
    
    # We must extract the theme name for the success message
    local theme_name=$(jq -r '.name // "Unknown"' "$theme_install_dir/manifest.json")
    
    show_install_success_message "$theme_name" "$theme_install_dir"
}

remove_package() {
    local config_file="$1"
    local install_dir=$(get_config_val "installDirectory" "$config_file")
    
    # When removing, we might want to specify which package to remove if there are multiple.
    local package_id="$2"
    if [[ -z "$package_id" ]]; then
        log_error "Usage: neotemplate remove <package_id>"
        return 1
    fi
    local theme_install_dir="$install_dir/$package_id"
    
    log_info "Removing package $package_id..."
    safe_remove_dir "$theme_install_dir"
    log_info "Package removed."
}

list_installed_packages() {
    local config_file="$1"
    local install_dir=$(get_config_val "installDirectory" "$config_file")
    
    echo -e "${BLUE}Installed Packages:${NC}"
    if [[ -d "$install_dir" ]]; then
        for dir in "$install_dir"/*; do
            if [[ -d "$dir" && -f "$dir/manifest.json" ]]; then
                local id=$(jq -r '.id' "$dir/manifest.json")
                local name=$(jq -r '.name' "$dir/manifest.json")
                local version=$(jq -r '.version' "$dir/manifest.json")
                local type=$(jq -r '.type // "theme"' "$dir/manifest.json")
                echo -e "${GREEN}Package:${NC} $name ($id) v$version [Type: $type] -> $dir"
            fi
        done
    else
        echo -e "${YELLOW}No packages are currently installed.${NC}"
    fi
}
