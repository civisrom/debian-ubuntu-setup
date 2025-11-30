# Добавьте эту проверку в начале .zshrc
if [[ $- != *i* ]]; then
    return  # Выход из скрипта, если сессия неинтерактивная
fi
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="fletcherm"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions dirhistory history history-substring-search docker docker-compose zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

clone_xtables_push() {
  local repo_name="xtables-addons"
  local repo_dir="$HOME/$repo_name"
  
  # Проверяем, существует ли папка с репозиторием
  if [ -d "$repo_dir" ]; then
    echo "⚠️ Директория $repo_dir уже существует. Переходим в неё..."
    cd $repo_dir || return 1
    # Получаем последние изменения из Codeberg
    git fetch origin
    git pull origin master || git pull origin main
  else
    echo "🔽 Клонируем $repo_name с Codeberg..."
    git clone https://codeberg.org/jengelh/$repo_name.git || return 1
    cd $repo_name || return 1
  fi

  echo "🔄 Перенастраиваем origin на SSH GitHub..."
  git remote remove origin
  git remote add origin git@github.com:civisrom/$repo_name.git

  # Проверяем наличие изменений
  if [ -n "$(git status --porcelain)" ]; then
    echo "🔄 Есть изменения, создаём новый commit..."
    git add .
    git commit -m "Автоматический commit: $(date '+%Y-%m-%d %H:%M:%S')"
    git push -u origin master || git push -u origin main
    echo "🚀 Пушим изменения в GitHub."
  else
    echo "ℹ️ Изменений нет — push не выполняется."
  fi

  echo "📌 origin:"
  git remote -v
}


git_update_push() {
    # Проверяем, что находимся в git-репозитории
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo '❌ Not inside a Git repository!'
        return 1
    fi

    # Обновляем локальную ветку
    echo '?? Pulling latest changes...'
    if ! git pull --no-rebase origin $(git branch --show-current); then
        echo '❌ Git pull failed!'
        return 1
    fi

    # Проверяем статус репозитория
    if git diff --quiet && git diff --cached --quiet; then
        echo '✅ No changes to commit.'
        return 0
    fi

    # Добавляем файлы
    echo '?? Staging changes...'
    git add .

    # Коммитим изменения с сообщением о времени
    COMMIT_MSG="Auto-update: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "?? Committing changes: '$COMMIT_MSG'"
    if ! git commit -m "$COMMIT_MSG"; then
        echo '❌ Commit failed!'
        return 1
    fi

    # Отправляем изменения
    echo '?? Pushing to remote...'
    if ! git push origin $(git branch --show-current); then
        echo '❌ Push failed!'
        return 1
    fi

    echo '?? Successfully pushed changes!'
}

HISTFILE=~/.zsh_history
HISTSIZE=999999999
SAVEHIST=$HISTSIZE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor root)
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PATH=$PATH:/usr/local/bin
export PATH=$PATH:/usr/local/go/bin
#alias saveip="sudo bash -c 'iptables-save > /etc/iptables/rules.v4 && ip6tables-save > /etc/iptables/rules.v6 && ipset save > /etc/ipset/ipset.rules'"
export GOPATH=$HOME/goproject
export PATH=$PATH:$GOPATH/bin
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export EDITOR=nano
export VISUAL=nano
