# ~/.zshenv — sourced for ALL zsh invocations, including NON-interactive ones
# (cron, scp, VS Code Remote, MCP child processes, `zsh -c '...'`, git hooks).
#
# PATH tweaks that must apply everywhere belong HERE, not in ~/.zshrc: that file
# returns early for non-interactive shells, so anything it sets is invisible to
# them. This is exactly why user-local tools (gh, ghx, pipx apps) were "command
# not found" from non-interactive shells until this file existed.

# Put user-local bins on PATH for every zsh invocation.
# `typeset -U path` keeps PATH de-duplicated even when ~/.zshrc also lists them.
typeset -U path
path=("$HOME/.local/bin" "$HOME/bin" $path)
export PATH
