#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

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

# Create XFCE session script for XRDP
cat > /etc/xrdp/startxfce.sh << 'EOF'
#!/bin/sh

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_CONFIG_DIRS=/etc/xdg/xdg-xfce:/etc/xdg
export XDG_DATA_DIRS=/usr/share/xfce:/usr/local/share:/usr/share:/var/lib/snapd/desktop
export XDG_SESSION_PATH=/run/user/$(id -u)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# # Create XDG runtime directory if it doesn't exist
# if [ ! -d "$XDG_RUNTIME_DIR" ]; then
#     export XDG_RUNTIME_DIR=/run/user/$(id -u)
#     mkdir -p "$XDG_RUNTIME_DIR"
#     chmod 0700 "$XDG_RUNTIME_DIR"
# fi

# if [ -r /etc/default/locale ]; then
#   . /etc/default/locale
#   export LANG LANGUAGE
# fi

# # Start dbus if not running
# if ! pgrep -x dbus-daemon > /dev/null; then
#     dbus-launch --sh-syntax
# fi

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
# mkdir -p /etc/polkit-1/localauthority/50-local.d/
# cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
# [Allow Colord all Users]
# Identity=unix-user:*
# Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
# ResultAny=no
# ResultInactive=no
# ResultActive=yes
# EOF

# # reconfigure the service
# systemctl daemon-reload
# systemctl start xrdp

# # Fix GNOME Keyring PAM daemon control file issue
# mkdir -p /var/run/user/$(id -u)
# chmod 0700 /var/run/user/$(id -u)

# # Ensure gnome-keyring-daemon is installed and configured
# apt install -y gnome-keyring

# # Configure PAM for XRDP sessions
# if [ -f /etc/pam.d/xrdp-sesman ]; then
#     if ! grep -q "auth optional pam_gnome_keyring.so" /etc/pam.d/xrdp-sesman; then
#         echo "auth optional pam_gnome_keyring.so" >> /etc/pam.d/xrdp-sesman
#     fi
#     if ! grep -q "session optional pam_gnome_keyring.so auto_start" /etc/pam.d/xrdp-sesman; then
#         echo "session optional pam_gnome_keyring.so auto_start" >> /etc/pam.d/xrdp-sesman
#     fi
# fi

#
# End XRDP
###############################################################################
###############################################################################
# Disable auto login
#

# Disable GDM auto login if configured
if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sed -i 's/^AutomaticLogin=.*/# AutomaticLogin=/' /etc/gdm3/custom.conf
fi

# # Disable LightDM auto login if configured
# if [ -f /etc/lightdm/lightdm.conf ]; then
#     sed -i 's/^autologin-user=.*/# autologin-user=/' /etc/lightdm/lightdm.conf
#     sed -i 's/^autologin-user-timeout=.*/# autologin-user-timeout=/' /etc/lightdm/lightdm.conf
# fi

 
# Configure XFCE session for better compatibility
# mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml

# # Set XFCE as default session for all users
# update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/bin/startxfce4 50
# update-alternatives --set x-session-manager /usr/bin/startxfce4

# # Ensure XFCE session files are properly configured
# if [ ! -f /usr/share/xsessions/xfce.desktop ]; then
#     cat > /usr/share/xsessions/xfce.desktop << 'EOF'
# [Desktop Entry]
# Name=Xfce Session
# Comment=Use this session to run Xfce as your desktop environment
# Exec=startxfce4
# Type=XSession
# DesktopNames=XFCE
# EOF
# fi

echo "Install is complete."
echo "Reboot your machine to begin using XRDP."
echo "XRDP will now use XFCE desktop which is more compatible with remote sessions."
