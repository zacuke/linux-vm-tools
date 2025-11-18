#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
#
# This script is for Ubuntu 25.10 Trixie to install XRDP+XFCE
#
# It assumes existing vanilla Gnome and Wayland.
#
# XFCE will host the XRDP sessions 
# Gnome 49+ is not compatible with XRDP because of Wayland
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

###############################################################################
# XRDP
#

# Install hv_kvp utils
apt install -y linux-tools-virtual
apt install -y linux-cloud-tools-virtual

# Install XFCE desktop (more compatible with XRDP)
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

xhost +

# Create XFCE session script for XRDP
cat > /etc/xrdp/startxfce.sh << 'EOF'
#!/bin/sh
export XDG_CONFIG_HOME="$HOME/.config-xfce"
export XDG_DATA_HOME="$HOME/.local-xfce"
export XDG_CACHE_HOME="$HOME/.cache-xfce"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
export XDG_SESSION_DESKTOP=xfce
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

if [ ! -f "$HOME/.config/xfce-configured" ]; then   
 
    mkdir -p "$HOME/.config"
    touch "$HOME/.config/xfce-configured"

    # Window manager theme 
    xfconf-query -c xfwm4 -p /general/theme --create --type string  -s Greybird-dark
 
    # Icon theme
    xfconf-query -c xsettings -p /Net/IconThemeName --create --type string -s elementary-xfce

    # GTK theme
    xfconf-query -c xsettings -p /Net/ThemeName --create --type string -s Greybird-dark
 
    # Desktop background
    xfconf-query -c xfce4-desktop --property /backdrop/screen0/monitorrdp0/workspace0/last-image --create --type string  -s "/usr/share/xfce4/backdrops/greybird-wall.svg"
 
fi
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

# reconfigure the service
systemctl daemon-reload
systemctl start xrdp
#systemctl --user mask --now gnome-keyring-daemon.service gsd-* gnome-session*

#
# End XRDP
###############################################################################
###############################################################################
# Disable auto login
#

# We don't want the virtual console to sign into Gnome automatically
if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sed -i 's/^AutomaticLogin=.*/# AutomaticLogin=/' /etc/gdm3/custom.conf
fi
echo "Install is complete."
echo "Reboot your machine to begin using XRDP."
echo "Gnome will logout in 15 seconds."

( sleep 15 && gnome-session-quit --logout --no-prompt ) &