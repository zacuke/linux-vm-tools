#!/bin/bash

#
# This script is for Ubuntu 22.04 Jammy Jellyfish to download and install XRDP+XORGXRDP via
# source.
#
# Major thanks to: http://c-nergy.be/blog/?p=11336 for the tips.
#

###############################################################################
# Use HWE kernel packages
#
HWE=""
#HWE="-hwe-22.04"

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
apt install -y linux-tools-virtual${HWE}
apt install -y linux-cloud-tools-virtual${HWE}

# Install XFCE desktop (more compatible with XRDP)
apt install -y xfce4 xfce4-goodies xdg-desktop-portal-xapp

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

# Create XFCE session script for XRDP
cat > /etc/xrdp/startxfce.sh << 'EOF'
#!/bin/sh
# Initialize proper session environment for XRDP
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce:/usr/local/share:/usr/share:/var/lib/snapd/desktop
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_SESSION_PATH=/run/user/$(id -u)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# Initialize D-Bus session bus if not already running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Ensure the runtime directory exists
mkdir -p $XDG_RUNTIME_DIR

# Configure XDG desktop portal to use XFCE implementation
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce

# Stop conflicting GNOME services that interfere with XFCE
systemctl --user stop xdg-desktop-portal-gtk 2>/dev/null || true
systemctl --user mask xdg-desktop-portal-gtk 2>/dev/null || true

# Start XFCE-compatible portal service
systemctl --user start xdg-desktop-portal-xapp 2>/dev/null || true

# Update desktop file database to fix slow application launching
update-desktop-database /usr/share/applications 2>/dev/null || true

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Start XFCE desktop
startxfce4
EOF
chmod a+x /etc/xrdp/startxfce.sh

# use XFCE instead of GNOME for XRDP sessions
sed -i_orig -e 's/startwm/startxfce/g' /etc/xrdp/sesman.ini

# rename the redirected drives to 'shared-drives'
sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini

# Configure XDG desktop portal to prefer XFCE implementation
mkdir -p /etc/xdg/xdg-xfce
cat > /etc/xdg/xdg-xfce/xdg-desktop-portal.conf << 'EOF'
[preferred]
default=gtk
EOF

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

###############################################################################
# Disable auto login
#

# Disable GDM auto login if configured
if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sed -i 's/^AutomaticLogin=.*/# AutomaticLogin=/' /etc/gdm3/custom.conf
fi

# Disable LightDM auto login if configured
if [ -f /etc/lightdm/lightdm.conf ]; then
    sed -i 's/^autologin-user=.*/# autologin-user=/' /etc/lightdm/lightdm.conf
    sed -i 's/^autologin-user-timeout=.*/# autologin-user-timeout=/' /etc/lightdm/lightdm.conf
fi

reboot