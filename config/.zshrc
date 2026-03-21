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
plugins=(git zsh-autosuggestions dirhistory history history-substring-search docker docker-compose zsh-syntax-highlighting sudo extract colored-man-pages)

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
alias ..='cd ..'                  # быстрый подъём на уровень вверх
alias ...='cd ../..'              # подъём на два уровня вверх
alias ....='cd ../../..'          # подъём на три уровня вверх
alias mkdir='mkdir -pv'           # создавать вложенные директории + показывать
alias cp='cp -iv'                 # подтверждение перед перезаписью при копировании
alias mv='mv -iv'                 # подтверждение перед перезаписью при перемещении
alias rm='rm -iv'                 # подтверждение перед удалением каждого файла

# --- Полезные функции --------------------------------------------------------
# # Создать директорию и сразу перейти в неё: mkcd my-new-project
mkcd() { mkdir -p "$1" && cd "$1" }
#
# # Быстрый бэкап файла с датой: backup /etc/nftables.conf
# backup() { cp "$1" "$1.backup.$(date +%Y%m%d-%H%M%S)~" }
#
# # Универсальная распаковка архивов: extract archive.tar.gz
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2) tar xjf "$1"    ;;
            *.tar.gz)  tar xzf "$1"    ;;
            *.tar.xz)  tar xJf "$1"    ;;
            *.bz2)     bunzip2 "$1"    ;;
            *.gz)       gunzip "$1"     ;;
            *.tar)     tar xf "$1"     ;;
            *.tbz2)    tar xjf "$1"    ;;
            *.tgz)     tar xzf "$1"    ;;
            *.zip)     unzip "$1"      ;;
            *.7z)      7z x "$1"       ;;
            *.xz)      xz -d "$1"     ;;
            *)         echo "'$1' — неизвестный формат архива" ;;
        esac
    else
        echo "'$1' — файл не найден"
    fi
}

# --- Сеть и диагностика ------------------------------------------------------
alias ipa='ip a'                              # полный вывод всех интерфейсов (ip addr show)
alias ping='ping -c 5'                        # пинг 5 пакетов (не бесконечно)
alias myip='curl -s ifconfig.me'              # показать внешний IP-адрес
# alias localip="ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print \$2}'"  # все локальные IPv4 адреса
alias ips="ip -br addr show"                  # краткий вывод всех интерфейсов и их IP
alias ip4="ip -4 -br addr show"               # только IPv4 адреса (кратко)
alias ip6="ip -6 -br addr show"               # только IPv6 адреса (кратко)
# alias gateway="ip route | grep default"       # показать шлюз по умолчанию
alias routes="ip route show"                  # таблица маршрутизации
alias dns="cat /etc/resolv.conf"              # текущие DNS-серверы
alias listen='ss -tulnp | grep LISTEN'        # только слушающие порты (TCP + UDP)
alias tcp-listen='ss -tlnp'                   # только TCP слушающие порты с PID процесса
alias udp-listen='ss -ulnp'                   # только UDP слушающие порты с PID процесса
alias connections='ss -tunap'                 # все активные TCP/UDP соединения с PID
alias established='ss -tunap state established'  # только установленные соединения
alias tcp-stats='ss -s'                       # статистика сокетов (всего/TCP/UDP/RAW)
alias port-count='ss -tunap | awk "{print \$1}" | sort | uniq -c | sort -rn'  # кол-во соединений по типу
# alias arp='ip neighbour show'                 # ARP-таблица (MAC-адреса соседей)
alias traffic='cat /proc/net/dev'             # статистика трафика по интерфейсам
# alias mtu="ip link show | grep mtu"           # MTU всех интерфейсов

