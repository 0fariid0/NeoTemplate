#!/usr/bin/env bash

upgrade_packages() {
    local config_file="$1"
    local install_dir=$(get_config_val "installDirectory" "$config_file")
    
    local packages_found=false
    
    if [[ -d "$install_dir" ]]; then
        for dir in "$install_dir"/*; do
            if [[ -d "$dir" && -f "$dir/manifest.json" ]]; then
                packages_found=true
                local active_id=$(jq -r '.id' "$dir/manifest.json")
                local active_version=$(jq -r '.version' "$dir/manifest.json")
                
                log_info "Checking updates for $active_id..."
                
                local registry_file=$(fetch_registry "$config_file")
                if [[ -z "$registry_file" || ! -f "$registry_file" ]]; then
                    log_warn "Could not fetch registry to check updates for $active_id."
                    continue
                fi
                
                local package_data=$(jq -c ".packages[] | select(.id == \"$active_id\")" "$registry_file")
                if [[ -z "$package_data" ]]; then
                    log_warn "Active package $active_id not found in registry."
                    continue
                fi
                
                local latest_version=$(echo "$package_data" | jq -r '.latest')
                
                semver_compare "$active_version" "$latest_version"
                local cmp_res=$?
                
                if [[ $cmp_res -eq 2 ]]; then
                    log_info "Update available for $active_id: $active_version -> $latest_version"
                    read -p "Do you want to update now? [Y/n] " choice
                    if [[ "$choice" == "Y" || "$choice" == "y" || -z "$choice" ]]; then
                        install_package "$active_id@latest" "$config_file"
                    fi
                elif [[ $cmp_res -eq 0 || $cmp_res -eq 1 ]]; then
                    log_info "Package $active_id is up to date (v$active_version)."
                fi
            fi
        done
    fi
    
    if [[ "$packages_found" == false ]]; then
        log_info "No active packages installed to check for updates."
    fi
}
