------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "eDP-2",          -- check with: hyprctl monitors
    mode     = "1920x1080@144",  -- or "highrr" for max refresh
    position = "auto",
    scale    = 1,
})   

-- Workspaces 1-5
hl.workspace_rule({ workspace = "1", monitor = "eDP-2", persistent = true})
hl.workspace_rule({ workspace = "2", monitor = "eDP-2", persistent = true})
hl.workspace_rule({ workspace = "3", monitor = "eDP-2", persistent = true})
hl.workspace_rule({ workspace = "4", monitor = "eDP-2", persistent = true})
hl.workspace_rule({ workspace = "5", monitor = "eDP-2", persistent = true})