#!/bin/bash
# diagnostic.sh - Check current system state

echo "=== System Diagnostic ==="
echo "GNOME Version: $(gnome-shell --version 2>/dev/null || echo "Not found")"
echo "GDM Version: $(gdm --version 2>/dev/null || echo "Not found")"
echo "Mutter Version: $(mutter --version 2>/dev/null || echo "Not found")"
echo ""

echo "=== Current Sessions Available ==="
ls /usr/share/xsessions/ 2>/dev/null || echo "No session files found"
echo ""

echo "=== GDM Configuration ==="
cat /etc/gdm3/custom.conf 2>/dev/null || echo "No custom GDM config"
echo ""

echo "=== Wayland vs X11 ==="
echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-Not set}"
echo ""

echo "=== Testing Meson Directly ==="
mkdir -p /tmp/test-meson
cd /tmp/test-meson
cat > meson.build << 'EOF'
project('test', 'c')
option('x11', type: 'feature', value: 'enabled')
message('Options test completed')
EOF

if meson setup build 2>&1 | grep -i "option\|error\|warning"; then
    echo "Meson test completed"
else
    echo "Meson test failed"
fi