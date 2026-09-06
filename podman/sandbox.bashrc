# shellcheck shell=bash
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

# Kit of a named sandbox, from its image (localhost/ai-<kit>:latest -> <kit>); empty if unknown.
_sb_kit_of() {
    local img
    img=$(podman inspect -f '{{.ImageName}}' "${_SB_PREFIX}$1" 2>/dev/null) || return 1
    img="${img##*/}"        # ai-java:latest
    img="${img%:*}"         # ai-java
    printf '%s' "${img#ai-}"
}

# GUI launcher commands available in a kit: base apps + kit extras.
_sb_gui_apps() {
    local base=(chrome claude-desktop chatgpt meld lite-xl wezterm)
    case "$1" in
        java)    printf '%s\n' "${base[@]}" idea ;;
        node)    printf '%s\n' "${base[@]}" code webstorm ;;
        android) printf '%s\n' "${base[@]}" studio ;;
        *)       printf '%s\n' "${base[@]}" ;;   # base, dev, unknown
    esac
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
  sb export              wizard: add a menu launcher for a GUI app in a sandbox
  sb export <args...>    export-app.sh passthrough (e.g. sb export --remove <name> <app>)
  sb list | ls           list sandboxes with status
  sb help                this text
EOF
}

# Interactive wizard: create a menu launcher for a GUI app in a named sandbox.
_sb_export_wizard() {
    local names name kit apps app display start i flag
    mapfile -t names < <(_sb_names)
    if ((${#names[@]})); then
        echo "Sandboxes:"; printf '  %s\n' "${names[@]}"
    else
        echo "No sandboxes yet — create one first (e.g. sb <name>)." >&2
    fi
    read -rp "Sandbox name: " name || return 1
    [[ -n "$name" ]] || { echo "no name given" >&2; return 1; }

    if podman container exists "${_SB_PREFIX}${name}"; then
        kit=$(_sb_kit_of "$name")
        if ! podman inspect -f '{{range .Config.Env}}{{println .}}{{end}}' \
                "${_SB_PREFIX}${name}" 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; then
            echo "warning: sandbox '$name' was created without GUI — exec'd apps can't display." >&2
            echo "         recreate it with GUI:  sb rm $name && sb $name" >&2
        fi
    else
        echo "note: sandbox '$name' does not exist yet — its launchers will notify until you create it." >&2
        kit=""
    fi

    mapfile -t apps < <(_sb_gui_apps "$kit")
    echo "Apps${kit:+ (kit: $kit)}:"
    for i in "${!apps[@]}"; do printf '  %2d) %s\n' "$((i+1))" "${apps[$i]}"; done
    read -rp "App (name or number): " app || return 1
    [[ "$app" =~ ^[0-9]+$ ]] && app="${apps[$((app-1))]:-}"
    [[ -n "$app" ]] || { echo "no app given" >&2; return 1; }

    read -rp "Menu name [$app ($name)]: " display || true
    display="${display:-$app ($name)}"

    read -rp "Also add a 'Start $name' launcher? [Y/n] " start || true
    flag=(); case "${start:-Y}" in [Nn]*) flag=(--no-start) ;; esac

    "$_SB_DIR/export-app.sh" "${flag[@]}" "$name" "$app" "$display"
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
        export)         shift
                        if [[ $# -eq 0 ]]; then _sb_export_wizard
                        else "$_SB_DIR/export-app.sh" "$@"; fi ;;
        help|-h|--help) _sb_help ;;
        *)              "$_SB_DIR/connect-sandboxed.sh" "$cmd" ;;   # `sb <name>` = connect
    esac
}

_sb_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ $COMP_CWORD -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "list ls connect stop rm run export help $(_sb_names)" -- "$cur")
    else
        case "${COMP_WORDS[1]}" in
            connect|c|stop|rm|remove)
                mapfile -t COMPREPLY < <(compgen -W "$(_sb_names)" -- "$cur") ;;
            run)
                mapfile -t COMPREPLY < <(compgen -W "base java dev android node --gui --persist-work --host-network" -- "$cur") ;;
            export)
                if [[ $COMP_CWORD -eq 2 ]]; then
                    mapfile -t COMPREPLY < <(compgen -W "$(_sb_names) --remove --no-start" -- "$cur")
                elif [[ $COMP_CWORD -eq 3 ]]; then
                    mapfile -t COMPREPLY < <(compgen -W "$(_sb_gui_apps "$(_sb_kit_of "${COMP_WORDS[2]}" 2>/dev/null)")" -- "$cur")
                else COMPREPLY=(); fi ;;
            *) COMPREPLY=() ;;
        esac
    fi
}
complete -F _sb_complete sb
