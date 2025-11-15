#!/bin/bash

# GNOME X11 Build Script - Simplified Version
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BUILD_DIR="$HOME/gnome-x11-build"
PKG_BUILD_DIR="$BUILD_DIR/pkgbuild"
mkdir -p "$BUILD_DIR" "$PKG_BUILD_DIR"

install_dependencies() {
    print_status "Installing build dependencies..."
    sudo apt update
    sudo apt install -y \
        build-essential meson ninja-build pkg-config gettext \
        libgirepository1.0-dev libglib2.0-dev libgtk-4-dev \
        libgraphene-1.0-dev libjson-glib-dev libpango1.0-dev \
        libcairo2-dev libx11-dev libxext-dev libxi-dev libxtst-dev \
        libxfixes-dev libxcomposite-dev libxdamage-dev libxrandr-dev \
        libxinerama-dev libxcursor-dev libxkbcommon-dev libxkbcommon-x11-dev \
        libinput-dev libsystemd-dev libgudev-1.0-dev libpipewire-0.3-dev \
        libpulse-dev libcanberra-dev gobject-introspection libdrm-dev \
        libgbm-dev libegl-dev libgles2 libwayland-dev wayland-protocols \
        xwayland git
}

# Function to discover correct meson options
discover_meson_options() {
    local component="$1"
    local repo_url="$2"
    
    print_status "Discovering meson options for $component..."
    
    cd "$PKG_BUILD_DIR"
    if [ ! -d "$component" ]; then
        git clone "$repo_url" "$component"
    fi
    
    cd "$component"
    git checkout main 2>/dev/null || git checkout gnome-49 2>/dev/null || true
    git pull
    
    # Create a minimal build to see available options
    mkdir -p build
    cd build
    
    print_status "Available meson options for $component:"
    meson .. --help 2>&1 | grep -A 50 "Project-specific options" | head -30 || true
    
    # Try a basic configuration to see what works
    print_status "Testing basic configuration..."
    if meson .. 2>&1 | grep -E "Option|Value|Possible|error"; then
        print_status "Basic configuration successful"
    else
        print_warning "Basic configuration failed, checking meson.build..."
    fi
    
    cd ../..
}

# Build components with discovered options
build_mutter() {
    print_status "Building mutter..."
    
    cd "$PKG_BUILD_DIR/mutter"
    
    # Try different option combinations
    local meson_options=(
        "-Dx11=true"
        "-Dx11=enabled" 
        "-Dx11_egl_stream=true"
        "-Dxwayland=true"
        "-Dxwayland=enabled"
    )
    
    for option in "${meson_options[@]}"; do
        print_status "Trying option: $option"
        rm -rf build
        mkdir build
        cd build
        
        if meson setup .. --prefix=/usr --buildtype=release $option 2>/dev/null; then
            print_status "Configuration successful with: $option"
            break
        else
            print_warning "Failed with: $option"
            cd ..
        fi
    done
    
    cd build
    ninja
    sudo ninja install
}

build_gdm() {
    print_status "Building GDM..."
    
    cd "$PKG_BUILD_DIR/gdm"
    rm -rf build
    mkdir build
    cd build
    
    # Try different X11 option names
    if ! meson setup .. --prefix=/usr --buildtype=release -Dx11=true 2>/dev/null; then
        rm -rf ../build
        mkdir ../build
        cd ../build
        meson setup .. --prefix=/usr --buildtype=release -Dx11-support=true
    fi
    
    ninja
    sudo ninja install
}

build_gnome_session() {
    print_status "Building gnome-session..."
    
    cd "$PKG_BUILD_DIR/gnome-session"
    rm -rf build
    mkdir build
    cd build
    
    meson setup .. --prefix=/usr --buildtype=release -Dx11=true
    ninja
    sudo ninja install
}

build_gnome_shell() {
    print_status "Building gnome-shell..."
    
    cd "$PKG_BUILD_DIR/gnome-shell"
    rm -rf build
    mkdir build
    cd build
    
    meson setup .. --prefix=/usr --buildtype=release
    ninja
    sudo ninja install
}

# Main functions
discover_all_options() {
    print_status "Discovering all meson options..."
    
    discover_meson_options "mutter" "https://gitlab.gnome.org/GNOME/mutter.git"
    discover_meson_options "gdm" "https://gitlab.gnome.org/GNOME/gdm.git"
    discover_meson_options "gnome-session" "https://gitlab.gnome.org/GNOME/gnome-session.git"
    discover_meson_options "gnome-shell" "https://gitlab.gnome.org/GNOME/gnome-shell.git"
}

build_all() {
    print_status "Starting build process..."
    
    install_dependencies
    
    # Clone all repos first
    cd "$PKG_BUILD_DIR"
    git clone https://gitlab.gnome.org/GNOME/mutter.git || true
    git clone https://gitlab.gnome.org/GNOME/gdm.git || true
    git clone https://gitlab.gnome.org/GNOME/gnome-session.git || true
    git clone https://gitlab.gnome.org/GNOME/gnome-shell.git || true
    
    # Build in order
    build_mutter
    build_gdm
    build_gnome_session
    build_gnome_shell
    
    # Configure system
    sudo tee /etc/gdm3/custom.conf > /dev/null << 'EOF'
[daemon]
WaylandEnable=false
EOF

    sudo tee /usr/share/xsessions/gnome-x11.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=GNOME on X11
Comment=GNOME with X11 session
Exec=gnome-session
Type=XSession
DesktopNames=GNOME
EOF

    sudo glib-compile-schemas /usr/share/glib-2.0/schemas/
    print_status "Build completed! Please reboot."
}

case "${1:-build}" in
    "discover")
        discover_all_options
        ;;
    "build")
        build_all
        ;;
    *)
        echo "Usage: $0 [discover|build]"
        echo "  discover - Find correct meson options"
        echo "  build    - Build with discovered options"
        ;;
esac