# shellcheck shell=bash
# ai-dev: show the per-kit tools banner once, on the first interactive shell after the
# container starts. Sourced from /etc/bash.bashrc + ~/.bashrc (see install-terminal.sh).
#
# The marker lives in /dev/shm — a tmpfs recreated when the container starts — so the banner
# reappears after a stop/start but not on reconnects or subshells. `mkdir` is atomic, so if two
# shells race only one prints. Set AI_TOOLS_QUIET=1 to suppress it.
if [[ $- == *i* && -z ${AI_TOOLS_QUIET:-} ]] && command -v tools >/dev/null 2>&1; then
    if mkdir /dev/shm/.ai-tools-shown 2>/dev/null || mkdir /tmp/.ai-tools-shown 2>/dev/null; then
        tools
    fi
fi
