# AI dev sandboxes — shell integration.
# Source this from ~/.bashrc:
#     source /path/to/podman/ai/podman/sandbox.bashrc
# Then use `sb` to manage named sandboxes (Tab-completes subcommands and names).

_SB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_SB_PREFIX="aidev-"   # mirrors SANDBOX_PREFIX in lib-sandbox.sh

# Bare sandbox names (prefix stripped) for listing/completion.
_sb_names() {
    podman ps -a --filter "name=^${_SB_PREFIX}" --format '{{.Names}}' 2>/dev/null \
        | sed "s/^${_SB_PREFIX}//"
}

_sb_help() {
    cat <<EOF
sb - manage AI dev sandboxes

  sb                     list sandboxes (same as: sb list)
  sb <name>              connect to (or create) a sandbox
  sb connect <name>      same, explicit (use if <name> clashes with a subcommand)
  sb stop <name>         stop a sandbox (keeps it; reconnect restarts)
  sb rm <name>           stop and remove a sandbox
  sb run <args...>       one-shot run-sandboxed.sh passthrough
  sb list | ls           list sandboxes with status
  sb help                this text
EOF
}

sb() {
    local cmd="${1:-list}"
    case "$cmd" in
        list|ls)
            podman ps -a --filter "name=^${_SB_PREFIX}" \
                --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | sed "s/${_SB_PREFIX}//"
            ;;
        connect|c)      shift; "$_SB_DIR/connect-sandboxed.sh" "$@" ;;
        stop)           shift; "$_SB_DIR/stop-sandboxed.sh" "$@" ;;
        rm|remove)      shift; "$_SB_DIR/stop-sandboxed.sh" --rm "$@" ;;
        run)            shift; "$_SB_DIR/run-sandboxed.sh" "$@" ;;
        help|-h|--help) _sb_help ;;
        *)              "$_SB_DIR/connect-sandboxed.sh" "$cmd" ;;   # `sb <name>` = connect
    esac
}

_sb_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ $COMP_CWORD -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "list ls connect stop rm run help $(_sb_names)" -- "$cur")
    else
        case "${COMP_WORDS[1]}" in
            connect|c|stop|rm|remove)
                mapfile -t COMPREPLY < <(compgen -W "$(_sb_names)" -- "$cur") ;;
            run)
                mapfile -t COMPREPLY < <(compgen -W "base java dev android node --gui --persist-work --host-network" -- "$cur") ;;
            *) COMPREPLY=() ;;
        esac
    fi
}
complete -F _sb_complete sb
