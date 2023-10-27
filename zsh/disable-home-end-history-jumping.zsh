# Disable grml zshrc's default that pressing "Home"/"End" twice
# jumps to the beginning of the history
# (thrice if in a multi-line buffer).
#
# This is because it's easy to accidentally trigger this,
# this functionality is rarely useful,
# and it still has its own keybinding (`Esc` - `<`/`>`).
#
# Uses a modified version of the code added in
# * https://github.com/grml/grml-etc-core/commit/9cb24cf7f6145fe2ac9f0d55e07952ed4d948bcf
# * https://www.zsh.org/mla/workers/2011/msg00873.html
function beginning-or-end-of-line-or-buffer () {
    local hno=$HISTNO
    # We want to disable the "-or-history" part of
    # `beginning/end-of-buffer-or-history`.
    #
    # For that, we call beginning/end-of-buffer-or-history only if we're
    # not at the beginning/end of the line; this effectively
    # turns it into beginning/end-of-buffer
    # (which does not exist standalone in zsh currently),
    # because the `-or-history` part only triggeres precisely
    # when we're at the begnning/end of the line.
    if [[ ( "${LBUFFER[-1]}" == $'\n' && "${WIDGET}" == beginning-of* ) || \
      ( "${RBUFFER[1]}" == $'\n' && "${WIDGET}" == end-of* ) ]]; then
        zle .${WIDGET:s/somewhere/buffer-or-history/} "$@" # Effectively only `buffer`, see above.
    else
        zle .${WIDGET:s/somewhere/line/} "$@"
    fi
}
zle -N beginning-of-somewhere beginning-or-end-of-line-or-buffer
zle -N end-of-somewhere beginning-or-end-of-line-or-buffer
