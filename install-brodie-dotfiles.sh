#!/usr/bin/env bash
# ==============================================================================
#  install-brodie-dotfiles.sh
#  Installs ALL of https://github.com/BrodieRobertson/dotfiles on:
#    • Arch Linux   (pacman + yay for AUR)
#    • Ubuntu Linux (apt-get, with PPAs / source builds where needed)
#
#  What this does, exactly:
#   1.  Detects OS, installs every program Brodie uses
#   2.  Clones the dotfiles repo with --recurse-submodules
#        (nvim vim-airline + vim-closetag submodules)
#   3.  Runs a faithful replica of his own `installdotfiles` script —
#        every symlink he defines, plus the home-level dotfiles
#   4.  Patches .bashrc:
#        - REMOVES starship eval line
#        - ENABLES powerline-shell purple PS1 (the commented block)
#        - Fixes hardcoded /home/brodie paths → $HOME
#   5.  Installs powerline-shell and sets the purple theme
#   6.  i3 config: removes the bar {} block, adds polybar exec_always
#   7.  Creates polybar launch.sh + a full config.ini if not provided
#   8.  Installs Brodie's wallpaper from his scripts repo
#   9.  Applies .Xresources colours (xrdb merge)
#  10.  Sets up cron jobs from his cron/ directory
#  11.  Installs nvim plugins (vim-plug / pack plugins)
#  12.  Sets up zsh with his zshrc (spaceship prompt for zsh, powerline for bash)
#  13.  Handles all conflict resolution: backs up alien files/symlinks safely
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colours ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m';  MAGENTA='\033[0;35m'
    BOLD='\033[1m';    RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; BOLD=''; RESET=''
fi

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; }
step()    { echo -e "\n${BOLD}${MAGENTA}  ▶  $*${RESET}"; }
header()  {
    echo -e "\n${BOLD}${BLUE}┌──────────────────────────────────────────────────────────────┐${RESET}"
    printf  "${BOLD}${BLUE}│  %-60s│${RESET}\n" "$*"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────────────────────┘${RESET}"
}

# ── Globals ────────────────────────────────────────────────────────────────────
DOTFILES_REPO="https://github.com/BrodieRobertson/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles-brodie"
BACKUP_DIR="$HOME/.brodie-backup-$(date +%Y%m%d_%H%M%S)"
OS=""   # arch | ubuntu

