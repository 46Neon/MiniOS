# Configuración heredada de la imagen Debian/QEMU

`grub/`, `lightdm/`, `systemd/` y los recursos `xfce/` de este directorio pertenecen al rootfs Debian anterior. No se copian ni aplican al usuario Termux. El perfil móvil experimental nativo se crea, opt-in y con respaldo, desde `scripts/termux-native/mobile-profile.sh` bajo directorios MiniAriño separados.
