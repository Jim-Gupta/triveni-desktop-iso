qemu-system-x86_64 -enable-kvm -cpu host -m 4096M -display gtk,zoom-to-fit=on -vga virtio -boot d -cdrom dist/GuideBuilder_5.7.0.12620-trunk_amd64.iso -hda qemu/sda.img -no-shutdown
