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
    [ValidateSet('kiro','claude','copilot','codex','all')]
    [string]$Agent = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# Agent directory map
# ---------------------------------------------------------------------------
function Get-AgentSkillsDir([string]$AgentName) {
    switch ($AgentName) {
        'kiro'    { Join-Path $env:USERPROFILE '.kiro\skills' }
        'claude'  { Join-Path $env:USERPROFILE '.claude\skills' }
        'copilot' { Join-Path $env:USERPROFILE '.copilot\skills' }
        'codex'   { Join-Path $env:USERPROFILE '.codex\skills' }
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
    Write-Host "  5) All of the above"
    $choice = Read-Host "Choice [1-5]"
    $Agent = switch ($choice) {
        '1' { 'kiro' }   '2' { 'claude' }
        '3' { 'copilot' } '4' { 'codex' }
        '5' { 'all' }
        default { Write-Warning "Invalid choice, defaulting to kiro."; 'kiro' }
    }
}

$SelectedAgents = if ($Agent -eq 'all') {
    @('kiro','claude','copilot','codex')
} else {
    @($Agent)
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
    Write-Host "  v $SkillName (local)"
}

# ---------------------------------------------------------------------------
# Main: read registry.txt and install
# ---------------------------------------------------------------------------
$registryPath = Join-Path $RepoDir 'registry.txt'
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

Write-Host "`nDone. Run scripts\setup-credentials.ps1 to configure service credentials."
