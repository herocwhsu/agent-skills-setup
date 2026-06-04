#Requires -Version 5.1
<#
.SYNOPSIS
    Install agent skills declared in registry.txt (Windows native PowerShell).
.DESCRIPTION
    Reads registry.txt and installs pip/github/local skills into the chosen
    agent's skills directory. Equivalent to scripts/install.sh for Windows.
.EXAMPLE
    .\scripts\install.ps1
    .\scripts\install.ps1 -Agent kiro
#>
param(
    [ValidateSet('kiro','claude','copilot','codex','gemini','all')]
    [string]$Agent = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $env:USERPROFILE '.agent-skills-setup'
$InstalledList = Join-Path $RuntimeDir 'installed.txt'

# ---------------------------------------------------------------------------
# Agent directory map
# ---------------------------------------------------------------------------
function Get-AgentSkillsDir([string]$AgentName) {
    switch ($AgentName) {
        'kiro'    { Join-Path $env:USERPROFILE '.kiro\skills' }
        'claude'  { Join-Path $env:USERPROFILE '.claude\skills' }
        'copilot' { Join-Path $env:USERPROFILE '.copilot\skills' }
        'codex'   { Join-Path $env:USERPROFILE '.codex\skills' }
        'gemini'  { Join-Path $env:USERPROFILE '.gemini\skills' }
        default   { throw "Unknown agent: $AgentName" }
    }
}

# ---------------------------------------------------------------------------
# Agent selection
# ---------------------------------------------------------------------------
if (-not $Agent) {
    Write-Host "`nWhich agent(s) to target?"
    Write-Host "  1) Kiro        (~\.kiro\skills\)"
    Write-Host "  2) Claude Code (~\.claude\skills\)"
    Write-Host "  3) Copilot     (~\.copilot\skills\)"
    Write-Host "  4) Codex       (~\.codex\skills\)"
    Write-Host "  5) Gemini CLI  (~\.gemini\skills\)"
    Write-Host "  6) All of the above"
    $choice = Read-Host "Choice [1-6]"
    $Agent = switch ($choice) {
        '1' { 'kiro' }   '2' { 'claude' }
        '3' { 'copilot' } '4' { 'codex' }
        '5' { 'gemini' }
        '6' { 'all' }
        default { Write-Warning "Invalid choice, defaulting to kiro."; 'kiro' }
    }
}

$SelectedAgents = if ($Agent -eq 'all') {
    @('kiro','claude','copilot','codex','gemini')
} else {
    @($Agent)
}

# ---------------------------------------------------------------------------
# Cross-agent runtime dir
# ---------------------------------------------------------------------------
function Install-RuntimeDir {
    New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
    Copy-Item (Join-Path $RepoDir 'lib\lib.sh') (Join-Path $RuntimeDir 'lib.sh') -Force
    Copy-Item (Join-Path $RepoDir 'scripts\credentials\_store.sh') (Join-Path $RuntimeDir '_store.sh') -Force
    Write-Host "  v runtime -> $RuntimeDir"
}

function Invoke-KeychainMigration {
    # Best-effort warning for any agent-skills:* entries left in Credential Manager.
    $found = cmdkey /list 2>$null | Select-String 'agent-skills:'
    if ($found) {
        Write-Warning "Found credentials with 'agent-skills:' prefix. Re-run setup-credentials.ps1 for each service to migrate to 'agent-skills-setup:'."
    }
}

function Initialize-InstalledList {
    Set-Content -Path $InstalledList -Value '' -Force
}

function Add-InstalledSkill([string]$Name) {
    Add-Content -Path $InstalledList -Value $Name
}

function Install-KiroPrompts {
    $target = Join-Path $env:USERPROFILE '.kiro\prompts'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $count = 0
    $promptsDir = Join-Path $RepoDir 'prompts'
    if (Test-Path $promptsDir) {
        foreach ($f in Get-ChildItem $promptsDir -Filter '*.md') {
            $content = Get-Content $f.FullName -Raw
            $content = $content -replace '/Users/<user>', $env:USERPROFILE
            Set-Content -Path (Join-Path $target $f.Name) -Value $content
            $count++
        }
    }
    Write-Host "  v kiro prompts ($count files) -> $target"
}

function Install-KiroAgentConfig([string]$SkillsDir) {
    $agentsDir = Join-Path $env:USERPROFILE '.kiro\agents'
    New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
    $out = Join-Path $agentsDir 'default.json'
    $steeringRef = '    "file://~/.kiro/steering/engineering-rules.md"'

    $entries = @($steeringRef)
    if (Test-Path $SkillsDir) {
        $skills = Get-ChildItem -Path $SkillsDir -Filter 'SKILL.md' -Recurse -Depth 2 | Sort-Object FullName
        foreach ($s in $skills) {
            $rel = $s.FullName -replace [regex]::Escape($env:USERPROFILE), '~'
            $rel = $rel -replace '\\', '/'
            $entries += "    ""skill://$rel"""
        }
    }

    $lines = @('{', '    "name": "kiro_default",', '    "description": "Default Kiro agent with spec-gated workflow skills.",', '    "resources": [')
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($i -lt $entries.Count - 1) {
            $lines += $entries[$i] + ','
        } else {
            $lines += $entries[$i]
        }
    }
    $lines += @('    ]', '}')
    $lines | Set-Content -Path $out -Encoding UTF8
    Write-Host "  v kiro agent config -> $out ($($entries.Count) resources)"
}
}

