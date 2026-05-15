#Requires -Version 5.1
# credentials/confluence.ps1 — manage Confluence credentials
# Usage: .\confluence.ps1 <add|update|delete|list>
param([Parameter(Mandatory)][ValidateSet('add','update','delete','list')][string]$Action)

. "$PSScriptRoot\_store.ps1"

function Get-Slug([string]$Url) {
    "confluence-$(($Url -replace 'https?://' -replace '[^a-zA-Z0-9]','-') -replace '-+','-' -replace '-$')"
}

switch ($Action) {
    { $_ -in 'add','update' } {
        $url  = Read-Host "Confluence URL (e.g. https://confluence.example.com)"
        $user = Read-Host "Username"
        $pass = Read-Host "Password" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
        $slug = Get-Slug $url
        Store-AgentCredential $slug $user $plain
        Add-ProfileExport $slug $user 'CONFLUENCE_PASS'
        Write-Host "  v Confluence credentials saved (env: CONFLUENCE_PASS)"
    }
    'delete' {
        $url  = Read-Host "Confluence URL"
        $user = Read-Host "Username"
        $slug = Get-Slug $url
        Remove-AgentCredential $slug $user
        Remove-ProfileExport $slug
    }
    'list' { List-AgentCredentials }
}
