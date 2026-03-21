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

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=$HISTSIZE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Shell options
setopt AUTO_CD
setopt CORRECT

# Syntax highlighting
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor root)
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down

# Environment
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/goproject
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOPATH/bin
export EDITOR=nano
export VISUAL=nano

# ============================================================================
# ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ (раскомментируйте нужное)
# ============================================================================

# --- Настройки Zsh -----------------------------------------------------------
# setopt NO_BEEP                    # отключить звуковые сигналы терминала
# setopt GLOB_DOTS                  # включать dotfiles (.*) в glob-паттерны
# setopt EXTENDED_GLOB              # расширенные glob-паттерны (^, ~, #)
# WORDCHARS=''                      # Ctrl+W удаляет до /, а не весь путь целиком

# --- Дополнительные плагины Oh My Zsh ----------------------------------------
# Добавьте в массив plugins=(...) выше:
# sudo                              # двойное нажатие Esc — добавить sudo к команде
# extract                           # универсальная распаковка: extract archive.tar.gz
# colored-man-pages                 # цветные man-страницы для удобного чтения

# --- Навигация и файлы -------------------------------------------------------
# alias ..='cd ..'                  # быстрый подъём на уровень вверх
# alias ...='cd ../..'              # подъём на два уровня вверх
# alias ....='cd ../../..'          # подъём на три уровня вверх
# alias mkdir='mkdir -pv'           # создавать вложенные директории + показывать
# alias cp='cp -iv'                 # подтверждение перед перезаписью при копировании
# alias mv='mv -iv'                 # подтверждение перед перезаписью при перемещении
# alias rm='rm -iv'                 # подтверждение перед удалением каждого файла

# --- Полезные функции --------------------------------------------------------
# # Создать директорию и сразу перейти в неё: mkcd my-new-project
# mkcd() { mkdir -p "$1" && cd "$1" }
#
# # Быстрый бэкап файла с датой: backup /etc/nftables.conf
# backup() { cp "$1" "$1.backup.$(date +%Y%m%d-%H%M%S)~" }
#
# # Универсальная распаковка архивов: extract archive.tar.gz
# extract() {
#     if [[ -f "$1" ]]; then
#         case "$1" in
#             *.tar.bz2) tar xjf "$1"    ;;
#             *.tar.gz)  tar xzf "$1"    ;;
#             *.tar.xz)  tar xJf "$1"    ;;
#             *.bz2)     bunzip2 "$1"    ;;
#             *.gz)       gunzip "$1"     ;;
#             *.tar)     tar xf "$1"     ;;
#             *.tbz2)    tar xjf "$1"    ;;
#             *.tgz)     tar xzf "$1"    ;;
#             *.zip)     unzip "$1"      ;;
#             *.7z)      7z x "$1"       ;;
#             *.xz)      xz -d "$1"     ;;
#             *)         echo "'$1' — неизвестный формат архива" ;;
#         esac
#     else
#         echo "'$1' — файл не найден"
#     fi
# }

# --- Сеть и диагностика ------------------------------------------------------
# alias ping='ping -c 5'                        # пинг 5 пакетов (не бесконечно)
# alias myip='curl -s ifconfig.me'              # показать внешний IP-адрес
# alias localip="ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print \$2}'"  # все локальные IPv4 адреса
# alias ips="ip -br addr show"                  # краткий вывод всех интерфейсов и их IP
# alias ip4="ip -4 -br addr show"               # только IPv4 адреса (кратко)
# alias ip6="ip -6 -br addr show"               # только IPv6 адреса (кратко)
# alias gateway="ip route | grep default"       # показать шлюз по умолчанию
# alias routes="ip route show"                  # таблица маршрутизации
# alias dns="cat /etc/resolv.conf"              # текущие DNS-серверы
# alias listen='ss -tulnp | grep LISTEN'        # только слушающие порты (TCP + UDP)
# alias tcp-listen='ss -tlnp'                   # только TCP слушающие порты с PID процесса
# alias udp-listen='ss -ulnp'                   # только UDP слушающие порты с PID процесса
# alias connections='ss -tunap'                 # все активные TCP/UDP соединения с PID
# alias established='ss -tunap state established'  # только установленные соединения
# alias tcp-stats='ss -s'                       # статистика сокетов (всего/TCP/UDP/RAW)
# alias port-count='ss -tunap | awk "{print \$1}" | sort | uniq -c | sort -rn'  # кол-во соединений по типу
# alias arp='ip neighbour show'                 # ARP-таблица (MAC-адреса соседей)
# alias traffic='cat /proc/net/dev'             # статистика трафика по интерфейсам
# alias mtu="ip link show | grep mtu"           # MTU всех интерфейсов

