#!/bin/bash

# Configuration
WALL_DIR="$HOME/.images"
# Use 'rofi -dmenu' with a custom prompt
ROFI_CMD="rofi -dmenu -i -p "󰸉 Wallpapers""

# 1. Get a list of image files (basenames only for the menu)
# If you want full paths in rofi, remove the 'basename' step, but this keeps it clean.
CHOICE=$(find "$WALL_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -exec basename {} \; | $ROFI_CMD)

# Exit if no selection was made (e.g., user pressed Esc)
if [ -z "$CHOICE" ]; then
    exit 0
fi

# Reconstruct the full path
FULL_PATH="$WALL_DIR/$CHOICE"

# 2. Apply the wallpaper
# ---- IF YOU USE HYPRPAPER ----
hyprpaper preload "$FULL_PATH"
hyprpaper wallpaper ",$FULL_PATH"
# Clean up older unloads if your memory builds up:
# hyprctl hyprpaper unload all

# ---- IF YOU USE SWWW (Uncomment below and comment out hyprpaper) ----
# swww img "$FULL_PATH" --transition-type fade
