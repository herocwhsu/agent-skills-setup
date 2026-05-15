#Requires -Version 5.1
# credentials/jira.ps1 — manage Jira credentials
# Usage: .\jira.ps1 <add|update|delete|list>
param([Parameter(Mandatory)][ValidateSet('add','update','delete','list')][string]$Action)

. "$PSScriptRoot\_store.ps1"

function Get-Slug([string]$Url) {
    "jira-$(($Url -replace 'https?://' -replace '[^a-zA-Z0-9]','-') -replace '-+','-' -replace '-$')"
}

switch ($Action) {
    { $_ -in 'add','update' } {
        $url  = Read-Host "Jira URL (e.g. https://jira.example.com)"
        $user = Read-Host "Username"
        $pass = Read-Host "Password / API token" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
        $slug = Get-Slug $url
        Store-AgentCredential $slug $user $plain
        Add-ProfileExport $slug $user 'JIRA_PASS'
        Write-Host "  v Jira credentials saved (env: JIRA_PASS)"
    }
    'delete' {
        $url  = Read-Host "Jira URL"
        $user = Read-Host "Username"
        $slug = Get-Slug $url
        Remove-AgentCredential $slug $user
        Remove-ProfileExport $slug
    }
    'list' { List-AgentCredentials }
}
