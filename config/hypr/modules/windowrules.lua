--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.layer_rule({
    name = "rofi-popup",
    match = { namespace = "rofi"},
    animation = "slide bottom",
    dim_around = true,
})

hl.layer_rule({
    name = "notification-animations",
    match = { namespace = "swaync-control-center"},
    animation = "slide right",
})
-- Duolingo como panel de Quickshell: ventana --app de Chromium flotante bajo
-- la barra, en un special workspace que el botón del bar muestra/oculta.
hl.window_rule({
    name  = "duolingo-panel",
    match = { class = "^chrome-www\\.duolingo\\.com__learn-Default$" },

    float     = true,
    size      = "520 990",
    move      = "1388 56",
    workspace = "special:duolingo silent",
})
