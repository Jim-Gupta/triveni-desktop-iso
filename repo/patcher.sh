#!/bin/bash

set -euo pipefail

readonly DOWNLOAD_DIR="./security_patches"

readonly REPO_DATA_URL="http://10.77.46.5:8080/userContent/SecurityPatches/data/"
# TODO fix URL to point to 7.1 instead of trunk once 7.1 branch is created
readonly SSMT_DATA_URL="http://10.77.46.5:8080/userContent/StreamScopeMT_24.04_trunk/"
readonly SSXM_DATA_URL="http://10.77.46.5:8080/userContent/SSXM_24.04_1.6/"


download_all_items_from_url() {
    local url="$1"
    local target_dir="$2"

    echo "Downloading all items from $url into $target_dir..."
    mkdir -p "$target_dir"

    curl -s "$url" | grep -oE 'href="[^"]+\.(tgz|sh|deb)"' | cut -d'"' -f2 | xargs -I {} curl -s -O --output-dir "$target_dir" "$url{}"
 }

zip_items() {
    local items_dir="$1"
    local output_file="$2"

    if [[ ! -d "$items_dir" ]]; then
        echo "Error: Directory $items_dir does not exist."
        return 1
    fi

    if [[ -f "$output_file" ]]; then
        echo "Warning: Output file $output_file already exists and will be overwritten."
        rm -f "$output_file"
    fi

    echo "Zipping items from $items_dir into $output_file..."
    zip -r "$output_file" "$items_dir"
}

apply_security_patches() {
    echo "Applying security patches..."
    cd "$DOWNLOAD_DIR"
    for patch in *.sh; do
        echo "Running patch: $patch"
        chmod +x "$patch"
        sudo ./"$patch"
    done
    echo "Done."
}

install_security_patches_and_upgrade_xm_mt() {
    echo "Installing Security Patches and upgrading XM & MT..."
    rm -rf "$DOWNLOAD_DIR"

    download_all_items_from_url "$REPO_DATA_URL" "$DOWNLOAD_DIR"
    download_all_items_from_url "$SSXM_DATA_URL" "$DOWNLOAD_DIR"
    download_all_items_from_url "$SSMT_DATA_URL" "$DOWNLOAD_DIR"
    chmod -R +x "$DOWNLOAD_DIR"/*.sh
    apply_security_patches
    echo "Done."
}

install_security_patches_only() {
    echo "Installing Security Patches only..."
    rm -rf "$DOWNLOAD_DIR"

    download_all_items_from_url "$REPO_DATA_URL" "$DOWNLOAD_DIR"
    chmod -R +x "$DOWNLOAD_DIR"/*.sh
    apply_security_patches

    echo "Done."
}

upgrade_xm_mt_only() {
    echo "Upgrading XM & MT only (no security patches)..."
    rm -rf "$DOWNLOAD_DIR"

    download_all_items_from_url "$SSXM_DATA_URL" "$DOWNLOAD_DIR"
    download_all_items_from_url "$SSMT_DATA_URL" "$DOWNLOAD_DIR"
    wget "$REPO_DATA_URL/install_repo.sh" -O "$DOWNLOAD_DIR/install_repo.sh"
    chmod +x "$DOWNLOAD_DIR/install_repo.sh"
    cd "$DOWNLOAD_DIR"
    sudo ./"install_repo.sh"
}

create_distribution_package_with_xm_mt() {
    echo "Creating distribution package for customers with XM & MT..."
    rm -rf "$DOWNLOAD_DIR"

    download_all_items_from_url "$REPO_DATA_URL" "$DOWNLOAD_DIR"
    download_all_items_from_url "$SSXM_DATA_URL" "$DOWNLOAD_DIR"
    download_all_items_from_url "$SSMT_DATA_URL" "$DOWNLOAD_DIR"
    chmod -R +x "$DOWNLOAD_DIR"/*.sh

    zip_items "$DOWNLOAD_DIR" "security_patches_xm_mt_$(date +%Y%m%d).zip"
    echo "Done."
}

create_distribution_package_patches_only() {
    echo "\nCreating distribution package for customers only patches..."
    rm -rf "$DOWNLOAD_DIR"

    download_all_items_from_url "$REPO_DATA_URL" "$DOWNLOAD_DIR"
    chmod -R +x "$DOWNLOAD_DIR"/*.sh

    zip_items "$DOWNLOAD_DIR" "security_patches_$(date +%Y%m%d).zip"
}

show_menu() {
  cat <<'EOF'
Please choose an option:
 1) Install security patches and upgrade XM & MT
 2) Install security patches only
 3) Upgrade XM & MT only (no security patches)
 4) Create a distribution package for customers with XM & MT
 5) Create a distribution package for customers only patches
 q) Quit
EOF
}

main() {
    show_menu
    read -rp "Enter choice: " choice
    case "$choice" in
        1)
        install_security_patches_and_upgrade_xm_mt
        ;;
        2)
        install_security_patches_only
        ;;
        3)
        upgrade_xm_mt_only
        ;;
        4)
        create_distribution_package_with_xm_mt
        ;;
        5)
        create_distribution_package_patches_only
        ;;
        q|Q)
        echo "Exiting."
        exit 0
        ;;
        *)
        echo "Invalid option. Please select 1-5 or q."
        ;;
    esac
    echo
}

main "$@"
