#Requires -Version 5.1
# credentials/_store.ps1 — Windows Credential Manager CRUD
# Dot-source this file: . "$PSScriptRoot\_store.ps1"
#
# All entries are prefixed with "agent-skills:" to avoid collisions.
# Passwords are NEVER exported to env vars — read from keychain at use-time only.
#
# Public functions:
#   Store-AgentCredential  <slug> <username> <password>
#   Read-AgentCredential   <slug> <username>  -> plaintext (use immediately, don't store)
#   Remove-AgentCredential <slug> <username>
#   Verify-AgentCredential <slug> <username>  -> writes OK/FAIL, returns bool
#   List-AgentCredentials                     -> prints entries (no passwords)

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
    New-StoredCredential -Target "$target`:$Username" -UserName $Username `
        -Password $Password -Type Generic -Persist LocalMachine | Out-Null
    Write-Host "  v Stored in Windows Credential Manager ($target)"
}

# Returns plaintext password — use immediately, never assign to a persistent variable
function Read-AgentCredential([string]$Slug, [string]$Username) {
    _EnsureCredentialManager
    $target = _SvcKey $Slug
    $cred = Get-StoredCredential -Target "$target`:$Username" -ErrorAction SilentlyContinue
    if ($cred) { return $cred.GetNetworkCredential().Password }
    return ''
}

# ---------------------------------------------------------------------------
function Verify-AgentCredential([string]$Slug, [string]$Username) {
    $val = Read-AgentCredential $Slug $Username
    if ($val) {
        Write-Host "  v Credential found for $Slug / $Username (value hidden)"
        return $true
    }
    Write-Warning "  x No credential found for $Slug / $Username"
    return $false
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
