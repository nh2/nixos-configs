# Make normal Ctrl+{W/Left/Right} operate on whole words.
WORDCHARS='*?_-.[]~=/&;!#$%^(){}<>'

# Make Alt+Backspace delete on word segments
backward-kill-dir () {
    local WORDCHARS=${WORDCHARS/\/}
    zle backward-kill-word
    zle -f kill
}
zle -N backward-kill-dir
bindkey '^[^?' backward-kill-dir


# Note:
# The below are different than
#    bindkey "^[[1;3C" forward-word
#    bindkey "^[[1;3D" backward-word
# because that needs 2 jumps to jump over a '/'
# while the below needs only 1.

# Make Alt+Left operate on path segments.
backward-word-dir () {
    local WORDCHARS=${WORDCHARS/\/}
    zle backward-word
}
zle -N backward-word-dir
bindkey "^[[1;3C" forward-word-dir

# Make Alt+Right operate on path segments.
forward-word-dir () {
    local WORDCHARS=${WORDCHARS/\/}
    zle forward-word
}
zle -N forward-word-dir
bindkey "^[[1;3D" backward-word-dir

