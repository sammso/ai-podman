# ============================================================
#  Terminal prompt with git branch  —  source this from ~/.bashrc
#  Example add following line to ~/.bashrc
#   source "${HOME}/.bash-scripts/terminal_prompt.sh"
# ============================================================

if [[ $- == *i* ]]; then

    # git-aware prompt helper; provides __git_ps1. Path varies by distro:
    # Ubuntu/Debian ship it with git, Fedora ships it in git-core contrib.
    for GIT_PROMPT_PATH in \
        /usr/lib/git-core/git-sh-prompt \
        /etc/bash_completion.d/git-prompt \
        /usr/share/git-core/contrib/completion/git-prompt.sh; do
        if [ -f "$GIT_PROMPT_PATH" ]; then
            . "$GIT_PROMPT_PATH"
            break
        fi
    done

    # podman environment name shown in the prompt: the file ~/.podman_env (first line)
    # overrides the default, which is the kit name AI_KIT (set by run-sandboxed.sh), then
    # "podman". Ends in printf (exit 0) so it never leaks a nonzero $? into the prompt.
    _podman_env() {
        local n=""
        [[ -r "$HOME/.podman_env" ]] && read -r n < "$HOME/.podman_env"
        printf '%s' "${n:-${AI_KIT:-podman}}"
    }
    PODMAN_ENV="$(_podman_env)"

    # refresh env name + git branch before every prompt; append so other PROMPT_COMMAND
    # users (e.g. bash_history.sh) keep working. Guarded so re-sourcing does not stack
    # duplicates; PS1 itself is (re)set every time below so it wins over a ~/.bashrc
    # default sourced before us.
    if [[ -z ${_AI_PROMPT_DONE:-} ]]; then
        _AI_PROMPT_DONE=1
        _pc='PODMAN_ENV=$(_podman_env)'
        if declare -F __git_ps1 >/dev/null; then
            _pc="$_pc"'; PS1_CMD1=$(__git_ps1 " (%s)")'
        else
            PS1_CMD1=''
        fi
        PROMPT_COMMAND="${_pc}${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
        unset _pc
    fi

    # Window/tab title: "<podman-env>:<cwd>", using the same PODMAN_ENV as the prompt;
    # falls back to the hostname (\h) when empty. Parameter expansion runs before bash
    # processes \h, so the fallback works.
    PS1_TITLE='\[\e]0;${PODMAN_ENV:-\h}:\w\a\]'

    # <title>HHMMSS:podman-env(history#) (git-branch):cwd
    # #:
    PS1="${PS1_TITLE}"'\[\e[1m\]\D{%H%M%S}\[\e[0m\]:${PODMAN_ENV}(\!)\[\e[38;5;214;1m\]${PS1_CMD1}\[\e[0m\]:\[\e[38;5;118m\]\w\n\[\e[0m\]#:'
fi
