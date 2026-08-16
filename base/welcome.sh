# shellcheck shell=bash
# ai-dev: show the per-kit tools banner once, on the first interactive shell after the
# container starts. Sourced from /etc/bash.bashrc + ~/.bashrc (see install-terminal.sh).
#
# Two guards, because an interactive bash sources BOTH rc files (so this runs twice per shell):
#   * _AI_WELCOME_DONE (a plain shell var) stops the second source in the SAME shell.
#   * a marker dir stops later shells — it lives in /dev/shm, a tmpfs recreated when the
#     container starts, so the banner reappears after a stop/start but not on reconnects.
# `mkdir` is atomic, so racing shells still print only once. Set AI_TOOLS_QUIET=1 to suppress.
if [[ $- == *i* && -z ${AI_TOOLS_QUIET:-} && -z ${_AI_WELCOME_DONE:-} ]] \
        && command -v tools >/dev/null 2>&1; then
    _AI_WELCOME_DONE=1
    _ai_marker=/dev/shm/.ai-tools-shown
    [[ -d /dev/shm && -w /dev/shm ]] || _ai_marker="${TMPDIR:-/tmp}/.ai-tools-shown"
    mkdir "$_ai_marker" 2>/dev/null && tools
    unset _ai_marker
fi
