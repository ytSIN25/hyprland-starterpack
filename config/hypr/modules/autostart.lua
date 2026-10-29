-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
 hl.on("hyprland.start", function ()
    -- Optional: expose the session over VNC (install wayvnc and put your IP in)
    --hl.exec_cmd("until ip -4 addr | grep -q <YOUR-VNC-IP>; do sleep 1; done; wayvnc")
    --hl.exec_cmd("waybar")
    --hl.exec_cmd("swaync")
    -- Wallpaper daemon only: Quickshell sets the image (and the matching theme)
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("hypridle")
    --hl.exec_cmd("swayosd-server")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("quickshell")
    -- First login after ./install.sh: open the starter pack guide once
    hl.exec_cmd("f=~/.config/starterpack/show-guide; [ -f $f ] && rm $f && sleep 3 && xdg-open ~/.config/starterpack/guide.html")
    --hl.exec_cmd("mpvpaper -o 'loop=inf' eDP-1 ~/.images/lenovowallpaper.mp4")
    hl.dispatch(hl.dsp.focus({ workspace = "1" }))
 end)