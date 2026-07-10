#!/usr/bin/env bash
# extract-uki.sh — pull the kernel + initrd out of a duranium UKI (.efi)
# so QEMU can boot them directly via -kernel/-initrd.
#
# WHY: the QEMU-aarch64 image boots via UEFI → systemd-boot → UKI. That
# path relies on systemd-gpt-auto-generator to discover the root
# partition, which duranium routes through systemd-cryptsetup@pmOS_root.
# Our boot harness masks cryptsetup (there's no LUKS on the QEMU image),
# so /dev/mapper/root never appears and the initrd waits for root
# forever — nothing switch-roots, greetd/sshd never start, and the guest
# looks "booted" only because QEMU's slirp optimistically accepts the
# :22 forward (→ ssh "banner exchange timeout", blank screen).
#
# Booting the extracted kernel+initrd with an explicit root=LABEL=pmOS_root
# sidesteps the whole gpt-auto/cryptsetup chain — exactly what the Pi 5
# firmware-boot path already does with these same UKIs.
#
# Usage:
#   source lib/extract-uki.sh
#   extract_uki_kernel_initrd "$UKI_EFI" "$CACHE_DIR"
#   # sets $UKI_KERNEL and $UKI_INITRD

# extract_uki_kernel_initrd <uki.efi> <cache_dir>
extract_uki_kernel_initrd() {
    local uki="$1" cache="$2"
    [ -f "$uki" ] || { echo "extract-uki: no UKI at $uki" >&2; return 1; }
    command -v objcopy >/dev/null || { echo "extract-uki: objcopy not found (need binutils)" >&2; return 1; }
    mkdir -p "$cache"
    UKI_KERNEL="$cache/vmlinuz"
    UKI_INITRD="$cache/initrd"
    local stamp="$cache/.uki-source"
    # Re-extract only when the UKI changed (cheap idempotency).
    if [ ! -s "$UKI_KERNEL" ] || [ ! -s "$UKI_INITRD" ] \
       || [ "$(cat "$stamp" 2>/dev/null)" != "$uki" ] || [ "$uki" -nt "$UKI_KERNEL" ]; then
        echo "==> extracting kernel+initrd from UKI: $(basename "$uki")"
        objcopy -O binary --only-section=.linux  "$uki" "$UKI_KERNEL"
        objcopy -O binary --only-section=.initrd "$uki" "$UKI_INITRD"
        printf '%s\n' "$uki" > "$stamp"
    fi
}