# ---------------------------------------------------------------------------
# Download helper
# ---------------------------------------------------------------------------
function Invoke-Download([string]$Url, [string]$Dest) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

# ---------------------------------------------------------------------------
# Install handlers
# ---------------------------------------------------------------------------
function Install-NpmSkill([string]$Package) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Warning "npm not found — skipping npm install for $Package"
        Write-Warning "  Install Node.js + npm to enable: https://nodejs.org/"
        return
    }
    & $npm.Source install -g $Package
    Write-Host "  v $Package (npm)"
}

function Install-PipSkill([string]$Package, [string]$TargetDir) {
    $pip = Get-Command pip3 -ErrorAction SilentlyContinue
    if (-not $pip) { $pip = Get-Command pip -ErrorAction SilentlyContinue }
    if (-not $pip) {
        Write-Warning "pip not found — falling back to GitHub zip for $Package"
        return $false
    }
    & $pip.Source install --quiet --upgrade $Package
    $sp = Get-Command agent-superpowers -ErrorAction SilentlyContinue
    if ($sp) { & $sp.Source install --skip-existing 2>$null }
    Write-Host "  v $Package (pip)"
    return $true
}

function Install-GithubSkill([string]$Repo, [string]$Subpath, [string]$TargetDir) {
    $repoName = $Repo.Split('/')[-1]
    $zip  = Join-Path $env:TEMP "agent-skills-$repoName.zip"
    $extr = Join-Path $env:TEMP "agent-skills-$repoName-extract"

    Invoke-Download "https://github.com/$Repo/archive/refs/heads/main.zip" $zip
    if (Test-Path $extr) { Remove-Item $extr -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extr
    Remove-Item $zip

    $branchDir = Get-ChildItem $extr -Directory | Where-Object { $_.Name -like "$repoName-*" } | Select-Object -First 1
    if (-not $branchDir) { throw "Could not find extracted dir for $Repo" }

    $srcDir = Join-Path $branchDir.FullName $Subpath
    if (-not (Test-Path $srcDir)) { throw "Subpath '$Subpath' not found in $Repo" }

    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    $count = 0
    foreach ($skillDir in Get-ChildItem $srcDir -Directory) {
        $dest = Join-Path $TargetDir $skillDir.Name
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item $skillDir.FullName $dest -Recurse
        Add-InstalledSkill $skillDir.Name
        $count++
    }
    Remove-Item $extr -Recurse -Force
    Write-Host "  v $Repo ($count skills)"
}

function Install-LocalSkill([string]$SkillName, [string]$TargetDir) {
    $src = Join-Path $RepoDir "skills\$SkillName"
    if (-not (Test-Path $src)) {
        Write-Warning "Local skill '$SkillName' not found at $src"
        return
    }
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    $dest = Join-Path $TargetDir $SkillName
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $src $dest -Recurse
    Add-InstalledSkill $SkillName
    Write-Host "  v $SkillName (local)"
}

# ---------------------------------------------------------------------------
# Main: read registry.txt and install
# ---------------------------------------------------------------------------
$registryPath = Join-Path $RepoDir 'registry.txt'

Write-Host "`n==> Installing runtime helpers..."
Install-RuntimeDir

if (Select-String -Path $registryPath -Pattern '^npm\s+@fission-ai/openspec' -Quiet) {
    Write-Host ""
    Write-Host "==> OpenSpec post-install steps (per target repo):"
    Write-Host "    cd <your-repo>"
    Write-Host "    openspec init"
    Write-Host "    # For the full slash-command set:"
    Write-Host "    openspec config profile expanded && openspec update"
}

Write-Host "`n==> Migrating keychain entries (if any)..."
Invoke-KeychainMigration

Initialize-InstalledList

Write-Host "`n==> Installing skills from registry.txt..."

foreach ($agentName in $SelectedAgents) {
    $targetDir = Get-AgentSkillsDir $agentName
    Write-Host "`n  Agent: $agentName -> $targetDir"

    foreach ($line in Get-Content $registryPath) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        $parts = $line -split '\s+', 3
        $type  = $parts[0]
        $id    = $parts[1]
        $extra = if ($parts.Count -ge 3) { $parts[2] } else { '.' }

        try {
            switch ($type) {
                'npm'    { Install-NpmSkill    $id }
                'pip'    { Install-PipSkill    $id $targetDir }
                'github' { Install-GithubSkill $id $extra $targetDir }
                'local'  { Install-LocalSkill  $id $targetDir }
                default  { Write-Warning "Unknown type '$type' for '$id', skipping." }
            }
        } catch {
            Write-Warning "Failed to install $id`: $_"
        }
    }
}

# Install Kiro prompts and agent config if kiro was selected
if ($SelectedAgents -contains 'kiro') {
    Install-KiroPrompts
    $kiroSkillsDir = Get-AgentSkillsDir 'kiro'
    Install-KiroAgentConfig $kiroSkillsDir
}

Write-Host "`nDone. Run scripts\setup-credentials.ps1 to configure service credentials."
