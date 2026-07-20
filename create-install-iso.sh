#!/bin/bash

set -euo pipefail

echo "$0 $*" 1>&2

readonly DIST="dist"
readonly DEFAULT_ISO_IN=""
readonly USER_DATA_YAMLS=("legacy-auto-clean" "legacy-auto-upgrade" "legacy-manual-clean" "legacy-manual-upgrade" \
                          "uefi-auto-clean" "uefi-auto-upgrade" "uefi-manual-clean" "uefi-manual-upgrade")

ISO_IN="$DEFAULT_ISO_IN"
SSMT_DIR=""
SSXM_DIR=""
DRIVERS_DIR=""
GUIDE_BUILDER_DEB_DIR=""
ENTERPRISE_DEB_DIR=""
ISO_DESC=""
ISO_OUT=""
BUILD_TIMESTAMP=""
INSTALL_MENU_TITLE="Install Triveni Digital System"

log() {
    echo "[create-install-iso] $*"
}

die() {
    echo "[create-install-iso][error] $*" >&2
    exit 1
}

require_commands() {
    local cmd
    for cmd in dpkg xorriso find md5sum fdisk dd awk grep stat; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
    done
}

usage() {
    cat <<EOF
Usage: $0 -d <drivers_dir> [-m <mt_deb_dir>] [-x <xm_deb_dir>] [-g <gb_deb_dir>] [-i <base_iso_path>]
EOF
}

