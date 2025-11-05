#!/bin/bash

#
# Ubuntu 25.10 Questing Quokka 
# Enable hyper-v linux hvsocket
# by installing linux-tools-virtual, xfce, and xrdp
# 
# Gnome 49+ is not compatible with hvsocket (uses xrdp) because of wayland
# But gnome is still accessible on the non-hvsocket virtual console 
#
# Make sure to run this on the host:
#
#  powershell -c "Set-VM -Name 'UbuntuVMName' -EnhancedSessionTransportType HvSocket"

if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run with root privileges' >&2
    exit 1
fi

apt update && apt upgrade -y

if [ -f /var/run/reboot-required ]; then
    echo "A reboot is required in order to proceed with the install." >&2
    echo "Please reboot and re-run this script to finish the install." >&2
    exit 1
fi

apt install -y linux-tools-virtual linux-cloud-tools-virtual xrdp

systemctl stop xrdp
systemctl stop xrdp-sesman

#hyper-v xrdp setup
sed -i_orig -e 's/port=3389/port=vsock:\/\/-1:3389/g' /etc/xrdp/xrdp.ini
sed -i_orig -e 's/security_layer=negotiate/security_layer=rdp/g' /etc/xrdp/xrdp.ini
sed -i_orig -e 's/crypt_level=high/crypt_level=none/g' /etc/xrdp/xrdp.ini
sed -i_orig -e 's/bitmap_compression=true/bitmap_compression=false/g' /etc/xrdp/xrdp.ini
sed -i_orig -e 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config
sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini

create_config_file() { 
  [ ! -e "$1" ] && echo "$2" > "$1"; 
}
create_config_file "/etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf" "blacklist vmw_vsock_vmci_transport"
create_config_file "/etc/modprobe.d/blacklist-simpledrm.conf" "blacklist simpledrm"
create_config_file "/etc/modules-load.d/hv_sock.conf" "hv_sock"

mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

#xfce setup 
apt-mark hold lightdm light-locker
apt install -y xfce4 xfce4-goodies
apt-mark unhold lightdm light-locker
update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper
PAM_FILE="/etc/pam.d/xrdp-sesman"
sed -i 's/^\(\s*\)-auth\s\+optional\s\+pam_gnome_keyring.so/#\1-auth optional pam_gnome_keyring.so/' "$PAM_FILE"
sed -i 's/^\(\s*\)-auth\s\+optional\s\+pam_kwallet5.so/#\1-auth optional pam_kwallet5.so/' "$PAM_FILE"
sed -i 's/^\(\s*\)-session\s\+optional\s\+pam_gnome_keyring.so\s\+auto_start/#\1-session optional pam_gnome_keyring.so auto_start/' "$PAM_FILE"
sed -i 's/^\(\s*\)-session\s\+optional\s\+pam_kwallet5.so\s\+auto_start/#\1-session optional pam_kwallet5.so auto_start/' "$PAM_FILE"
if ! grep -q 'session optional pam_xauth.so' "$PAM_FILE"; then
    echo "session optional pam_xauth.so" >> "$PAM_FILE"
fi

cat > /etc/xrdp/startxfce.sh << 'EOF'
#!/bin/sh
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce:/usr/local/share:/usr/share:/var/lib/snapd/desktop
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

if [ ! -f "$HOME/.config/xfce-configured" ]; then   
    mkdir -p "$HOME/.config"
    touch "$HOME/.config/xfce-configured"
    systemctl --user mask xfce4-notifyd
    systemctl --user mask xdg-desktop-portal
    systemctl --user mask xdg-desktop-portal-gtk
    xfconf-query -c xfce4-desktop --property /backdrop/screen0/monitorrdp0/workspace0/last-image --create --type string  -s "/usr/share/xfce4/backdrops/greybird-wall.svg"
    xfconf-query -c xsettings -p /Xft/DPI --create --type int -s 120
    xfconf-query -c xfwm4 -p /general/theme --create --type string  -s Yaru-dark
    xfconf-query -c xsettings -p /Net/IconThemeName --create --type string -s Yaru
    xfconf-query -c xsettings -p /Net/ThemeName --create --type string -s Yaru-dark
    (
      sleep 3
      xfconf-query -c xfce4-panel -p /panels/panel-1/size --create --type int -s 42
      xfconf-query -c xfce4-panel -p /panels/panel-2/size --create --type int -s 64
      xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size --create --type int -s 0
      xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior --create --type int -s 0
    ) >"$HOME/.config/xfce-configured-setup.log" 2>&1 &
    (
      sleep 5
      xfce4-terminal --title="Hyper-V Setup Complete" --hide-menubar --geometry=60x10 --command="bash -c \"echo 'Press Enter to reboot'; read; sudo reboot\""
    )  >"$HOME/.config/xfce-configured-setup.log" 2>&1 &
fi

XAUTHORITY="$HOME/.Xauthority"
export XAUTHORITY
if [ ! -f "$XAUTHORITY" ]; then
    touch "$XAUTHORITY"
fi

xauth generate $DISPLAY . trusted >/dev/null 2>&1
xauth add $DISPLAY MIT-MAGIC-COOKIE-1 $(xauth list $DISPLAY | awk '{print $3}') >/dev/null 2>&1

startxfce4
EOF

chmod a+x /etc/xrdp/startxfce.sh
sed -i_orig -e 's/startwm/startxfce/g' /etc/xrdp/sesman.ini

if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sed -i 's/^AutomaticLogin=.*/# AutomaticLogin=/' /etc/gdm3/custom.conf
fi

#done
systemctl daemon-reload
systemctl start xrdp

echo "Install is complete."
echo "Reboot your machine to begin using XRDP."
