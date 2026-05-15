# credentials/_store.ps1 — Windows Credential Manager CRUD
# Dot-source this file: . "$PSScriptRoot\_store.ps1"
#
# All entries are prefixed with "agent-skills:" to avoid collisions.
# Requires: CredentialManager module (auto-installed if missing).
#
# Public functions:
#   Store-Credential   <service-slug> <username> <password>
#   Read-Credential    <service-slug> <username>  -> SecureString (or $null)
#   Remove-Credential  <service-slug> <username>
#   List-Credentials                              -> prints stored entries

Set-StrictMode -Version Latest

$script:KeychainPrefix = 'agent-skills'

function _EnsureCredentialManager {
    if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
        Write-Host "  Installing CredentialManager module..."
        Install-Module -Name CredentialManager -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module CredentialManager -ErrorAction Stop
}

function _SvcKey([string]$Slug) { "$script:KeychainPrefix`:$Slug" }

# ---------------------------------------------------------------------------
function Store-AgentCredential([string]$Slug, [string]$Username, [string]$Password) {
    _EnsureCredentialManager
    $target = _SvcKey $Slug
    # New-StoredCredential overwrites if target already exists
    New-StoredCredential -Target "$target`:$Username" -UserName $Username `
        -Password $Password -Type Generic -Persist LocalMachine | Out-Null
    Write-Host "  v Stored in Windows Credential Manager ($target)"
}

# Returns plaintext password string, or empty string if not found
function Read-AgentCredential([string]$Slug, [string]$Username) {
    _EnsureCredentialManager
    $target = _SvcKey $Slug
    $cred = Get-StoredCredential -Target "$target`:$Username" -ErrorAction SilentlyContinue
    if ($cred) {
        return $cred.GetNetworkCredential().Password
    }
    return ''
}

# ---------------------------------------------------------------------------
function Remove-AgentCredential([string]$Slug, [string]$Username) {
    _EnsureCredentialManager
    $target = _SvcKey $Slug
    $key = "$target`:$Username"
    $existing = Get-StoredCredential -Target $key -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-StoredCredential -Target $key -Type Generic
        Write-Host "  v Deleted from Windows Credential Manager ($key)"
    } else {
        Write-Host "  (not found: $key)"
    }
}

# ---------------------------------------------------------------------------
function List-AgentCredentials {
    _EnsureCredentialManager
    Write-Host "Stored credentials (prefix: $script:KeychainPrefix`:):"
    $all = Get-StoredCredential -ErrorAction SilentlyContinue
    $found = $all | Where-Object { $_.Target -like "$script:KeychainPrefix`:*" }
    if ($found) {
        $found | ForEach-Object { Write-Host "  $($_.Target)  [$($_.UserName)]" }
    } else {
        Write-Host "  (none)"
    }
}

# ---------------------------------------------------------------------------
# Add export block to PowerShell profile (idempotent)
function Add-ProfileExport([string]$Slug, [string]$Username, [string]$EnvVar) {
    $target = _SvcKey $Slug
    $marker = "# agent-skills:$Slug"
    $profile_path = $PROFILE  # $PROFILE is the current user's PS profile path

    if (-not (Test-Path $profile_path)) {
        New-Item -ItemType File -Path $profile_path -Force | Out-Null
    }

    $content = Get-Content $profile_path -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($marker)) {
        Write-Host "  Profile already has export for $EnvVar, skipping."
        return
    }

    $block = @"

$marker
`$env:$EnvVar = (Get-StoredCredential -Target '$target`:$Username' -ErrorAction SilentlyContinue)?.GetNetworkCredential().Password
"@
    Add-Content -Path $profile_path -Value $block
    Write-Host "  v Added `$env:$EnvVar export to $profile_path"
}

# Remove export block from PowerShell profile
function Remove-ProfileExport([string]$Slug) {
    $marker = "# agent-skills:$Slug"
    $profile_path = $PROFILE
    if (-not (Test-Path $profile_path)) { return }

    $lines = Get-Content $profile_path
    # Remove marker line and the line immediately after it (the export line)
    $filtered = @()
    $skip = 0
    foreach ($line in $lines) {
        if ($line.Trim() -eq $marker) { $skip = 2; continue }
        if ($skip -gt 0) { $skip--; continue }
        $filtered += $line
    }
    Set-Content -Path $profile_path -Value $filtered
    Write-Host "  v Removed export block for $Slug from $profile_path"
}