# --- Systemd ------------------------------------------------------------------
# alias sc='sudo systemctl'                     # короткий вызов systemctl
alias scs='sudo systemctl status'             # статус сервиса: scs nginx
alias scr='sudo systemctl restart'            # перезапуск сервиса: scr nginx
alias scstop='sudo systemctl stop'            # остановить сервис: scstop nginx
alias scstart='sudo systemctl start'          # запустить сервис: scstart nginx
alias sce='sudo systemctl enable'             # включить автозапуск: sce nginx
alias sced='sudo systemctl enable --now'      # включить автозапуск и сразу запустить
alias scd='sudo systemctl disable'            # отключить автозапуск: scd nginx
alias scdd='sudo systemctl disable --now'     # отключить автозапуск и сразу остановить
alias scmask='sudo systemctl mask'            # полностью заблокировать сервис (нельзя запустить)
alias scunmask='sudo systemctl unmask'        # разблокировать замаскированный сервис
# alias screload='sudo systemctl daemon-reload' # перечитать все unit-файлы после изменений
alias scl='sudo systemctl list-units --type=service --state=running'   # запущенные сервисы
alias scf='systemctl --failed'                # все упавшие юниты (сервисы, таймеры и т.д.)
alias scfailed='systemctl --failed --type=service'  # только упавшие сервисы
# alias sctimers='systemctl list-timers --all'  # все таймеры (аналог cron в systemd)
alias scenabled='systemctl list-unit-files --state=enabled'   # сервисы с автозапуском
# alias scdisabled='systemctl list-unit-files --state=disabled' # сервисы без автозапуска
# alias sccat='systemctl cat'                   # показать содержимое unit-файла: sccat nginx
# alias scedit='sudo systemctl edit'            # редактировать override для сервиса: scedit nginx
# alias scdeps='systemctl list-dependencies'    # дерево зависимостей: scdeps nginx
# alias scboot='systemd-analyze blame'          # время загрузки каждого сервиса (от долгого к быстрому)
alias scboottime='systemd-analyze time'       # общее время загрузки системы
alias jlog='sudo journalctl -xe'              # последние логи с контекстом и пояснениями
alias jfu='sudo journalctl -fu'               # follow лог сервиса: jfu nginx
alias jboot='sudo journalctl -b'              # логи с момента последней загрузки
alias jprev='sudo journalctl -b -1'           # логи предыдущей загрузки (до ребута)
alias jyesterday='sudo journalctl --since yesterday'  # логи за вчера
alias jerr='sudo journalctl -p err -b'        # только ошибки с последней загрузки
alias jwarn='sudo journalctl -p warning -b'   # предупреждения и ошибки с последней загрузки
alias jdisk='sudo journalctl --disk-usage'    # сколько места занимают логи journald
alias jclean='sudo journalctl --vacuum-time=7d'  # удалить логи старше 7 дней

# --- Docker -------------------------------------------------------------------
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'  # компактный список контейнеров
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'  # все контейнеры (вкл. остановленные)
alias dlogs='docker logs -f --tail 100'       # последние 100 строк лога + follow: dlogs container
alias dstats='docker stats --no-stream'       # ресурсы контейнеров (CPU/RAM/NET) однократно
alias dprune='docker system prune -af'        # удалить всё неиспользуемое (образы, контейнеры, сети)
alias dvols='docker volume ls'                # список Docker-томов
alias dimages='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'  # список образов
alias dstop='docker stop $(docker ps -q)'     # остановить все запущенные контейнеры
alias drestart='docker restart $(docker ps -q)'  # перезапустить все контейнеры
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

# --- Права доступа (chmod/chown) ---------------------------------------------
# # Файлы — установить права на один файл:
alias ch644='chmod 644'                       # rw-r--r--  владелец читает/пишет, остальные только читают
alias ch600='chmod 600'                       # rw-------  только владелец читает/пишет (приватные файлы, ключи)
alias ch755='chmod 755'                       # rwxr-xr-x  владелец всё, остальные читают/выполняют (скрипты)
alias ch700='chmod 700'                       # rwx------  только владелец всё (приватные скрипты)
alias ch400='chmod 400'                       # r--------  только владелец читает (SSH ключи, сертификаты)
alias chx='chmod +x'                          # добавить право на выполнение: chx script.sh
#
# # Директория — установить права только на саму папку:
alias chd755='chmod 755'                      # rwxr-xr-x  стандартные права на директорию
alias chd700='chmod 700'                      # rwx------  приватная директория (только владелец)
alias chd750='chmod 750'                      # rwxr-x---  владелец всё, группа читает, остальные нет
#
# # Рекурсивно — папка со ВСЕМ содержимым (файлы + подпапки):
alias chr755='chmod -R 755'                   # rwxr-xr-x  рекурсивно на всё содержимое
alias chr700='chmod -R 700'                   # rwx------  рекурсивно приватно
alias chr644='chmod -R 644'                   # rw-r--r--  рекурсивно только чтение для остальных
#
# # Раздельно — разные права для папок и файлов внутри дерева:
# # chmod-dirs 755 /path  — установить 755 только на ВСЕ подпапки (файлы не трогать)
# chmod-dirs() { find "$2" -type d -exec chmod "$1" {} + }
# # chmod-files 644 /path — установить 644 только на ВСЕ файлы (папки не трогать)
# chmod-files() { find "$2" -type f -exec chmod "$1" {} + }
# # chmod-web /var/www    — типичные права для веб-сервера (755 папки, 644 файлы)
# chmod-web() { find "$1" -type d -exec chmod 755 {} + && find "$1" -type f -exec chmod 644 {} + }
# # chmod-private /path   — приватные права (700 папки, 600 файлы)
# chmod-private() { find "$1" -type d -exec chmod 700 {} + && find "$1" -type f -exec chmod 600 {} + }
#
# # Смена владельца:
# alias chownme='sudo chown -R $(whoami):$(whoami)'  # сделать себя владельцем: chownme /path
# alias chownwww='sudo chown -R www-data:www-data'   # передать веб-серверу: chownwww /var/www
# alias chownroot='sudo chown -R root:root'          # передать root: chownroot /etc/myapp

