#Requires -Version 5.1
# credentials/jira.ps1 — manage Jira credentials
# Usage: .\jira.ps1 <add|update|delete|list|verify>
param([Parameter(Mandatory)][ValidateSet('add','update','delete','list','verify')][string]$Action)

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
        Write-Host "  v Jira credentials saved"
        Write-Host "  Use in scripts: Read-AgentCredential '$slug' '$user'"
    }
    'delete' {
        $url  = Read-Host "Jira URL"
        $user = Read-Host "Username"
        Remove-AgentCredential (Get-Slug $url) $user
    }
    'list'   { List-AgentCredentials }
    'verify' {
        $url  = Read-Host "Jira URL"
        $user = Read-Host "Username"
        Verify-AgentCredential (Get-Slug $url) $user
    }
}
