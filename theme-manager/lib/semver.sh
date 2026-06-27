#!/usr/bin/env bash

# Compare two semantic versions.
# Returns 0 if v1 == v2
# Returns 1 if v1 > v2
# Returns 2 if v1 < v2
semver_compare() {
    local v1="$1"
    local v2="$2"
    
    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($v1) ver2=($v2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<3; i++)); do
        ver1[i]=0
    done
    for ((i=${#ver2[@]}; i<3; i++)); do
        ver2[i]=0
    done
    
    for ((i=0; i<3; i++)); do
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    
    return 0
}

# Checks if the provided version meets the minimum required version.
# Returns 0 if true, 1 if false.
semver_satisfies_min() {
    local version="$1"
    local min_version="$2"
    
    semver_compare "$version" "$min_version"
    local result=$?
    
    if [[ $result -eq 0 || $result -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}