# --- Создание директорий и структур ------------------------------------------
alias mkdir='mkdir -pv'                       # всегда создавать вложенные + показывать
#
# # Создать директорию и перейти в неё: mkcd my-project
# # mkcd() { mkdir -p "$1" && cd "$1" }        # (уже есть выше в "Полезные функции")
#
# # Создать вложенную структуру каталогов одной командой:
# # mktree project/{src,docs,tests,config}
# alias mktree='mkdir -pv'                      # то же что mkdir -pv, для наглядности
#
# # Создать структуру веб-проекта: mkweb mysite
# mkweb() { mkdir -pv "$1"/{css,js,img,fonts} && touch "$1"/index.html }
#
# # Создать структуру Go-проекта: mkgo myapp
# mkgo() { mkdir -pv "$1"/{cmd/"$1",internal,pkg,api,configs,scripts,test} }
#
# # Создать временную директорию и перейти в неё: mktmp
# alias mktmp='cd $(mktemp -d)'

# --- Копирование, перемещение и переименование --------------------------------
# # Копировать файл с новым именем: cpn file.conf file.conf.new
# alias cpn='cp -iv'                            # копия с подтверждением (интерактивно)
#
# # Копировать директорию целиком: cpdir /src /dst
# alias cpdir='cp -riv'                         # рекурсивное копирование с подтверждением
#
# # Копировать файл с сохранением прав и времени (для бэкапов):
# alias cpp='cp -av'                            # archive mode: права, владелец, симлинки
#
# # Массовое переименование — переименовать расширение файлов:
# # rename-ext txt md       — переименовать все *.txt в *.md в текущей папке
# rename-ext() { for f in *."$1"; do mv -v "$f" "${f%.$1}.$2"; done }
#
# # Переименовать файл/папку (по сути mv, но с подтверждением):
# alias ren='mv -iv'                            # переименование с подтверждением
#
# # Переместить в директорию (создать если не существует): mvto /path file1 file2
mvto() { mkdir -p "$1" && shift && mv -iv "$@" "$1" }
#
# # Копировать в директорию (создать если не существует): cpto /path file1 file2
cpto() { mkdir -p "$1" && shift && cp -iv "$@" "$1" }
#
# # Синхронизация директорий (лучше чем cp для больших объёмов):
# alias rsync-copy='rsync -avh --progress'      # копировать с прогрессом: rsync-copy src/ dst/
# alias rsync-move='rsync -avh --progress --remove-source-files'  # переместить с прогрессом
# alias rsync-mirror='rsync -avh --delete'       # зеркалирование (удалит лишнее в dst)

# --- Поиск файлов и содержимого -----------------------------------------------
alias ff='find . -type f -name'               # найти файл по имени: ff "*.conf"
alias fd='find . -type d -name'               # найти директорию по имени: fd "logs"
alias fsize='find . -type f -size'            # найти по размеру: fsize +100M
# alias fbig='find . -type f -exec ls -lS {} + | sort -k5 -rn | head -20'  # 20 самых больших файлов
# alias fempty='find . -type f -empty'          # пустые файлы
# alias dempty='find . -type d -empty'          # пустые директории
alias fmod='find . -type f -mtime'            # найти по дате изменения: fmod -1 (за сутки)
alias fgrep='grep -rnI --color=auto'          # рекурсивный поиск текста: fgrep "TODO" .

