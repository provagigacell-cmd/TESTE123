#!/usr/bin/env bash
# Instala o Claude Code CLI no macOS (e Linux) com Node.js LTS, npm e Git.
# Uso: bash install-claude-code.sh
set -uo pipefail

NODE_MIN_MAJOR=18
NPM_PKG="@anthropic-ai/claude-code"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *) die "Sistema não suportado: $OS (no Windows use install-claude-code.ps1)" ;;
esac
info "Sistema detectado: $PLATFORM ($(uname -m))"

# Detecta o arquivo de perfil do shell para persistir PATH/variáveis.
case "${SHELL:-}" in
  */zsh)  PROFILE="$HOME/.zshrc" ;;
  */bash) if [ "$PLATFORM" = macos ]; then PROFILE="$HOME/.bash_profile"; else PROFILE="$HOME/.bashrc"; fi ;;
  *)      PROFILE="$HOME/.profile" ;;
esac

persist_line() {
  # Adiciona uma linha ao perfil apenas se ainda não existir.
  local line="$1"
  touch "$PROFILE"
  grep -qxF "$line" "$PROFILE" || { printf '\n%s\n' "$line" >> "$PROFILE"; ok "Adicionado ao $PROFILE: $line"; }
}

# ---------- Homebrew (macOS) ----------
ensure_brew() {
  [ "$PLATFORM" = macos ] || return 1
  if ! has brew; then
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$p" ] && eval "$("$p" shellenv)" && break
    done
  fi
  if ! has brew; then
    info "Instalando Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$p" ] && eval "$("$p" shellenv)" && persist_line "eval \"\$($p shellenv)\"" && break
    done
  fi
  has brew && ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
}

# ---------- Git ----------
ensure_git() {
  if has git && git --version >/dev/null 2>&1; then ok "Git já instalado: $(git --version)"; return; fi
  info "Instalando Git..."
  if [ "$PLATFORM" = macos ]; then
    if ensure_brew; then brew install git
    else
      warn "Homebrew indisponível; usando Xcode Command Line Tools"
      xcode-select --install 2>/dev/null || true
      die "Conclua a instalação do Xcode CLT na janela aberta e rode o script novamente."
    fi
  else
    if   has apt-get; then sudo apt-get update -y && sudo apt-get install -y git
    elif has dnf;     then sudo dnf install -y git
    elif has yum;     then sudo yum install -y git
    elif has pacman;  then sudo pacman -Sy --noconfirm git
    else die "Não encontrei gerenciador de pacotes para instalar o Git."; fi
  fi
  has git || die "Falha ao instalar o Git."
  ok "$(git --version)"
}

# ---------- Node.js LTS + npm ----------
node_major() { node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'; }

install_node_nvm() {
  info "Alternativa: instalando Node.js LTS via nvm..."
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | PROFILE="$PROFILE" bash || return 1
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" && nvm install --lts && nvm alias default 'lts/*'
}

ensure_node() {
  local major; major="$(node_major)"
  if [ -n "$major" ] && [ "$major" -ge "$NODE_MIN_MAJOR" ] && has npm; then
    ok "Node.js já instalado: $(node -v) / npm $(npm -v)"; return
  fi
  [ -n "$major" ] && warn "Node.js $(node -v) é antigo (mínimo v$NODE_MIN_MAJOR); atualizando para LTS."
  info "Instalando Node.js LTS..."
  local done=0
  if [ "$PLATFORM" = macos ] && ensure_brew; then
    brew install node@22 && brew link --overwrite --force node@22 && done=1
  elif [ "$PLATFORM" = linux ] && has apt-get; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs && done=1
  elif [ "$PLATFORM" = linux ] && { has dnf || has yum; }; then
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - && { sudo dnf install -y nodejs 2>/dev/null || sudo yum install -y nodejs; } && done=1
  fi
  hash -r
  major="$(node_major)"
  if [ "$done" -ne 1 ] || [ -z "$major" ] || [ "$major" -lt "$NODE_MIN_MAJOR" ]; then
    install_node_nvm || die "Não foi possível instalar o Node.js."
  fi
  has node && has npm || die "Node.js/npm não encontrados após a instalação."
  ok "Node.js $(node -v) / npm $(npm -v)"
}

# ---------- Claude Code CLI ----------
configure_npm_prefix() {
  # Evita 'sudo npm install -g': usa um prefixo no diretório do usuário se o atual não for gravável.
  local prefix; prefix="$(npm config get prefix)"
  mkdir -p "$prefix/lib" 2>/dev/null
  if [ ! -w "$prefix/lib" ]; then
    info "Prefixo global do npm ($prefix) não é gravável; usando ~/.npm-global"
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    persist_line 'export PATH="$HOME/.npm-global/bin:$PATH"'
  fi
}

ensure_claude() {
  if has claude && claude --version >/dev/null 2>&1; then
    ok "Claude Code já instalado: $(claude --version)"; return
  fi
  configure_npm_prefix
  info "Instalando $NPM_PKG globalmente..."
  if ! npm install -g "$NPM_PKG"; then
    warn "Falha no npm; limpando cache e tentando novamente..."
    npm cache clean --force >/dev/null 2>&1
    npm install -g "$NPM_PKG" || {
      warn "npm falhou de novo; usando o instalador nativo oficial."
      curl -fsSL https://claude.ai/install.sh | bash || die "Falha ao instalar o Claude Code."
      export PATH="$HOME/.local/bin:$PATH"
      persist_line 'export PATH="$HOME/.local/bin:$PATH"'
    }
  fi
  hash -r
  # Garante que o diretório bin global do npm esteja no PATH.
  local bin; bin="$(npm config get prefix)/bin"
  if ! has claude && [ -x "$bin/claude" ]; then
    export PATH="$bin:$PATH"
    persist_line "export PATH=\"$bin:\$PATH\""
  fi
  has claude || die "Comando 'claude' não encontrado no PATH."
}

# ---------- Execução ----------
ensure_git
ensure_node
ensure_claude

# Variável opcional: se ANTHROPIC_API_KEY estiver definida na sessão, persiste no perfil.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  persist_line "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\""
fi

echo
info "Validação"
printf '  node   %s\n' "$(node -v)"
printf '  npm    %s\n' "$(npm -v)"
printf '  git    %s\n' "$(git --version | awk '{print $3}')"
printf '  claude %s\n' "$(claude --version)"
claude --help >/dev/null 2>&1 && ok "claude --help executou com sucesso" || die "claude não respondeu ao --help"

echo
ok "Pronto! Abra um novo terminal (ou rode: source $PROFILE) e execute: claude"
