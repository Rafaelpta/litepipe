#!/bin/bash
# +extension GLX so software OpenGL via llvmpipe has somewhere to land.
# WebKit2GTK 4.1 needs SOME GL backing even with LIBGL_ALWAYS_SOFTWARE=1
# and WEBKIT_DISABLE_COMPOSITING_MODE=1 set; without GLX in the X server,
# WebProcess/Network/WebLoaderStrategy.cpp aborts the first navigation
# with internallyFailedLoadTimerFired() and the Tauri webview never
# renders the app (every spec then fails its before-all hook on
# openHomeWindow()).
# +extension RANDR is default in modern Xvfb but explicit is safer
# across Ubuntu LTS versions on GitHub's hosted runners.
Xvfb :99 -ac -screen 0 1920x1080x24 +extension GLX +extension RANDR &
echo "DISPLAY=:99" >> $GITHUB_ENV
sleep 3
export DISPLAY=:99
mkdir -p ~/.config/openbox
echo '<openbox_config><menu><file>menu.xml</file></menu></openbox_config>' > ~/.config/openbox/rc.xml
openbox --config-file ~/.config/openbox/rc.xml &
sleep 3
xterm -fa 'Liberation Mono' -fs 10 -e "while true; do echo 'Keeping xterm open'; sleep 60; done" &
sleep 3
xdpyinfo || echo "xdpyinfo failed"
xrandr || echo "xrandr failed"
xwininfo -root -children || echo "xwininfo failed"