# --- Информация о системе ----------------------------------------------------
# alias top10cpu='ps aux --sort=-%cpu | head -11'   # ТОП-10 процессов по CPU
# alias top10mem='ps aux --sort=-%mem | head -11'   # ТОП-10 процессов по RAM
# alias psg='ps aux | grep -v grep | grep -i'      # найти процесс: psg nginx
# alias duh='du -h --max-depth=1 | sort -hr'       # размер подпапок (сортировка по убыванию)
# alias duf='du -sh *'                              # размер каждого элемента в текущей папке
# alias diskfree='df -h | grep -v tmpfs | grep -v loop'  # диски без tmpfs и loop
# alias uptime='uptime -p'                          # аптайм в человекочитаемом формате
# alias loadavg='cat /proc/loadavg'                 # средняя загрузка системы
# alias meminfo='cat /proc/meminfo | head -5'       # основная информация о RAM
# alias cpuinfo='lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"'  # основная информация о CPU
# alias wholistens='sudo lsof -i -P -n | grep LISTEN'  # какие процессы слушают порты

# --- Безопасность / nftables (дополнение) ------------------------------------
alias nft-monitor='sudo nft monitor'                          # мониторинг изменений правил в реальном времени
alias nft-handles='sudo nft list ruleset -a'                  # правила с хендлами (для удаления конкретного правила)
alias nft-json='sudo nft -j list ruleset | python3 -m json.tool'  # правила в формате JSON (удобно для парсинга)
alias nft-counters='sudo nft list ruleset | grep -E "counter|chain|table"'  # счётчики пакетов по правилам
# alias fail2ban-status='sudo fail2ban-client status'           # общий статус fail2ban
# alias fail2ban-ssh='sudo fail2ban-client status sshd'         # заблокированные IP для SSH
# alias banned='sudo fail2ban-client banned'                    # все заблокированные IP во всех jail

# --- Автодополнение алиасов в zsh ---------------------------------------------
# zsh-autosuggestions (уже установлен в plugins) автоматически подсказывает
# продолжение команд на основе истории — включая все ваши алиасы.
# Просто начните вводить алиас и нажмите → (стрелку вправо) для подстановки.
#
# Для дополнительного автодополнения алиасов можно включить:
setopt COMPLETE_ALIASES               # Tab-дополнение учитывает алиасы
#
# Чтобы видеть все доступные алиасы начинающиеся с определённых букв:
# alias | grep '^nft'                   # показать все nft-* алиасы (nftables)
# alias | grep '^fail2ban'              # показать все fail2ban-* алиасы
# alias | grep '^sc'                    # показать все sc* алиасы (systemctl/systemd)
# alias | grep '^j'                     # показать все j* алиасы (journalctl)
# alias | grep '^d'                     # показать все d* алиасы (docker)
# alias | grep '^docker'                # показать все docker-* алиасы (docker сети/IP)
# alias | grep '^rsync'                 # показать все rsync-* алиасы (синхронизация)
# alias | grep '^ip'                    # показать все ip* алиасы (сеть/IP)
# alias | grep '^tcp\|^udp'             # показать все tcp*/udp* алиасы (порты)
# alias | grep '^ch'                    # показать все ch* алиасы (chmod/chown)
# alias | grep '^chr'                   # показать все chr* алиасы (рекурсивный chmod)
# alias | grep '^chown'                 # показать все chown* алиасы (смена владельца)
# alias | grep '^chmod'                 # показать все chmod-* алиасы (функции chmod)
# alias | grep '^mk'                   # показать все mk* алиасы (создание директорий)
# alias | grep '^cp'                    # показать все cp* алиасы (копирование)
# alias | grep '^mv\|^ren'             # показать все mv*/ren* алиасы (перемещение)
# alias | grep '^ff\|^fd\|^f'          # показать все f* алиасы (поиск файлов)
# alias | grep '^top10\|^psg'          # показать все top10*/psg* алиасы (процессы)
# alias | grep '^du\|^disk'            # показать все du*/disk* алиасы (диски)
# alias | grep '^mem\|^cpu\|^load'     # показать все mem*/cpu*/load* алиасы (система)
# alias | grep '^ping\|^myip\|^local'  # показать все ping*/myip*/local* алиасы (сеть)
# alias | grep '^listen\|^conn\|^est'  # показать все listen*/conn*/est* алиасы (соединения)
# alias | grep '^gate\|^route\|^dns'   # показать все gateway/routes/dns алиасы (маршруты)
# alias | grep '^ll\|^ports\|^mem\|^df' # показать все системные алиасы (активные)
#
# # Функция для поиска алиасов: aliases nft  — покажет все алиасы содержащие "nft"
aliases() { alias | grep -i "$1" }

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