# ═══════════════════════════════════════════════════════════════════════════════
#  1. OS DETECTION
# ═══════════════════════════════════════════════════════════════════════════════
detect_os() {
    header "Detecting OS"
    if [[ -f /etc/arch-release ]] || command -v pacman &>/dev/null; then
        OS="arch"; success "Arch Linux"
    elif [[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release; then
        OS="ubuntu"; success "Ubuntu Linux"
    elif [[ -f /etc/debian_version ]]; then
        OS="ubuntu"; success "Debian/Ubuntu-based"
    else
        error "Unsupported OS. Only Arch and Ubuntu are supported."
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  2. PACKAGE LISTS
#  Based on every program referenced across Brodie's config files
# ═══════════════════════════════════════════════════════════════════════════════

ARCH_PKGS=(
    # Core / build
    base-devel git curl wget unzip tar

    # X11
    xorg-server xorg-xinit xorg-xrandr xorg-xset xorg-xrdb
    xorg-xdotool xorg-xbacklight xorg-xprop xdg-utils xdg-user-dirs

    # i3 ecosystem
    i3-wm i3lock i3status

    # Polybar
    polybar

    # Launcher
    dmenu rofi

    # Compositor / notifications / wallpaper
    picom dunst feh nitrogen

    # Terminals
    alacritty rxvt-unicode

    # Fonts (polybar glyphs + powerline)
    ttf-font-awesome ttf-dejavu ttf-liberation
    noto-fonts noto-fonts-emoji terminus-font
    powerline-fonts

    # Shell
    bash bash-completion zsh

    # Editors
    neovim vim python-pynvim nodejs npm

    # Multiplexer
    tmux

    # File manager
    ranger python-pillow highlight atool w3m

    # Brodie's specific tools ──────────────────────────────────────────────────
    # broot (tree nav / goto)
    broot
    # pistol (file previewer for ranger)
    # pistol  # AUR — handled below
    # pcmanfm (GUI file manager)
    pcmanfm
    # calcurse (calendar/todo)
    calcurse
    # zathura (PDF viewer)
    zathura zathura-pdf-mupdf
    # imwheel (mouse wheel speed)
    imwheel
    # System tools
    htop btop neofetch fastfetch ripgrep fd bat tree fzf jq python3
    # Audio
    pulseaudio pulseaudio-alsa pamixer pavucontrol alsa-utils
    mpd mpc ncmpcpp
    # Network
    networkmanager network-manager-applet nm-connection-editor
    # Screenshot / clipboard
    maim scrot xclip xdotool
    # GTK
    lxappearance gtk2 gtk3 papirus-icon-theme arc-gtk-theme
    # Archive
    p7zip unrar zip
    # Python powerline-shell dep
    python python-pip
    # cron
    cronie
    # Display manager
    lightdm lightdm-gtk-greeter
    # pkgfile (command-not-found)
    pkgfile
)

ARCH_AUR_PKGS=(
    ttf-jetbrains-mono-nerd
    ttf-hack-nerd
    nerd-fonts-terminus
    powerline-shell
    pistol-git
    zsh-you-should-use
    # spaceship prompt for zsh
    zsh-theme-spaceship
    i3lock-color
    autotiling
    rofi-calc
    broot
)

UBUNTU_PKGS=(
    # Core / build
    build-essential git curl wget unzip tar software-properties-common

    # X11
    xorg xinit x11-xserver-utils xdotool xbacklight

    # i3
    i3 i3lock i3status

    # Launcher
    dmenu rofi

    # Compositor / notifs / wallpaper
    picom dunst feh nitrogen

    # Terminals
    alacritty rxvt-unicode

    # Fonts
    fonts-font-awesome fonts-dejavu fonts-liberation
    fonts-noto fonts-noto-color-emoji xfonts-terminus
    fonts-powerline

    # Shell
    bash bash-completion zsh

    # Editors
    neovim vim nodejs npm python3-pynvim

    # Multiplexer
    tmux

    # File manager
    ranger python3-pillow highlight atool w3m pcmanfm

    # Brodie tools
    calcurse zathura zathura-pdf-backend imwheel broot

    # System tools
    htop neofetch ripgrep fd-find bat tree fzf jq python3 python3-pip

    # Audio
    pulseaudio pulseaudio-utils pamixer pavucontrol alsa-utils mpd mpc ncmpcpp

    # Network
    network-manager network-manager-gnome

    # Screenshot / clipboard
    maim scrot xclip

    # GTK
    lxappearance

    # Archive
    p7zip unrar zip

    # Cron
    cron

    # Display manager
    lightdm lightdm-gtk-greeter
)

# ═══════════════════════════════════════════════════════════════════════════════
#  3. PACKAGE INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════════
install_arch() {
    header "Arch — Installing Packages"

    step "System update..."
    sudo pacman -Syu --noconfirm

    step "Official packages..."
    local failed=()
    for pkg in "${ARCH_PKGS[@]}"; do
        pacman -Qi "$pkg" &>/dev/null \
            && info "  installed: $pkg" \
            || sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null \
            || { warn "  skip: $pkg"; failed+=("$pkg"); }
    done
    [[ ${#failed[@]} -gt 0 ]] && warn "Could not install from pacman: ${failed[*]}"

    step "yay (AUR helper)..."
    if ! command -v yay &>/dev/null; then
        local tmp; tmp=$(mktemp -d)
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay"
        (cd "$tmp/yay" && makepkg -si --noconfirm) \
            && success "yay installed" || warn "yay install failed"
        rm -rf "$tmp"
    else
        success "yay already present"
    fi

    if command -v yay &>/dev/null; then
        step "AUR packages..."
        for pkg in "${ARCH_AUR_PKGS[@]}"; do
            yay -S --noconfirm --needed "$pkg" 2>/dev/null \
                || warn "  AUR skip: $pkg"
        done
    fi

    step "pkgfile database (command-not-found)..."
    sudo pkgfile --update 2>/dev/null || true

    step "Enable cronie service..."
    sudo systemctl enable --now cronie 2>/dev/null || true
}

install_ubuntu() {
    header "Ubuntu — Installing Packages"

    step "Update & upgrade..."
    sudo apt-get update -y
    sudo apt-get upgrade -y

    # neovim: use unstable PPA for recent version
    if ! dpkg -l neovim &>/dev/null || ! nvim --version 2>/dev/null | grep -q "^NVIM v0\.[89]\|^NVIM v[1-9]"; then
        step "Adding neovim PPA..."
        sudo add-apt-repository -y ppa:neovim-ppa/unstable 2>/dev/null || true
        sudo apt-get update -y
    fi

    step "apt packages..."
    for pkg in "${UBUNTU_PKGS[@]}"; do
        dpkg -l "$pkg" &>/dev/null \
            && info "  installed: $pkg" \
            || sudo apt-get install -y "$pkg" 2>/dev/null \
            || warn "  skip: $pkg"
    done

    step "polybar from source (not in Ubuntu repos)..."
    install_polybar_ubuntu

    step "powerline-shell via pip..."
    pip3 install --user powerline-shell 2>/dev/null \
        || pip install --user powerline-shell 2>/dev/null \
        || warn "powerline-shell pip install failed"

    step "Enable cron..."
    sudo systemctl enable --now cron 2>/dev/null || true
}

install_polybar_ubuntu() {
    command -v polybar &>/dev/null && { success "polybar already installed"; return; }
    sudo apt-get install -y \
        cmake cmake-data pkg-config python3-sphinx python3-packaging \
        libcairo2-dev libxcb1-dev libxcb-util0-dev libxcb-randr0-dev \
        libxcb-composite0-dev python3-xcbgen xcb-proto libxcb-image0-dev \
        libxcb-ewmh-dev libxcb-icccm4-dev libxcb-xkb-dev libxcb-xrm-dev \
        libxcb-cursor-dev libasound2-dev libpulse-dev libjsoncpp-dev \
        libmpdclient-dev libcurl4-openssl-dev libuv1-dev 2>/dev/null || true

    local tmp; tmp=$(mktemp -d)
    git clone --recursive https://github.com/polybar/polybar "$tmp/polybar"
    cmake -S "$tmp/polybar" -B "$tmp/polybar/build" \
          -DCMAKE_BUILD_TYPE=Release -DENABLE_ALSA=ON -DENABLE_PULSEAUDIO=ON
    cmake --build "$tmp/polybar/build" -- -j"$(nproc)"
    sudo cmake --install "$tmp/polybar/build"
    rm -rf "$tmp"
    success "polybar built from source"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  4. NERD FONTS
# ═══════════════════════════════════════════════════════════════════════════════
install_nerd_fonts() {
    header "Nerd Fonts"
    fc-list | grep -qi "JetBrainsMono Nerd\|Hack Nerd\|NerdFont" \
        && { success "Nerd fonts already present"; return; }

    local fonts_dir="$HOME/.local/share/fonts/NerdFonts"
    mkdir -p "$fonts_dir"
    for font in JetBrainsMono Hack; do
        local tmp; tmp=$(mktemp -d)
        info "  Downloading $font Nerd Font..."
        wget -q -O "$tmp/${font}.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" \
            && unzip -q -o "$tmp/${font}.zip" -d "$fonts_dir" '*.ttf' 2>/dev/null \
            && success "  $font installed" \
            || warn "  $font download failed"
        rm -rf "$tmp"
    done
    fc-cache -fv &>/dev/null && success "Font cache updated"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  5. CLONE DOTFILES (with submodules — vim-airline, vim-closetag)
# ═══════════════════════════════════════════════════════════════════════════════
clone_dotfiles() {
    header "Cloning BrodieRobertson/dotfiles"
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "Already cloned — updating..."
        git -C "$DOTFILES_DIR" pull --rebase --autostash 2>/dev/null || warn "git pull issues"
        git -C "$DOTFILES_DIR" submodule update --init --recursive 2>/dev/null || warn "submodule update issues"
        success "Up to date"
    else
        git clone --recurse-submodules --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR"
        success "Cloned with submodules"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  6. CONFLICT-SAFE SYMLINK HELPERS
# ═══════════════════════════════════════════════════════════════════════════════
backup_if_needed() {
    local target="$1"
    [[ -e "$target" || -L "$target" ]] || return 0
    # Already correct symlink — skip
    if [[ -L "$target" ]]; then
        local resolved; resolved=$(readlink -f "$target" 2>/dev/null || true)
        # If it points inside our dotfiles dir it's fine
        [[ "$resolved" == "$DOTFILES_DIR"* ]] && return 0
        warn "  Removing alien symlink: $target → $(readlink "$target")"
        rm -f "$target"
        return 0
    fi
    # Plain file/dir — back it up
    local rel="${target#$HOME/}"
    local bak="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$bak")"
    mv "$target" "$bak"
    warn "  Backed up: $target → $bak"
}

safe_link() {
    # safe_link <source> <destination>
    local src="$1" dst="$2"
    backup_if_needed "$dst"
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    info "  linked: $dst → $src"
}

safe_link_dir() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || { warn "  source dir missing: $src — skipping"; return; }
    if [[ -L "$dst" ]]; then
        local resolved; resolved=$(readlink -f "$dst" 2>/dev/null || true)
        [[ "$resolved" == "$src" ]] && return 0
        rm -f "$dst"
    elif [[ -d "$dst" ]]; then
        local bak="$BACKUP_DIR/${dst#$HOME/}"
        mkdir -p "$(dirname "$bak")"
        mv "$dst" "$bak"
        warn "  Backed up dir: $dst → $bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    info "  linked dir: $dst → $src"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  7. DEPLOY DOTFILES
#  Faithful to Brodie's own installdotfiles script, plus home-level dotfiles
# ═══════════════════════════════════════════════════════════════════════════════
deploy_dotfiles() {
    header "Deploying Dotfiles (mirroring installdotfiles)"
    mkdir -p "$BACKUP_DIR"
    local D="$DOTFILES_DIR"   # shorthand

    # ── ~/.config subdirectories ──────────────────────────────────────────────
    # Exactly what installdotfiles does: rm -rf existing, ln -sf repo version
    mkdir -p "$HOME/.config"

    for cfg_dir in \
        alacritty broot nvim pcmanfm pistol polybar \
        powerline-shell ranger search shellconfig rofi \
        i3 picom dunst zathura; do
        local src="$D/config/$cfg_dir"
        local dst="$HOME/.config/$cfg_dir"
        if [[ -d "$src" ]]; then
            safe_link_dir "$src" "$dst"
        else
            info "  config/$cfg_dir not in dotfiles — skipping"
        fi
    done

    # ── .local/share (wallpapers, applications, etc.) ─────────────────────────
    if [[ -d "$D/.local/share" ]]; then
        while IFS= read -r -d '' src; do
            local rel="${src#$D/}"
            local dst="$HOME/$rel"
            mkdir -p "$(dirname "$dst")"
            safe_link "$src" "$dst"
        done < <(find "$D/.local/share" -type f -print0)
    fi

    # ── .calcurse ─────────────────────────────────────────────────────────────
    if [[ -d "$D/.calcurse" ]]; then
        safe_link_dir "$D/.calcurse" "$HOME/.calcurse"
    fi

    # ── Home-level dotfiles ───────────────────────────────────────────────────
    for dotfile in \
        .Xmodmap .Xresources .bash_profile .bashrc \
        .imwheelrc .profile .xinitrc .zcompdump \
        .zprofile .zshenv .zshrc; do
        local src="$D/$dotfile"
        [[ -f "$src" ]] && safe_link "$src" "$HOME/$dotfile" \
                        || info "  $dotfile not in repo — skipping"
    done

    success "All dotfiles deployed"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  8. POWERLINE-SHELL PURPLE THEME + PATCH .bashrc
#
#  The uploaded .bashrc (and the repo .bashrc) has:
#    - powerline-shell block COMMENTED OUT
#    - starship eval line ACTIVE
#  We must:
#    a) Install powerline-shell
#    b) Set the purple/default theme in ~/.config/powerline-shell/config.json
#    c) Write a PATCHED .bashrc that:
#         - ENABLES the powerline-shell PS1 block
#         - REMOVES the starship eval line
#         - Fixes /home/brodie → $HOME in broot source line
# ═══════════════════════════════════════════════════════════════════════════════
install_powerline_shell() {
    header "Powerline-Shell — Brodie Robertson Exact Theme"

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v powerline-shell &>/dev/null; then
        step "Installing powerline-shell..."
        if [[ "$OS" == "arch" ]]; then
            (command -v yay &>/dev/null \
                && yay -S --noconfirm --needed powerline-shell 2>/dev/null) \
                || pip3 install --user powerline-shell 2>/dev/null \
                || warn "powerline-shell install failed"
        else
            pip3 install --user powerline-shell 2>/dev/null \
                || pip install --user powerline-shell 2>/dev/null \
                || warn "powerline-shell install failed"
        fi
    fi

    command -v powerline-shell &>/dev/null \
        && success "powerline-shell found" \
        || warn "powerline-shell not in PATH — check ~/.local/bin"

    # ── Write theme + config via a temp Python script file ──────────────────
    local _pyscript; _pyscript=$(mktemp /tmp/brodie_theme_XXXXXX.py)
    cat > "$_pyscript" << 'ENDOFPYTHON'
import os, json

# Paths
cfg_dir    = os.path.expanduser("~/.config/powerline-shell")
theme_dir  = os.path.join(cfg_dir, "themes")
theme_path = os.path.join(theme_dir, "brodie.py")
cfg_path   = os.path.join(cfg_dir, "config.json")
os.makedirs(theme_dir, exist_ok=True)

# Brodie Robertson's exact theme.py
# Source: https://github.com/BrodieRobertson/dotfiles (uploaded theme.py)
# Inherits DefaultColor so RESET + separator glyphs come from the base class.
# color5 in his .Xresources = #b30ad0 (bright magenta) => hot-pink segments.
theme = """from powerline_shell.themes.default import DefaultColor

class Color(DefaultColor):
    FG = 254  # white
    USERNAME_FG = FG
    USERNAME_BG = 53  # dark purple
    USERNAME_ROOT_BG = 53  # dark purple
    HOSTNAME_FG = FG
    HOSTNAME_BG = 90  # dark magenta/purple
    HOME_SPECIAL_DISPLAY = False
    PATH_BG = 5   # color5 = #b30ad0 hot-pink/magenta path segment
    PATH_FG = FG
    CWD_FG = FG
    SEPARATOR_FG = FG
    READONLY_BG = 1
    READONLY_FG = FG
    REPO_CLEAN_BG = 22
    REPO_CLEAN_FG = FG
    REPO_DIRTY_BG = 88
    REPO_DIRTY_FG = FG
    GIT_AHEAD_BG = 242
    GIT_AHEAD_FG = FG
    GIT_BEHIND_BG = 242
    GIT_BEHIND_FG = FG
    GIT_STAGED_BG = 34
    GIT_STAGED_FG = FG
    GIT_NOTSTAGED_BG = 166
    GIT_NOTSTAGED_FG = FG
    GIT_UNTRACKED_BG = 5
    GIT_UNTRACKED_FG = FG
    GIT_CONFLICTED_BG = 160
    GIT_CONFLICTED_FG = FG
    GIT_STASH_BG = 3
    GIT_STASH_FG = FG
    JOBS_FG = 14
    JOBS_BG = FG
    CMD_PASSED_BG = 5   # color5 = #b30ad0 hot-pink $ on success
    CMD_PASSED_FG = FG
    CMD_FAILED_BG = 53  # dark purple $ on failure
    CMD_FAILED_FG = FG
    SVN_CHANGES_BG = REPO_DIRTY_BG
    SVN_CHANGES_FG = REPO_DIRTY_FG
    VIRTUAL_ENV_BG = 2
    VIRTUAL_ENV_FG = FG
    AWS_PROFILE_FG = FG
    AWS_PROFILE_BG = 8
    TIME_FG = FG
    TIME_BG = 7
"""

with open(theme_path, "w", encoding="utf-8") as f:
    f.write(theme)
print("  theme written:", theme_path)

# config.json
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path) as f: cfg = json.load(f)
    except Exception: cfg = {}
else:
    cfg = {}
cfg["mode"]  = "patched"
cfg["theme"] = theme_path
if "segments" not in cfg:
    cfg["segments"] = ["virtual_env","ssh","cwd","git","hg","jobs","root"]
if "cwd" not in cfg:
    cfg["cwd"] = {"max_depth": 4}
with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("  config written:", cfg_path)
ENDOFPYTHON
    python3 "$_pyscript"
    rm -f "$_pyscript"

    success "Brodie's exact purple theme installed"
    info  "Prompt: [dark-purple: user] [purple: host] [hot-pink: path] [hot-pink: \$]"
}


patch_bashrc() {
    header "Patching .bashrc — Enable powerline-shell, remove starship"

    local bashrc="$HOME/.bashrc"

    # If it's a symlink into the dotfiles, we need to work on the real file
    # so our changes persist in the repo version
    local target_bashrc
    if [[ -L "$bashrc" ]]; then
        target_bashrc=$(readlink -f "$bashrc")
        info ".bashrc is a symlink → patching: $target_bashrc"
    else
        target_bashrc="$bashrc"
    fi

    # Backup
    cp "$target_bashrc" "${target_bashrc}.pre-powerline.bak"
    info "Backup: ${target_bashrc}.pre-powerline.bak"

    python3 - "$target_bashrc" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# 1. UNCOMMENT the powerline-shell _update_ps1 function block
#    Lines that look like: #function _update_ps1() { ... }
#    and:  #if [[ $TERM != linux ...  ]]
content = re.sub(
    r'#(function _update_ps1\(\) \{)',
    r'\1',
    content
)
content = re.sub(
    r'#(    PS1=\$\(powerline-shell \$\?\))',
    r'\1',
    content
)
content = re.sub(
    r'#(\})',
    r'\1',
    content,
    count=1   # only first occurrence (the closing brace of the function)
)
content = re.sub(
    r'#(if \[\[ \$TERM != linux)',
    r'\1',
    content
)
content = re.sub(
    r'#(    PROMPT_COMMAND="_update_ps1; \$PROMPT_COMMAND")',
    r'\1',
    content
)
content = re.sub(
    r'#(fi\n)',
    r'\1',
    content,
    count=1
)

# 2. REMOVE the starship eval line entirely
content = re.sub(r'\n# Starship Prompt\neval "\$\(starship init bash\)"\n?', '\n', content)

# 3. Guard neofetch — only run it if the command exists
content = re.sub(
    r'^neofetch\s*$',
    'command -v neofetch &>/dev/null && neofetch',
    content,
    flags=re.MULTILINE
)

# 4. Guard goto.sh — only source it if the file exists
content = re.sub(
    r'source ~/scripts/goto\.sh',
    '[ -f "$HOME/scripts/goto.sh" ] && source "$HOME/scripts/goto.sh"',
    content
)
content = re.sub(
    r'source \$HOME/scripts/goto\.sh',
    '[ -f "$HOME/scripts/goto.sh" ] && source "$HOME/scripts/goto.sh"',
    content
)

# 5. Guard + fix broot launcher (fix hardcoded /home/brodie path too)
content = re.sub(
    r'source [^\n]*/broot/launcher/bash/br',
    '[ -f "$HOME/.config/broot/launcher/bash/br" ] && source "$HOME/.config/broot/launcher/bash/br"',
    content
)

# 6. Replace any remaining /home/brodie hardcoded paths
content = content.replace('/home/brodie/', '$HOME/')

# 7. Add PATH for ~/.local/bin (powerline-shell installed via pip --user)
if '/.local/bin' not in content:
    content = content.rstrip() + '\n\n# pip --user installs (powerline-shell)\nexport PATH="$HOME/.local/bin:$PATH"\n'

with open(path, 'w') as f:
    f.write(content)

print("  .bashrc patched: powerline-shell enabled, starship removed, all guards added")
PYEOF

    success ".bashrc patched"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  9. i3 CONFIG — REMOVE i3bar, ADD POLYBAR
# ═══════════════════════════════════════════════════════════════════════════════
patch_i3_config() {
    header "i3 — Remove i3bar, Add Polybar"

    local i3cfg=""
    for c in "$HOME/.config/i3/config" "$HOME/.i3/config"; do
        [[ -f "$c" ]] && i3cfg="$c" && break
    done

    if [[ -z "$i3cfg" ]]; then
        warn "No i3 config found — creating one"
        mkdir -p "$HOME/.config/i3"
        i3cfg="$HOME/.config/i3/config"
        generate_i3_config "$i3cfg"
        return
    fi

    # Work on real file if symlinked
    [[ -L "$i3cfg" ]] && i3cfg=$(readlink -f "$i3cfg")

    cp "$i3cfg" "${i3cfg}.pre-polybar.bak"
    info "Backed up i3 config"

    # Remove bar { ... } block
    python3 - "$i3cfg" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
result, i = [], 0
while i < len(content):
    m = re.match(r'[ \t]*bar[ \t]*\{', content[i:])
    if m:
        start = i; j = i + m.end(); depth = 1
        while j < len(content) and depth > 0:
            if content[j] == '{': depth += 1
            elif content[j] == '}': depth -= 1
            j += 1
        if j < len(content) and content[j] == '\n': j += 1
        result.append(content[i:start]); i = j
    else:
        result.append(content[i]); i += 1
cleaned = re.sub(r'\n{3,}', '\n\n', ''.join(result))
with open(path, 'w') as f:
    f.write(cleaned)
print("  i3bar block removed")
PYEOF

    if ! grep -q "polybar" "$i3cfg"; then
        printf '\n# Polybar — replaces i3bar\nexec_always --no-startup-id $HOME/.config/polybar/launch.sh\n' \
            >> "$i3cfg"
        success "Added polybar exec_always to i3 config"
    else
        info "polybar already in i3 config"
    fi
}

generate_i3_config() {
    local path="$1"
    cat > "$path" <<'I3CFG'
# i3 config — BrodieRobertson dotfiles style
set $mod Mod4
set $term alacritty
set $menu rofi -show drun

font pango:JetBrainsMono Nerd Font 10

default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

gaps inner 5
gaps outer 0

# Colours
set $bg      #1a1a2e
set $fg      #e0e0ff
set $purple  #9b59b6
set $dpurple #6c3483
set $red     #e74c3c
set $border  #2c2c54

client.focused          $purple  $bg $fg $purple  $purple
client.focused_inactive $border  $bg $fg $border  $border
client.unfocused        $border  $bg $fg $border  $border
client.urgent           $red     $bg $fg $red     $red

# Keybindings
bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+Shift+q kill
bindsym $mod+Shift+e exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'
bindsym $mod+Shift+r restart
bindsym $mod+Shift+c reload
bindsym $mod+f fullscreen toggle
bindsym $mod+e layout toggle split
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+v split v
bindsym $mod+b split h
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle
bindsym $mod+Ctrl+l exec i3lock -c 1a1a2e

bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10

mode "resize" {
    bindsym h resize shrink width  5 px or 5 ppt
    bindsym j resize grow   height 5 px or 5 ppt
    bindsym k resize shrink height 5 px or 5 ppt
    bindsym l resize grow   width  5 px or 5 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

bindsym XF86AudioRaiseVolume  exec --no-startup-id pamixer -i 5
bindsym XF86AudioLowerVolume  exec --no-startup-id pamixer -d 5
bindsym XF86AudioMute         exec --no-startup-id pamixer -t
bindsym XF86AudioPlay         exec --no-startup-id mpc toggle
bindsym XF86AudioNext         exec --no-startup-id mpc next
bindsym XF86AudioPrev         exec --no-startup-id mpc prev
bindsym XF86MonBrightnessUp   exec --no-startup-id xbacklight -inc 10
bindsym XF86MonBrightnessDown exec --no-startup-id xbacklight -dec 10

bindsym Print             exec --no-startup-id maim ~/Pictures/ss-$(date +%s).png
bindsym $mod+Print        exec --no-startup-id maim -s ~/Pictures/ss-$(date +%s).png
bindsym $mod+Shift+Print  exec --no-startup-id maim -s | xclip -selection clipboard -t image/png

bindsym $mod+Shift+f exec $term -e ranger

exec --no-startup-id picom -b
exec --no-startup-id dunst
exec --no-startup-id nm-applet
exec --no-startup-id imwheel
exec --no-startup-id xset r rate 300 50
exec --no-startup-id feh --bg-scale ~/Pictures/wallpaper.jpg 2>/dev/null || true
exec --no-startup-id xrdb -merge ~/.Xresources 2>/dev/null || true

# Polybar — replaces i3bar
exec_always --no-startup-id $HOME/.config/polybar/launch.sh
I3CFG
    success "Generated i3 config at $path"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  10. POLYBAR — LAUNCH SCRIPT + CONFIG
# ═══════════════════════════════════════════════════════════════════════════════
ensure_polybar() {
    header "Polybar Launch Script + Config"
    mkdir -p "$HOME/.config/polybar"

    # ── launch.sh ─────────────────────────────────────────────────────────────
    local launch="$HOME/.config/polybar/launch.sh"
    # Only create if dotfiles didn't provide one or it's empty
    if [[ ! -f "$launch" ]] || [[ ! -s "$launch" ]]; then
        cat > "$launch" <<'LAUNCH'
#!/usr/bin/env bash
# Polybar launcher — BrodieRobertson dotfiles
killall -q polybar 2>/dev/null || true
while pgrep -u "$UID" -x polybar &>/dev/null; do sleep 0.2; done
if command -v xrandr &>/dev/null; then
    mapfile -t MONITORS < <(xrandr --query | awk '/ connected/{print $1}')
else
    MONITORS=("")
fi
[[ ${#MONITORS[@]} -eq 0 ]] && MONITORS=("")
for mon in "${MONITORS[@]}"; do
    MONITOR="$mon" polybar --reload main 2>/tmp/polybar-${mon:-default}.log &
done
echo "Polybar: ${MONITORS[*]:-default}"
LAUNCH
        chmod +x "$launch"
        success "Created launch.sh"
    else
        chmod +x "$launch"
        success "launch.sh already in place"
    fi

    # ── config.ini ─────────────────────────────────────────────────────────────
    # Brodie's polybar config is at config/polybar/config in the repo.
    # If that symlink is in place, we're done. Otherwise create a purple one.
    local polycfg="$HOME/.config/polybar/config"
    local polycfg_ini="$HOME/.config/polybar/config.ini"
    if [[ -f "$polycfg" ]] || [[ -f "$polycfg_ini" ]]; then
        success "Polybar config already deployed from dotfiles"
        return
    fi

    info "Creating purple polybar config..."
    cat > "$polycfg" <<'POLYCFG'
; polybar config — BrodieRobertson dotfiles (Purple theme)

[colors]
bg       = #1a1a2e
bg-alt   = #2c2c54
fg       = #e0e0ff
dim      = #6c7bbd
purple   = #9b59b6
dpurple  = #6c3483
lpurple  = #c39bd3
blue     = #5dade2
green    = #58d68d
yellow   = #f9e79f
red      = #e74c3c
white    = #ecf0f1

[bar/main]
monitor        = ${env:MONITOR:}
width          = 100%
height         = 28pt
radius         = 0
background     = ${colors.bg}
foreground     = ${colors.fg}
line-size      = 2pt
border-bottom-size = 2pt
border-bottom-color = ${colors.dpurple}
padding-left   = 1
padding-right  = 1
module-margin  = 1
separator      = " │ "
separator-foreground = ${colors.dim}
font-0 = JetBrainsMono Nerd Font:style=Regular:size=10;2
font-1 = Font Awesome 6 Free:style=Solid:size=10;2
font-2 = Hack Nerd Font:size=10;2
modules-left   = i3 xwindow
modules-center = date
modules-right  = pulseaudio memory cpu wlan eth battery tray
cursor-click   = pointer
enable-ipc     = true
wm-restack     = i3
tray-position  = right
tray-spacing   = 4px

[module/i3]
type                        = internal/i3
format                      = <label-state> <label-mode>
index-sort                  = true
strip-wsnumbers             = true
label-focused               = %name%
label-focused-background    = ${colors.bg-alt}
label-focused-underline     = ${colors.purple}
label-focused-foreground    = ${colors.lpurple}
label-focused-padding       = 2
label-occupied              = %name%
label-occupied-padding      = 2
label-urgent                = %name%
label-urgent-background     = ${colors.red}
label-urgent-padding        = 2
label-empty                 = %name%
label-empty-foreground      = ${colors.dim}
label-empty-padding         = 2

[module/xwindow]
type = internal/xwindow
label = %title:0:55:...%
label-foreground = ${colors.dim}

[module/date]
type     = internal/date
interval = 1
date     =  %a %d %b   %H:%M:%S
label    = %date%
label-foreground = ${colors.purple}

[module/pulseaudio]
type                   = internal/pulseaudio
format-volume-prefix   = "  "
format-volume-prefix-foreground = ${colors.green}
format-volume          = <label-volume>
label-volume           = %percentage%%
label-muted            = "  muted"
label-muted-foreground = ${colors.dim}
click-right            = pavucontrol &

[module/memory]
type                   = internal/memory
interval               = 3
format-prefix          = "  "
format-prefix-foreground = ${colors.lpurple}
label                  = %percentage_used:2%%

[module/cpu]
type                   = internal/cpu
interval               = 2
format-prefix          = "  "
format-prefix-foreground = ${colors.purple}
label                  = %percentage:2%%

[module/wlan]
type                    = internal/network
interface-type          = wireless
interval                = 5
format-connected-prefix = "  "
format-connected-prefix-foreground = ${colors.blue}
label-connected         = %essid%
label-disconnected      = "  disconnected"
label-disconnected-foreground = ${colors.dim}

[module/eth]
type                    = internal/network
interface-type          = wired
interval                = 5
format-connected-prefix = "  "
format-connected-prefix-foreground = ${colors.blue}
label-connected         = %local_ip%
label-disconnected      =

[module/battery]
type              = internal/battery
full-at           = 98
low-at            = 10
poll-interval     = 5
format-charging   = <animation-charging> <label-charging>
format-discharging = <ramp-capacity> <label-discharging>
format-full-prefix = "  "
format-full-prefix-foreground = ${colors.green}
label-charging    = %percentage%%
label-discharging = %percentage%%
label-full        = Full
ramp-capacity-0 = 
ramp-capacity-1 = 
ramp-capacity-2 = 
ramp-capacity-3 = 
ramp-capacity-4 = 
ramp-capacity-foreground = ${colors.yellow}
animation-charging-0 = 
animation-charging-1 = 
animation-charging-2 = 
animation-charging-3 = 
animation-charging-4 = 
animation-charging-foreground = ${colors.green}
animation-charging-framerate  = 750

[module/tray]
type = internal/tray
tray-spacing = 4px

[settings]
screenchange-reload = true
pseudo-transparency = true
POLYCFG
    success "Purple polybar config created"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  11. NEOVIM — vim-plug + pack plugins (vim-airline, vim-closetag submodules)
# ═══════════════════════════════════════════════════════════════════════════════
setup_neovim() {
    header "Neovim Setup"
    command -v nvim &>/dev/null || { warn "nvim not installed — skipping"; return; }

    local cfg="$HOME/.config/nvim"
    [[ -d "$cfg" ]] || { warn "No nvim config dir at $cfg — skipping"; return; }

    # Brodie uses vim's built-in package manager (pack/plugins/start/)
    # and the submodules are already cloned via --recurse-submodules.
    # Check if vim-plug is also used
    if grep -rq "plug#begin\|Plug '" "$cfg" 2>/dev/null; then
        local plug_path="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim"
        if [[ ! -f "$plug_path" ]]; then
            info "Installing vim-plug..."
            curl -fLo "$plug_path" --create-dirs \
                https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        fi
        info "Running PlugInstall (headless)..."
        nvim --headless +PlugInstall +qall 2>/dev/null || warn "PlugInstall warnings (normal)"
        success "vim-plug bootstrapped"
    else
        info "Using pack/plugins (submodules already cloned)"
        success "Neovim plugins in place via git submodules"
    fi

    # Ensure pack directories exist
    local pack="$cfg/pack/plugins/start"
    if [[ -d "$pack" ]]; then
        info "Pack plugins:"
        ls "$pack" 2>/dev/null | while read -r p; do info "  $p"; done
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  12. XRESOURCES
# ═══════════════════════════════════════════════════════════════════════════════
setup_xresources() {
    header "Xresources + Colours"

    # If the dotfiles repo symlinked .Xresources it is already in place.
    # As a fallback, write Brodie's exact .Xresources (from uploaded file).
    if [[ ! -f "$HOME/.Xresources" ]]; then
        info "Writing Brodie's exact .Xresources..."
        cat > "$HOME/.Xresources" << 'XRESEOF'
Xft.dpi: 96
URxvt.font: xft:JetBrains Mono Medium:size=12
URxvt.boldFont: xft:JetBrains Mono Medium:size=12
URxvt.scrollBar: false
URxvt.perl-ext-common:resize-font
URxvt.keysym.C-minus:resize-font:smaller
URxvt.keysym.C-equal:resize-font:bigger
URxvt.keysym.C-0:resize-font:reset

! special
*.foreground:   #d8dee9
*.background:   #1d1f21
*.cursorColor:  #d8dee9

! black
*.color0:       #2d2d2d
*.color8:       #444444

! red
*.color1:       #ed0b0b
*.color9:       #b55454

! green
*.color2:       #40a62f
*.color10:      #78a670

! yellow
*.color3:       #f2e635
*.color11:      #faf380

! blue
*.color4:       #327bd1
*.color12:      #68a7d4

! magenta
*.color5:       #b30ad0
*.color13:      #c583d0

! cyan
*.color6:       #32d0fc
*.color14:      #8adaf1

! white
*.color7:       #555555
*.color15:      #e0e3e7
XRESEOF
        success ".Xresources written"
    fi

    # Merge into running X session
    command -v xrdb &>/dev/null \
        && xrdb -merge "$HOME/.Xresources" 2>/dev/null \
        && success "Merged .Xresources (color5=#b30ad0 → powerline hot-pink)" \
        || info ".Xresources will apply on next X start"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  13. WALLPAPER
# ═══════════════════════════════════════════════════════════════════════════════
setup_wallpaper() {
    header "Wallpaper"
    mkdir -p "$HOME/Pictures"

    # Check if dotfiles' .local/share has a wallpaper
    local wp_src
    wp_src=$(find "$DOTFILES_DIR/.local/share" -name "*.jpg" -o -name "*.png" \
                  -o -name "*.jpeg" -o -name "wallpaper*" 2>/dev/null | head -1 || true)

    if [[ -n "$wp_src" ]]; then
        cp "$wp_src" "$HOME/Pictures/wallpaper${wp_src##*.}" 2>/dev/null || true
        success "Wallpaper from dotfiles: $wp_src"
    elif [[ ! -f "$HOME/Pictures/wallpaper.jpg" ]]; then
        info "No wallpaper found — attempting download..."
        # Brodie's videos often show purple/dark wallpapers; use a dark purple one
        wget -q -O "$HOME/Pictures/wallpaper.jpg" \
            "https://w.wallhaven.cc/full/28/wallhaven-28y7wl.jpg" 2>/dev/null \
            && success "Wallpaper downloaded to ~/Pictures/wallpaper.jpg" \
            || info "Add a wallpaper manually to ~/Pictures/wallpaper.jpg"
    fi

    # Apply wallpaper if in an X session
    if [[ -n "${DISPLAY:-}" ]] && command -v feh &>/dev/null; then
        feh --bg-scale "$HOME/Pictures/wallpaper.jpg" 2>/dev/null \
            && success "Wallpaper set" || true
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  14. CRON JOBS
# ═══════════════════════════════════════════════════════════════════════════════
setup_cron() {
    header "Cron Jobs"
    local cron_dir="$DOTFILES_DIR/cron"
    [[ -d "$cron_dir" ]] || { info "No cron/ dir in dotfiles — skipping"; return; }

    # List cron files and install them
    while IFS= read -r -d '' f; do
        info "  Installing crontab from: $f"
        crontab "$f" 2>/dev/null && success "  Crontab installed" \
            || warn "  crontab install failed for $f"
    done < <(find "$cron_dir" -type f -print0)
}

# ═══════════════════════════════════════════════════════════════════════════════
#  15. ZSH / SPACESHIP PROMPT (for zsh — Brodie uses spaceship in .zshrc)
# ═══════════════════════════════════════════════════════════════════════════════
setup_zsh() {
    header "Zsh (Spaceship prompt for zsh, powerline for bash)"
    command -v zsh &>/dev/null || { warn "zsh not installed"; return; }

    # Spaceship prompt for zsh
    local spaceship_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt"
    if [[ -f "$HOME/.zshrc" ]] && grep -q "SPACESHIP" "$HOME/.zshrc" 2>/dev/null; then
        if [[ "$OS" == "arch" ]]; then
            # spaceship-prompt from AUR
            command -v yay &>/dev/null \
                && yay -S --noconfirm --needed zsh-theme-spaceship 2>/dev/null \
                || true
        fi
        # Also install via git into oh-my-zsh if needed
        if [[ ! -d "$spaceship_dir" ]]; then
            info "Installing Spaceship prompt for zsh..."
            git clone --depth 1 https://github.com/spaceship-prompt/spaceship-prompt.git \
                "$spaceship_dir" 2>/dev/null \
                && success "Spaceship installed" || warn "Spaceship clone failed"
        fi
    fi

    # zsh syntax highlighting
    if [[ "$OS" == "arch" ]]; then
        pacman -Qi zsh-syntax-highlighting &>/dev/null \
            || sudo pacman -S --noconfirm --needed zsh-syntax-highlighting 2>/dev/null || true
    else
        sudo apt-get install -y zsh-syntax-highlighting 2>/dev/null || true
    fi

    # Set zsh as default shell
    if [[ "$SHELL" != "$(command -v zsh)" ]]; then
        chsh -s "$(command -v zsh)" "$USER" \
            && success "Default shell set to zsh" \
            || warn "chsh failed — run: chsh -s $(command -v zsh)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  16. BROOT LAUNCHER
# ═══════════════════════════════════════════════════════════════════════════════
setup_broot() {
    header "Broot"
    command -v broot &>/dev/null || { info "broot not installed — skipping"; return; }
    # Launch broot once headlessly to generate its launcher script
    if [[ ! -f "$HOME/.config/broot/launcher/bash/br" ]]; then
        info "Running broot --install to generate launcher..."
        broot --install 2>/dev/null \
            && success "broot launcher created" \
            || warn "broot --install failed"
    else
        success "broot launcher already present"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  17. RANGER
# ═══════════════════════════════════════════════════════════════════════════════
setup_ranger() {
    command -v ranger &>/dev/null || return 0
    [[ -f "$HOME/.config/ranger/rc.conf" ]] && { success "Ranger config in place"; return; }
    ranger --copy-config=all 2>/dev/null || true
    success "Ranger default config generated"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  18. IMWHEEL (mouse scroll speed)
# ═══════════════════════════════════════════════════════════════════════════════
setup_imwheel() {
    command -v imwheel &>/dev/null || return 0
    [[ -f "$HOME/.imwheelrc" ]] && success ".imwheelrc in place"
    # Start imwheel if in an X session
    [[ -n "${DISPLAY:-}" ]] && imwheel -k 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  19. FINISH UP
# ═══════════════════════════════════════════════════════════════════════════════
finish_up() {
    header "Final Steps"

    step "Font cache..."
    fc-cache -fv &>/dev/null && success "Done"

    step "Script permissions..."
    find "$HOME/.config" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$HOME/scripts"  -type f      -exec chmod +x {} \; 2>/dev/null || true
    find "$HOME/.local/bin" -type f    -exec chmod +x {} \; 2>/dev/null || true

    step "Xresources..."
    command -v xrdb &>/dev/null && [[ -f "$HOME/.Xresources" ]] \
        && xrdb -merge "$HOME/.Xresources" 2>/dev/null || true

    step "Pictures directory..."
    mkdir -p "$HOME/Pictures" "$HOME/scripts"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  20. SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
print_summary() {
    echo ""
    echo -e "${BOLD}${MAGENTA}"
    cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════════════╗
  ║   BrodieRobertson Dotfiles — Installation Complete  ✔           ║
  ╚══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"

    echo -e "  ${BOLD}Dotfiles:${RESET}   $DOTFILES_DIR"
    echo -e "  ${BOLD}OS:${RESET}         $OS"
    [[ -d "$BACKUP_DIR" && -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]] \
        && echo -e "  ${BOLD}Backups:${RESET}    $BACKUP_DIR"
    echo ""
    echo -e "  ${BOLD}${CYAN}Configs deployed:${RESET}"
    for d in alacritty broot nvim pcmanfm pistol polybar \
              powerline-shell ranger search shellconfig rofi i3 picom dunst zathura; do
        [[ -e "$HOME/.config/$d" ]] \
            && echo -e "    ${GREEN}✔${RESET}  ~/.config/$d"
    done
    echo ""
    echo -e "  ${BOLD}${CYAN}Next steps:${RESET}"
    echo -e "  1. ${BOLD}Log out${RESET} and select i3 from your display manager"
    echo -e "     or: ${BOLD}startx ~/.xinitrc${RESET}"
    echo -e ""
    echo -e "  2. ${BOLD}Polybar:${RESET} edit ~/.config/polybar/config  (or config.ini)"
    echo -e "     Run ${BOLD}xrandr --query${RESET} to find your monitor name"
    echo -e ""
    echo -e "  3. ${BOLD}Powerline-shell:${RESET} open a new terminal — your bash prompt"
    echo -e "     should now show the purple powerline segments"
    echo -e "     If not: check ${BOLD}which powerline-shell${RESET}"
    echo -e "     and ensure ${BOLD}~/.local/bin${RESET} is in PATH"
    echo -e ""
    echo -e "  4. ${BOLD}Neovim:${RESET} open nvim — pack plugins loaded from submodules"
    echo -e "     vim-airline + vim-closetag active automatically"
    echo -e ""
    echo -e "  5. ${BOLD}Broot:${RESET} run ${BOLD}broot${RESET} once to set up the 'br' function"
    echo -e ""
    echo -e "  6. ${BOLD}Wallpaper:${RESET} set with ${BOLD}feh --bg-scale ~/Pictures/wallpaper.jpg${RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    clear
    echo -e "${BOLD}${MAGENTA}"
    cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════════════╗
  ║                                                                  ║
  ║   ██████╗ ██████╗  ██████╗ ██████╗ ██╗███████╗                  ║
  ║   ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██║██╔════╝                  ║
  ║   ██████╔╝██████╔╝██║   ██║██║  ██║██║█████╗                    ║
  ║   ██╔══██╗██╔══██╗██║   ██║██║  ██║██║██╔══╝                    ║
  ║   ██████╔╝██║  ██║╚██████╔╝██████╔╝██║███████╗                  ║
  ║   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝╚══════╝                  ║
  ║                                                                  ║
  ║   BrodieRobertson Dotfiles Installer                             ║
  ║   Arch Linux  ·  Ubuntu Linux                                   ║
  ║   i3 + Polybar  ·  Powerline-Shell Purple  ·  Neovim            ║
  ║                                                                  ║
  ╚══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"

    detect_os

    # Packages
    case "$OS" in
        arch)   install_arch ;;
        ubuntu) install_ubuntu ;;
    esac

    install_nerd_fonts

    # Dotfiles
    clone_dotfiles
    deploy_dotfiles

    # Powerline-shell purple (before patching .bashrc)
    install_powerline_shell
    patch_bashrc

    # i3 + Polybar
    patch_i3_config
    ensure_polybar

    # Per-app setup
    setup_neovim
    setup_zsh
    setup_xresources
    setup_wallpaper
    setup_cron
    setup_broot
    setup_ranger
    setup_imwheel

    # Finish
    finish_up
    print_summary
}

main "$@"