# --- Systemd ------------------------------------------------------------------
# alias sc='sudo systemctl'                     # короткий вызов systemctl
# alias scs='sudo systemctl status'             # статус сервиса: scs nginx
# alias scr='sudo systemctl restart'            # перезапуск сервиса: scr nginx
# alias sce='sudo systemctl enable'             # включить автозапуск: sce nginx
# alias scd='sudo systemctl disable'            # отключить автозапуск: scd nginx
# alias scl='sudo systemctl list-units --type=service --state=running'  # список запущенных сервисов
# alias scf='sudo systemctl list-units --type=service --state=failed'   # список упавших сервисов
# alias jlog='sudo journalctl -xe'              # последние логи с контекстом и пояснениями
# alias jfu='sudo journalctl -fu'               # follow лог сервиса: jfu nginx
# alias jboot='sudo journalctl -b'              # логи с момента последней загрузки
# alias jyesterday='sudo journalctl --since yesterday'  # логи за вчера

# --- Docker -------------------------------------------------------------------
# alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'  # компактный список контейнеров
# alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'  # все контейнеры (вкл. остановленные)
# alias dlogs='docker logs -f --tail 100'       # последние 100 строк лога + follow: dlogs container
# alias dstats='docker stats --no-stream'       # ресурсы контейнеров (CPU/RAM/NET) однократно
# alias dprune='docker system prune -af'        # удалить всё неиспользуемое (образы, контейнеры, сети)
# alias dvols='docker volume ls'                # список Docker-томов
# alias dimages='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'  # список образов
# alias dstop='docker stop $(docker ps -q)'     # остановить все запущенные контейнеры
# alias drestart='docker restart $(docker ps -q)'  # перезапустить все контейнеры
#
# # IP-адреса всех запущенных контейнеров (имя + IP): docker-ips
# alias docker-ips='docker inspect $(docker ps -q) --format "{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" | sort'
#
# # Подробная информация о сетях контейнера: docker-nets container_name
# docker-nets() { docker inspect "$1" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}: {{$conf.IPAddress}}{{"\n"}}{{end}}' }
#
# # Войти в контейнер через bash: dexec container_name
# alias dexec='docker exec -it'
#
# # Список Docker-сетей с подсетями: docker-subnets
# alias docker-subnets='docker network ls -q | xargs -I{} docker network inspect {} --format "{{.Name}}: {{range .IPAM.Config}}{{.Subnet}}{{end}}"'

# --- Безопасность / nftables (дополнение) ------------------------------------
# alias nft-monitor='sudo nft monitor'                          # мониторинг изменений правил в реальном времени
# alias nft-handles='sudo nft list ruleset -a'                  # правила с хендлами (для удаления конкретного правила)
# alias nft-json='sudo nft -j list ruleset | python3 -m json.tool'  # правила в формате JSON (удобно для парсинга)
# alias nft-counters='sudo nft list ruleset | grep -E "counter|chain|table"'  # счётчики пакетов по правилам
# alias fail2ban-status='sudo fail2ban-client status'           # общий статус fail2ban
# alias fail2ban-ssh='sudo fail2ban-client status sshd'         # заблокированные IP для SSH
# alias banned='sudo fail2ban-client banned'                    # все заблокированные IP во всех jail

# ============================================================================

# System aliases
alias ll='ls -lah'
alias ports='ss -tulnp'
alias mem='free -h'
alias df='df -h'

# nftables aliases
alias nft-list='sudo nft list ruleset'                                          # показать все текущие правила
alias nft-check='sudo nft -c -f /etc/nftables.conf'                             # проверить синтаксис конфига без применения
alias nft-apply='sudo nft -f /etc/nftables.conf'                                # применить правила из конфига
alias nft-flush='sudo nft flush ruleset'                                        # очистить все правила (осторожно!)
alias nft-save='sudo sh -c "nft list ruleset > /etc/nftables.conf"'             # сохранить текущие правила в конфиг
alias nft-reload='sudo systemctl restart nftables'                              # перезапустить сервис nftables
alias nft-status='sudo systemctl status nftables'                               # статус сервиса nftables
alias nft-test='sudo nft -c -f /etc/nftables.conf && echo "✓ Синтаксис OK" || echo "✗ Ошибка в конфиге"'  # тест с выводом результата
