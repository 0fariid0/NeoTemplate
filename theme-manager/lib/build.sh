#!/usr/bin/env bash

# Builds a production-ready package from a development directory
build_package() {
    local source_dir="$1"
    
    if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
        log_error "Usage: neotemplate build <path-to-theme-directory>"
        return 1
    fi
    
    # Resolve absolute path
    source_dir=$(cd "$source_dir" && pwd)
    
    log_info "Starting production build for: $source_dir"
    
    # 1. Validation of Manifest
    if [[ ! -f "$source_dir/manifest.json" ]]; then
        log_error "manifest.json not found in the source directory."
        return 1
    fi
    
    local package_id=$(jq -r '.id // empty' "$source_dir/manifest.json")
    local package_version=$(jq -r '.version // empty' "$source_dir/manifest.json")
    
    if [[ -z "$package_id" || -z "$package_version" ]]; then
        log_error "Invalid manifest.json: missing 'id' or 'version'."
        return 1
    fi
    
    log_info "Package identified: $package_id v$package_version"
    
    # 2. Staging Environment
    local staging_base="/tmp/neotemplate_build"
    local staging_dir="$staging_base/$package_id"
    
    log_info "Staging files..."
    safe_remove_dir "$staging_base"
    safe_create_dir "$staging_dir"
    safe_copy "$source_dir/"* "$staging_dir/"
    
    # 3. Purging Development Artifacts
    log_info "Purging development artifacts..."
    
    # Remove Preview Engine
    if [[ -d "$staging_dir/preview" ]]; then
        safe_remove_dir "$staging_dir/preview"
        log_info "Removed preview/ directory"
    fi
    
    # Remove Mock Data
    if [[ -f "$staging_dir/mock-data.json" ]]; then
        rm -f "$staging_dir/mock-data.json"
        log_info "Removed mock-data.json"
    fi
    
    # Remove OS specific and hidden files
    find "$staging_dir" -name ".DS_Store" -type f -delete
    find "$staging_dir" -name "Thumbs.db" -type f -delete
    find "$staging_dir" -name "desktop.ini" -type f -delete
    
    # 4. Final Validation (No absolute paths to local files, no preview code)
    # Simple check if there are any remaining references to 'preview/' or 'mock-data' in html
    if grep -q "preview.js" "$staging_dir/index.html" 2>/dev/null; then
        log_error "index.html contains references to development scripts (preview.js)."
        safe_remove_dir "$staging_base"
        return 1
    fi
    
    # 5. Packaging
    local dist_dir="$source_dir/../dist"
    safe_create_dir "$dist_dir"
    local zip_file="$dist_dir/${package_id}-${package_version}.zip"
    
    rm -f "$zip_file"
    
    log_info "Creating production package..."
    # cd into staging base so the zip contains the top-level folder $package_id
    # Wait, the rule says themes shouldn't be extracted into a subfolder initially, or rather
    # they should extract directly or into a single folder. 
    # Usually zip contains the contents directly or one folder. We will zip the contents of staging_dir directly.
    (cd "$staging_dir" && zip -r -q "$zip_file" .)
    
    if [[ $? -eq 0 ]]; then
        log_info "Build successful! Package saved to:"
        echo -e "${GREEN}$zip_file${NC}"
    else
        log_error "Failed to create ZIP package."
        safe_remove_dir "$staging_base"
        return 1
    fi
    
    # 6. Cleanup
    safe_remove_dir "$staging_base"
}
