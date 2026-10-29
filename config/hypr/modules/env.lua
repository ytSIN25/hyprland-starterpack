-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_SIZE", "32")

-- Toolkit backend
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Qt
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Nvidia
-- LIBVA_DRIVER_NAME is left unset: the screen runs on the Intel iGPU, and forcing
-- "nvidia" broke VA-API there (gpu-screen-recorder, browser video decode).
-- libva picks iHD for Intel and nvidia for the dGPU on its own.
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- __GLX_VENDOR_LIBRARY_NAME is left unset too: set globally to "nvidia" it put
-- every X11/XWayland app on the dGPU, overriding the bar's GPU offload toggle.
-- Per-app offload is handled by Services/GpuOffload.qml in quickshell.
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

-- Keyboard Languages
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("INPUT_METHOD", "fcitx")
hl.env("SDL_IM_MODULE", "fcitx")

-- Cursor Theme
hl.env("XCURSOR_THEME", "Keqing")
-- HYPRCURSOR_THEME intentionally unset: Keqing ships only xcursor
-- data, so Hyprland must fall back to XCURSOR_THEME above.