# ============================================================
#  Per-shell bash history  —  source this from ~/.bashrc
#  Example add following line to ~/.bashrc
#   source "${HOME}/.bash-scripts/bash_history.sh"
# ============================================================

HISTDIR="${HOME}/.bash_history.d"

# --- 1. one history file per interactive shell --------------
# Guarded so re-sourcing (e.g. from both /etc/bash.bashrc and ~/.bashrc) does not
# pick a new HISTFILE or stack duplicate PROMPT_COMMAND entries.
if [[ $- == *i* && -z ${_AI_HIST_DONE:-} ]]; then
    _AI_HIST_DONE=1
    mkdir -p "$HISTDIR" && chmod 700 "$HISTDIR"

    _tty=$(tty 2>/dev/null | sed 's|^/dev/||; s|/|-|g')
    HISTFILE="$HISTDIR/$(date +%Y-%m-%d_%H%M%S).$$.${_tty:-notty}.hist"
    unset _tty

    HISTSIZE=100000          # in-memory lines
    HISTFILESIZE=-1          # negative = never truncate the file
    HISTTIMEFORMAT='%F %T '  # also makes bash write "#<epoch>" lines to disk
    HISTCONTROL=ignoredups
    shopt -s histappend cmdhist

    # flush after every prompt, so nothing is lost if the shell is killed
    PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

    # don't leave behind files for shells where nothing was typed
    trap '[[ -s "$HISTFILE" ]] || rm -f "$HISTFILE"' EXIT
fi

# --- 2. list the stored sessions ----------------------------
hist-ls() {
    local f n
    for f in "$HISTDIR"/*.hist; do
        [[ -e $f ]] || { echo "no history files yet" >&2; return 1; }
        n=$(grep -cv '^#' "$f")
        printf '%s  %6d cmds  %s\n' \
               "$(date -r "$f" '+%F %T')" "$n" "${f##*/}"
    done | sort
}

# --- 3. search across all sessions --------------------------
# usage: hist-grep <extended-regex>
hist-grep() {
    [[ $# -ge 1 ]] || { echo "usage: hist-grep <regex>" >&2; return 2; }
    awk -v pat="$1" '
        /^#[0-9]+$/ { ts = substr($0, 2); next }
        $0 ~ pat {
            printf "%s  %-40s  %s\n",
                   (ts ? strftime("%F %T", ts) : "----------- --------"),
                   substr(FILENAME, match(FILENAME, /[^/]+$/)),
                   $0
        }
    ' "$HISTDIR"/*.hist | sort
}

# interactive fuzzy search over every session (needs fzf)
hist-fzf() {
    grep -hv '^#' "$HISTDIR"/*.hist | tac | awk '!seen[$0]++' \
        | fzf --no-sort --height 60% --reverse
}

# reload one old session into the current shell (arrow keys / Ctrl-R)
# usage: hist-load 2026-08-07_101500.4711.pts-3.hist
hist-load() { history -r "$HISTDIR/$1"; }

# housekeeping: drop sessions older than N days (default 365)
hist-prune() { find "$HISTDIR" -name '*.hist' -mtime "+${1:-365}" -delete; }
