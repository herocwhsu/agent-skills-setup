#Requires -Version 5.1
<#
.SYNOPSIS
    Manage credentials for all services (Windows native PowerShell).
.EXAMPLE
    .\scripts\setup-credentials.ps1
    .\scripts\setup-credentials.ps1 -Service confluence -Action add
#>
param(
    [ValidateSet('confluence','jira','apidog')][string]$Service = '',
    [ValidateSet('add','update','delete','list')][string]$Action = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CredsDir = Join-Path $PSScriptRoot 'credentials'

if (-not $Service) {
    Write-Host "`nWhich service?"
    Write-Host "  1) Confluence"
    Write-Host "  2) Jira"
    Write-Host "  3) Apidog"
    $choice = Read-Host "Choice [1-3]"
    $Service = switch ($choice) {
        '1' { 'confluence' } '2' { 'jira' } '3' { 'apidog' }
        default { Write-Error "Invalid choice."; exit 1 }
    }
}

if (-not $Action) {
    Write-Host "`nAction for $Service?"
    Write-Host "  1) add / update"
    Write-Host "  2) delete"
    Write-Host "  3) list all stored"
    $choice = Read-Host "Choice [1-3]"
    $Action = switch ($choice) {
        '1' { 'add' } '2' { 'delete' } '3' { 'list' }
        default { Write-Error "Invalid choice."; exit 1 }
    }
}

$script = Join-Path $CredsDir "$Service.ps1"
if (-not (Test-Path $script)) {
    Write-Error "No credential handler found for '$Service' ($script)."
    exit 1
}

& $script -Action $Action
