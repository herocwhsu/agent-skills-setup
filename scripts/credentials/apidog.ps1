#Requires -Version 5.1
# credentials/apidog.ps1 — manage Apidog credentials
# Usage: .\apidog.ps1 <add|update|delete|list|verify>
param([Parameter(Mandatory)][ValidateSet('add','update','delete','list','verify')][string]$Action)

. "$PSScriptRoot\_store.ps1"

$Slug = 'apidog'

switch ($Action) {
    { $_ -in 'add','update' } {
        $user = Read-Host "Apidog username / email"
        $pass = Read-Host "API token" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
        Store-AgentCredential $Slug $user $plain
        Write-Host "  v Apidog credentials saved"
        Write-Host "  Use in scripts: Read-AgentCredential '$Slug' '$user'"
    }
    'delete' {
        $user = Read-Host "Apidog username / email"
        Remove-AgentCredential $Slug $user
    }
    'list'   { List-AgentCredentials }
    'verify' {
        $user = Read-Host "Apidog username / email"
        Verify-AgentCredential $Slug $user
    }
}
