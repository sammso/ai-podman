#!/bin/bash
# Wire the container terminal prompt + per-shell bash history into every interactive
# shell. The snippets live in /etc/ai-dev/bash/ and are sourced from both
# /etc/bash.bashrc (covers homes without our dotfiles, e.g. /work under --persist-work) AND the
# end of each ~/.bashrc (Ubuntu's stock ~/.bashrc sets PS1 after /etc/bash.bashrc, so
# ours must run last to win). The snippets are idempotent, so double-sourcing is safe.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# fzf powers hist-fzf (fuzzy search across sessions)
apt-get update
apt-get install -y --no-install-recommends fzf
apt-get clean
rm -rf /var/lib/apt/lists/*

read -r -d '' SNIPPET <<'EOF' || true

# ai-dev: per-shell history + git-aware prompt with container title, then the first-shell
# tools banner (welcome.sh runs last so it prints above the first prompt).
for _ai_rc in /etc/ai-dev/bash/bash_history.sh /etc/ai-dev/bash/terminal_prompt.sh /etc/ai-dev/bash/welcome.sh; do
    [ -r "$_ai_rc" ] && . "$_ai_rc"
done
unset _ai_rc
EOF

# Append to the system rc and every skeleton/existing ~/.bashrc (idempotent).
for RC in /etc/bash.bashrc /etc/skel/.bashrc /root/.bashrc /home/ubuntu/.bashrc; do
    [ -f "$RC" ] || continue
    grep -q '/etc/ai-dev/bash/terminal_prompt.sh' "$RC" || printf '%s\n' "$SNIPPET" >> "$RC"
done
