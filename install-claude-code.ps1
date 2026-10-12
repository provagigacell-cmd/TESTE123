# Instala o Claude Code CLI no Windows com Node.js LTS, npm e Git.
# Uso (PowerShell):  powershell -ExecutionPolicy Bypass -File .\install-claude-code.ps1
$ErrorActionPreference = 'Stop'
$NodeMinMajor = 18
$NpmPkg = '@anthropic-ai/claude-code'

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host " v  $m" -ForegroundColor Green }
function Warn($m) { Write-Host " !  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host " x  $m" -ForegroundColor Red; exit 1 }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Add-UserPath($dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $user) { $user = '' }
    if (($user -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', ($user.TrimEnd(';') + ";$dir").TrimStart(';'), 'User')
        Ok "Adicionado ao PATH do usuario: $dir"
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
}

# $IsWindows so existe no PowerShell 6+; no Windows PowerShell 5.1 e $null.
if ($null -ne $IsWindows -and -not $IsWindows) {
    Die 'Este script e para Windows. No macOS/Linux use install-claude-code.sh'
}
Info "Sistema detectado: Windows $([Environment]::OSVersion.Version) ($env:PROCESSOR_ARCHITECTURE)"

# ---------- Gerenciador de pacotes ----------
$PM = $null
if (Has winget) { $PM = 'winget' }
elseif (Has choco) { $PM = 'choco' }
else {
    Warn 'winget nao encontrado; tentando instalar Chocolatey...'
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refresh-Path
        if (Has choco) { $PM = 'choco' }
    } catch { Warn "Falha ao instalar Chocolatey: $($_.Exception.Message)" }
}
if ($PM) { Ok "Gerenciador de pacotes: $PM" } else { Warn 'Nenhum gerenciador de pacotes; usarei downloads diretos.' }

function Install-Pkg($wingetId, $chocoId) {
    if ($PM -eq 'winget') {
        winget install --id $wingetId -e --source winget --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { return $true }
        Warn "winget falhou ($LASTEXITCODE)"
        if (Has choco) { choco install $chocoId -y; return ($LASTEXITCODE -eq 0) }
        return $false
    }
    if ($PM -eq 'choco') { choco install $chocoId -y; return ($LASTEXITCODE -eq 0) }
    return $false
}

# ---------- Git ----------
if (Has git) {
    Ok "Git ja instalado: $(git --version)"
} else {
    Info 'Instalando Git...'
    if (-not (Install-Pkg 'Git.Git' 'git')) {
        Warn 'Tentando download direto do Git for Windows...'
        $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest'
        $asset = $rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
        $exe = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $exe
        Start-Process $exe -ArgumentList '/VERYSILENT', '/NORESTART' -Wait
    }
    Refresh-Path
    if (-not (Has git)) { Die 'Falha ao instalar o Git.' }
    Ok "$(git --version)"
}
# Claude Code no Windows usa o Git Bash; define a variavel se o bash.exe for encontrado.
$gitBash = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe") |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($gitBash -and -not $env:CLAUDE_CODE_GIT_BASH_PATH) {
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $gitBash, 'User')
    $env:CLAUDE_CODE_GIT_BASH_PATH = $gitBash
    Ok "CLAUDE_CODE_GIT_BASH_PATH = $gitBash"
}

# ---------- Node.js LTS + npm ----------
function Node-Major { if (Has node) { [int]((node -v) -replace '^v(\d+).*', '$1') } else { 0 } }

if ((Node-Major) -ge $NodeMinMajor -and (Has npm)) {
    Ok "Node.js ja instalado: $(node -v) / npm $(npm -v)"
} else {
    if ((Node-Major) -gt 0) { Warn "Node.js $(node -v) e antigo; atualizando para LTS." }
    Info 'Instalando Node.js LTS...'
    if (-not (Install-Pkg 'OpenJS.NodeJS.LTS' 'nodejs-lts')) {
        Warn 'Tentando download direto do MSI do Node.js LTS...'
        $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
        $lts = ($idx | Where-Object { $_.lts } | Select-Object -First 1).version
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $msi = Join-Path $env:TEMP "node-$lts-$arch.msi"
        Invoke-WebRequest "https://nodejs.org/dist/$lts/node-$lts-$arch.msi" -OutFile $msi
        Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait
    }
    Refresh-Path
    if (-not (Test-Path "$env:ProgramFiles\nodejs\node.exe") -and -not (Has node)) { Die 'Falha ao instalar o Node.js.' }
    Add-UserPath "$env:ProgramFiles\nodejs"
    Ok "Node.js $(node -v) / npm $(npm -v)"
}

# ---------- Claude Code CLI ----------
$npmBin = "$env:APPDATA\npm"
Add-UserPath $npmBin

if ((Has claude) -and (claude --version 2>$null)) {
    Ok "Claude Code ja instalado: $(claude --version)"
} else {
    Info "Instalando $NpmPkg globalmente..."
    npm install -g $NpmPkg
    if ($LASTEXITCODE -ne 0) {
        Warn 'Falha no npm; limpando cache e tentando novamente...'
        npm cache clean --force | Out-Null
        npm install -g $NpmPkg
    }
    if ($LASTEXITCODE -ne 0) {
        Warn 'npm falhou de novo; usando o instalador nativo oficial.'
        Invoke-Expression (Invoke-RestMethod 'https://claude.ai/install.ps1')
        Add-UserPath "$env:USERPROFILE\.local\bin"
    }
    Refresh-Path
    Add-UserPath $npmBin
    if (-not (Has claude)) { Die "Comando 'claude' nao encontrado no PATH." }
}

# Variavel opcional: persiste ANTHROPIC_API_KEY se estiver definida na sessao.
if ($env:ANTHROPIC_API_KEY) {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $env:ANTHROPIC_API_KEY, 'User')
    Ok 'ANTHROPIC_API_KEY persistida para o usuario.'
}

# ---------- Validacao ----------
Write-Host ''
Info 'Validacao'
Write-Host "  node   $(node -v)"
Write-Host "  npm    $(npm -v)"
Write-Host "  git    $(git --version)"
Write-Host "  claude $(claude --version)"
claude --help *> $null
if ($LASTEXITCODE -eq 0) { Ok 'claude --help executou com sucesso' } else { Die 'claude nao respondeu ao --help' }

Write-Host ''
Ok 'Pronto! Abra um novo terminal e execute: claude'
