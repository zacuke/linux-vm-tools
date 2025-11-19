#!/bin/bash

#
# This script is for Ubuntu 25.10 Trixie to install xrdp and xfce 
# for hyper-v hvsocket compatibility. It assumes existing vanilla 
# Gnome and Wayland. Xfce will be used by xrdp sessions.
#
# Gnome 49+ is not compatible with xrdp because of Wayland.
#

###############################################################################
# Update our machine to the latest code if we need to.
#

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

export DEBIAN_FRONTEND=noninteractive

###############################################################################
# XRDP
#

# Install hv_kvp utils
apt install -y linux-tools-virtual
apt install -y linux-cloud-tools-virtual

# Install xfce 
apt install -y xfce4 xfce4-goodies

# Install the xrdp service so we have the auto start behavior
apt install -y xrdp

systemctl stop xrdp
systemctl stop xrdp-sesman

# Configure the installed XRDP ini files.
# use vsock transport.
sed -i_orig -e 's/port=3389/port=vsock:\/\/-1:3389/g' /etc/xrdp/xrdp.ini
# use rdp security.
sed -i_orig -e 's/security_layer=negotiate/security_layer=rdp/g' /etc/xrdp/xrdp.ini
# remove encryption validation.
sed -i_orig -e 's/crypt_level=high/crypt_level=none/g' /etc/xrdp/xrdp.ini
# disable bitmap compression since its local its much faster
sed -i_orig -e 's/bitmap_compression=true/bitmap_compression=false/g' /etc/xrdp/xrdp.ini

# Create xfce session script for XRDP
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

    #<optional>
    # Dark theme 
    # Increase panel size
    # Desktop background
    xfconf-query -c xfce4-desktop --property /backdrop/screen0/monitorrdp0/workspace0/last-image --create --type string  -s "/usr/share/xfce4/backdrops/greybird-wall.svg"
    
    # Font DPI (96, 120, 144)
    xfconf-query -c xsettings -p /Xft/DPI --create --type int -s 120

    # Window manager theme 
    xfconf-query -c xfwm4 -p /general/theme --create --type string  -s Yaru-dark
 
    # Icon theme
    xfconf-query -c xsettings -p /Net/IconThemeName --create --type string -s Yaru

    # GTK theme
    xfconf-query -c xsettings -p /Net/ThemeName --create --type string -s Yaru-dark

    # Wait for panel to load
    (
      sleep 3

      # increase top panel height
      xfconf-query -c xfce4-panel -p /panels/panel-1/size --create --type int -s 42

      # increase bottom panel height
      xfconf-query -c xfce4-panel -p /panels/panel-2/size --create --type int -s 64

      # auto panel icon size
      xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size --create --type int -s 0

      # always show Panel
      xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior --create --type int -s 0

    ) >"$HOME/.config/xfce-configured-setup.log" 2>&1 &
    #</optional> 

    #gnome will be left logged in so nudge the user to reboot
    (
      sleep 5

      xfce4-terminal --title="Hyper-V Setup Complete" --hide-menubar --geometry=60x10 --command="bash -c \"echo 'Press Enter to reboot'; read; sudo reboot\""
    )  >"$HOME/.config/xfce-configured-setup.log" 2>&1 &
fi

# Ensure Xauthority exists and is valid
XAUTHORITY="$HOME/.Xauthority"
export XAUTHORITY
if [ ! -f "$XAUTHORITY" ]; then
    touch "$XAUTHORITY"
fi

# Manually generate token
xauth generate $DISPLAY . trusted >/dev/null 2>&1
xauth add $DISPLAY MIT-MAGIC-COOKIE-1 $(xauth list $DISPLAY | awk '{print $3}') >/dev/null 2>&1

startxfce4
EOF
chmod a+x /etc/xrdp/startxfce.sh

# use XFCE instead of GNOME for XRDP sessions
sed -i_orig -e 's/startwm/startxfce/g' /etc/xrdp/sesman.ini

# rename the redirected drives to 'shared-drives'
sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini

# Changed the allowed_users
sed -i_orig -e 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config

# Blacklist the vmw module
if [ ! -e /etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf ]; then
  echo "blacklist vmw_vsock_vmci_transport" > /etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf
fi

# Blacklist simpledrm to prevent conflict with hyperv_drm
if [ ! -e /etc/modprobe.d/blacklist-simpledrm.conf ]; then
  echo "blacklist simpledrm" > /etc/modprobe.d/blacklist-simpledrm.conf
fi

#Ensure hv_sock gets loaded
if [ ! -e /etc/modules-load.d/hv_sock.conf ]; then
  echo "hv_sock" > /etc/modules-load.d/hv_sock.conf
fi

# Configure the policy xrdp session
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# set xfce terminal as default
update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper

# We don't want the virtual console to sign into Gnome automatically
if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sed -i 's/^AutomaticLogin=.*/# AutomaticLogin=/' /etc/gdm3/custom.conf
fi

# Fix PAM configuration for XRDP
PAM_FILE="/etc/pam.d/xrdp-sesman"

# Comment out gnome-keyring and kwallet PAM lines safely
sed -i 's/^\(\s*\)-auth\s\+optional\s\+pam_gnome_keyring.so/#\1-auth optional pam_gnome_keyring.so/' "$PAM_FILE"
sed -i 's/^\(\s*\)-auth\s\+optional\s\+pam_kwallet5.so/#\1-auth optional pam_kwallet5.so/' "$PAM_FILE"
sed -i 's/^\(\s*\)-session\s\+optional\s\+pam_gnome_keyring.so\s\+auto_start/#\1-session optional pam_gnome_keyring.so auto_start/' "$PAM_FILE"
sed -i 's/^\(\s*\)-session\s\+optional\s\+pam_kwallet5.so\s\+auto_start/#\1-session optional pam_kwallet5.so auto_start/' "$PAM_FILE"

# Append pam_xauth.so only if it is not already there
if ! grep -q 'session optional pam_xauth.so' "$PAM_FILE"; then
    echo "session optional pam_xauth.so" >> "$PAM_FILE"
fi
 
# remove app that crashes
sudo apt remove light-locker -y

# reconfigure the service
systemctl daemon-reload
systemctl start xrdp

#
# End XRDP
###############################################################################
 

echo "Install is complete."
echo "Reboot your machine to begin using XRDP."
