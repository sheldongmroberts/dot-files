# -*- mode: sh -*-

alias s='git status'
alias S='git status --short'
alias gsu='git submodule update --init --recursive'
alias gpf='git push --force-with-lease'
alias grc='git rebase --continue'
alias l='git fetch --all; git log --all --graph --oneline --decorate'

alias sR='git status --short; git submodule foreach --recursive "git status --short || :" | grep --color=none -B 1 -v Entering'
alias gsl="git stash list | grep stash; git submodule foreach --recursive 'git stash list || :' | grep -B 1 stash"
alias gsS="git stash -uq; git submodule --quiet foreach --recursive 'git stash -uq || :'; gsl"
alias gsP="(git stash list | grep -q stash) && git stash pop -q; git submodule --quiet foreach --recursive '((git stash list | grep -q stash) && git stash pop -q) || :'; sR"
alias gsDROP="git stash drop; git submodule foreach --recursive 'git stash drop || :'; gsl"
alias gsPRUNE="git fetch --prune --all && git submodule foreach --recursive 'git fetch --prune --all || :'"
alias gsCLEAN="git restore . && git clean -ffd && git submodule update --recursive --init && git submodule foreach --recursive 'git restore . && git clean -ffd'"