read_version_from_deb_dir() {
    local deb_dir="$1"
    local deb_file=""

    shopt -s nullglob
    local debs=("$deb_dir"/*.deb)
    shopt -u nullglob

    [ "${#debs[@]}" -gt 0 ] || die "No .deb files found in $deb_dir"
    deb_file="${debs[0]}"
    dpkg -I "$deb_file" | awk '/^ Version:/ {print $2; exit}'
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -i)
                [ "$#" -ge 2 ] || die "Missing value for -i"
                ISO_IN="$2"
                log "24.04 source ISO is $ISO_IN"
                shift 2
                ;;
            -d)
                [ "$#" -ge 2 ] || die "Missing value for -d"
                DRIVERS_DIR="$2"
                log "Drivers directory is $DRIVERS_DIR"
                shift 2
                ;;
            -m)
                [ "$#" -ge 2 ] || die "Missing value for -m"
                SSMT_DIR="$2"
                log "SSMT Debian located at $SSMT_DIR"
                shift 2
                ;;
            -x)
                [ "$#" -ge 2 ] || die "Missing value for -x"
                SSXM_DIR="$2"
                log "SSXM Debian located at $SSXM_DIR"
                shift 2
                ;;
            -r)
                [ "$#" -ge 2 ] || die "Missing value for -r"
                SSRM_DEB="$2"
                log "SSRM Debian located at $SSRM_DEB"
                shift 2
                ;;
            -g)
                [ "$#" -ge 2 ] || die "Missing value for -g"
                GUIDE_BUILDER_DEB_DIR="$2"
                log "Guide Builder Debian located at $GUIDE_BUILDER_DEB_DIR"
                shift 2
                ;;
            -e)
                [ "$#" -ge 2 ] || die "Missing value for -e"
                ENTERPRISE_DEB_DIR="$2"
                log "Enterprise Debian located at $ENTERPRISE_DEB_DIR"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

validate_inputs() {
    [ -n "$ISO_IN" ] || die "ISO input path is empty"
    [ -f "$ISO_IN" ] || die "Ubuntu ISO not found: $ISO_IN"
    log "Using Ubuntu ISO: $ISO_IN"

    [ -d "os-files" ] || die "Missing required directory: os-files"
    [ -d "scripts" ] || die "Missing required directory: scripts"
    [ -f "config/grub.cfg" ] || die "Missing required file: config/grub.cfg"
    [ -f "config/grub_background.png" ] || die "Missing required file: config/grub_background.png"

    local script
    for script in "${REPO_SCRIPTS[@]}"; do
        [ -f "$script" ] || die "Missing required repo script: $script"
    done
}

compute_iso_desc() {
    local ver
    ISO_DESC=""

    if [ -n "$SSMT_DIR" ]; then
        [ -d "$SSMT_DIR" ] || die "SSMT deb directory not found: $SSMT_DIR"
        ver="$(read_version_from_deb_dir "$SSMT_DIR")"
        ISO_DESC="ssmt_${ver}"
    fi

    if [ -n "$SSXM_DIR" ]; then
        [ -d "$SSXM_DIR" ] || die "SSXM deb directory not found: $SSXM_DIR"
        ver="$(read_version_from_deb_dir "$SSXM_DIR")"
        if [ -n "$ISO_DESC" ]; then
            ISO_DESC="${ISO_DESC}_"
        fi
        ISO_DESC="${ISO_DESC}ssxm_${ver}"
    fi

    [ -n "$ISO_DESC" ] || ISO_DESC="streamscope"
    BUILD_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    ISO_OUT="$DIST/${ISO_DESC}-desktop_24.04_amd64_${BUILD_TIMESTAMP}.iso"
    log "ISO Output Filename=${ISO_OUT}"
}

write_build_metadata() {
    local metadata_file="iso/pool/install/build.txt"
    local debians_included=()
    local source_iso_name
    local output_iso_name

    source_iso_name="$(basename "$ISO_IN")"
    output_iso_name="$(basename "$ISO_OUT")"

    if [ -d "iso/pool/install" ]; then
        while IFS= read -r deb_path; do
            debians_included+=("$deb_path")
        done < <(find iso/pool/install -type f -name '*.deb' -printf '%f\n' | sort)
    fi

    {
        echo "iso_name=${output_iso_name}"
        echo "source_iso=${source_iso_name}"
        echo "install_menu_title=${INSTALL_MENU_TITLE}"
        echo

        echo "[debians_included]"
        if [ "${#debians_included[@]}" -gt 0 ]; then
            printf '%s\n' "${debians_included[@]}"
        else
            echo "none"
        fi
    } > "$metadata_file"

    log "Wrote build metadata: $metadata_file"
}

prepare_workspace() {
    rm -rf iso
    mkdir -p "$DIST"
    rm -rf "$DIST"/*
}

extract_base_iso() {
    /usr/bin/xorriso \
        -osirrox on \
        -indev "$ISO_IN" \
        -extract / iso

    chmod -R +w iso
}

stage_pool_content() {
    mkdir -p iso/pool/install
    mkdir -p iso/pool/os-extras

    if [ -n "$DRIVERS_DIR" ]; then
        local drivers_output="iso/pool/install/drivers"
        shopt -s nullglob
        mkdir -p "$drivers_output"
        cp -ar "$DRIVERS_DIR"/* "$drivers_output"/
        copied_driver_count=$(find "$drivers_output" -type f | wc -l)
        log "Driver files staged in $drivers_output: $copied_driver_count"
    fi

    if [ -n "$SSXM_DIR" ]; then
        shopt -s nullglob
        local xm_debs=("$SSXM_DIR"/*.deb)
        shopt -u nullglob
        if [ "${#xm_debs[@]}" -gt 0 ]; then
            cp -a "${xm_debs[@]}" iso/pool/install/
            log "Copied SSXM debian packages to iso/pool/install"
        fi
    fi

    if [ -n "$SSMT_DIR" ]; then
        shopt -s nullglob
        local mt_debs=("$SSMT_DIR"/*.deb)
        shopt -u nullglob
        if [ "${#mt_debs[@]}" -gt 0 ]; then
            cp -a "${mt_debs[@]}" iso/pool/install/
            log "Copied SSMT debian packages to iso/pool/install"
        fi
    fi

    cp -Ra "install" iso/pool
    cp -Ra os-files/* iso/pool/os-extras
}

stage_autoinstall_configs() {
    local profile
    for profile in "${USER_DATA_YAMLS[@]}"; do
        [ -f "config/${profile}-user-data.yaml" ] || die "Missing user-data: config/${profile}-user-data.yaml"
        mkdir -p "iso/nocloud/$profile"
        touch "iso/nocloud/$profile/meta-data"
        cp -a "config/${profile}-user-data.yaml" "iso/nocloud/$profile/user-data"
    done
}

stage_scripts_and_boot_config() {
    mkdir -p iso/scripts
    cp -a scripts/* iso/scripts/

    if [ -n "$SSXM_DIR" ]; then
        shopt -s nullglob
        local xm_debs=("$SSXM_DIR"/ssxm_*.deb)
        shopt -u nullglob
        if [ "${#xm_debs[@]}" -gt 0 ]; then
            cp -a "${xm_debs[@]}" iso/scripts/product-scripts/ssxm/
            log "Staged SSXM first-boot scripts and debs"
        fi
    fi

    if [ -n "$SSMT_DIR" ]; then
        shopt -s nullglob
        local mt_debs=("$SSMT_DIR"/ssmt_*.deb)
        shopt -u nullglob
        if [ "${#mt_debs[@]}" -gt 0 ]; then
            cp -a "${mt_debs[@]}" iso/scripts/product-scripts/ssmt/
            log "Staged SSMT first-boot scripts and debs"
        fi
    fi

    if [ -n "$DRIVERS_DIR" ] && [ -d "$DRIVERS_DIR" ]; then
        shopt -s nullglob
        local driver_payload=("$DRIVERS_DIR"/*)
        shopt -u nullglob
        if [ "${#driver_payload[@]}" -gt 0 ]; then
            cp -a "${driver_payload[@]}" iso/scripts/product-scripts/triveni-drivers/
        fi
        log "Staged triveni-drivers first-boot scripts and payload"
    fi

    if [ -n "$GUIDE_BUILDER_DEB_DIR" ]; then
        shopt -s nullglob
        local gb_debs=("$GUIDE_BUILDER_DEB_DIR"/gb_*.deb)
        shopt -u nullglob
        if [ "${#gb_debs[@]}" -gt 0 ]; then
            cp -a "${gb_debs[@]}" iso/scripts/product-scripts/gb/
            log "Staged GB first-boot scripts and debs"
        fi
    fi

    chmod +x iso/scripts/*.sh
    find iso/scripts -name "*.sh" -exec chmod +x {} +
    cp -a config/grub.cfg iso/boot/grub/
    cp -a config/grub_background.png iso/boot/grub/
}

compute_install_menu_title() {
    local has_xm=0
    local has_mt=0

    shopt -s nullglob
    local xm_pkgs=(iso/scripts/product-scripts/ssxm/ssxm_*.deb)
    local mt_pkgs=(iso/scripts/product-scripts/ssmt/ssmt_*.deb)
    shopt -u nullglob

    [ "${#xm_pkgs[@]}" -gt 0 ] && has_xm=1
    [ "${#mt_pkgs[@]}" -gt 0 ] && has_mt=1

    if [ "$has_xm" -eq 1 ] && [ "$has_mt" -eq 1 ]; then
        INSTALL_MENU_TITLE="Install StreamScopeXM and StreamScopeMT"
    elif [ "$has_mt" -eq 1 ]; then
        INSTALL_MENU_TITLE="Install StreamScopeMT"
    elif [ "$has_xm" -eq 1 ]; then
        INSTALL_MENU_TITLE="Install StreamScopeXM"
    else
        INSTALL_MENU_TITLE="Install Triveni Digital System"
    fi

    log "GRUB install title: $INSTALL_MENU_TITLE"
}

apply_grub_menu_title() {
    local grub_cfg="iso/boot/grub/grub.cfg"
    [ -f "$grub_cfg" ] || die "Missing GRUB config in extracted ISO: $grub_cfg"

    sed -i "s|menuentry \"Clean Install StreamScope (UEFI)\" {|menuentry \"${INSTALL_MENU_TITLE} (UEFI)\" {|g" "$grub_cfg"
    sed -i "s|menuentry \"Clean Install StreamScope (Legacy BIOS)\" {|menuentry \"${INSTALL_MENU_TITLE} (Legacy BIOS)\" {|g" "$grub_cfg"
}

rebuild_md5sum_old() {
    local md5_bin
    md5_bin="$(command -v md5sum)"

    mv iso/ubuntu .
    (
        cd iso
        find '!' -name "md5sum.txt" '!' -path "ubuntu" -follow -type f -exec "$md5_bin" {} \;
    ) > md5sum.txt
    mv md5sum.txt iso/
    mv ubuntu iso
}

rebuild_md5sum() {
    local md5_bin
    md5_bin="$(command -v md5sum)"

    log "Regenerating md5sum.txt..."
    
    # Securely handle the legacy 'ubuntu' symlink loop if it exists
    if [ -e "iso/ubuntu" ]; then
        mv iso/ubuntu .
    fi

    (
        cd iso
        # 1. Explicitly supply '.' as the starting path so find matches correctly
        # 2. Exclude md5sum.txt itself
        # 3. Exclude generated El Torito catalog rewritten by ISO mastering
        # 4. Exclude the entire ./boot directory to bypass xorriso auto-patching errors
        find . -type f \
            '!' -name "md5sum.txt" \
            '!' -path "./boot.catalog" \
            '!' -path "./boot/*" \
            -exec "$md5_bin" {} \;
    ) > md5sum.txt

    mv md5sum.txt iso/

    # Put the symlink back if it was moved
    if [ -e "ubuntu" ]; then
        mv ubuntu iso/
    fi
}

extract_boot_images() {
    local part_info
    local efi_start
    local efi_size

    part_info="$(fdisk -l "$ISO_IN")"
    efi_start="$(echo "$part_info" | awk '/EFI System/ {print $2; exit}')"
    efi_size="$(echo "$part_info" | awk '/EFI System/ {print $4; exit}')"

    [ -n "$efi_start" ] || die "Failed to parse EFI start sector from source ISO"
    [ -n "$efi_size" ] || die "Failed to parse EFI size from source ISO"

    dd if="$ISO_IN" bs=1 count=432 of=boot_hybrid.img
    dd if="$ISO_IN" bs=512 skip="$efi_start" count="$efi_size" of=efi.img

    EFI_SIZE="$efi_size"
}

build_iso() {
    xorriso \
     -as mkisofs \
     -r \
     -J \
     -joliet-long \
     -l \
     -iso-level 4 \
     -V 'StreamScope' \
     --grub2-mbr boot_hybrid.img \
     --protective-msdos-label \
     -partition_cyl_align off \
     -partition_offset 16 \
     --mbr-force-bootable \
     -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b efi.img \
     -appended_part_as_gpt -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
     -c '/boot.catalog' \
     -b '/boot/grub/i386-pc/eltorito.img' \
     -no-emul-boot \
     -boot-load-size 4 \
     -boot-info-table \
     --grub2-boot-info \
     -eltorito-alt-boot \
     -e --interval:appended_partition_2::: \
     -no-emul-boot \
     -boot-load-size "$EFI_SIZE" \
     -o "$ISO_OUT" \
     iso

    /usr/bin/stat "$ISO_OUT"
}

cleanup() {
    rm -rf iso
}

main() {
    require_commands
    parse_args "$@"
    validate_inputs
    compute_iso_desc

    set -x
    prepare_workspace
    extract_base_iso
    stage_pool_content
    stage_autoinstall_configs
    stage_scripts_and_boot_config
    compute_install_menu_title
    write_build_metadata
    # apply_grub_menu_title
    rebuild_md5sum
    extract_boot_images
    build_iso
    # cleanup
    date
}

main "$@"
