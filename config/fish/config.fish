if status is-interactive
    # Commands to run in interactive sessions can go here
    set fish_greeting

    # eza replaces ls
    alias ls="eza -l --color=auto --icons"
    alias grep="grep --color=auto"

    # Initialize Starship for Fish
    starship init fish | source
end

fish_add_path $HOME/.local/bin
