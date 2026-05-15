#Requires -Version 5.1
# credentials/apidog.ps1 — manage Apidog credentials
# Usage: .\apidog.ps1 <add|update|delete|list>
param([Parameter(Mandatory)][ValidateSet('add','update','delete','list')][string]$Action)

. "$PSScriptRoot\_store.ps1"

$Slug = 'apidog'

switch ($Action) {
    { $_ -in 'add','update' } {
        $user = Read-Host "Apidog username / email"
        $pass = Read-Host "API token" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
        Store-AgentCredential $Slug $user $plain
        Add-ProfileExport $Slug $user 'APIDOG_TOKEN'
        Write-Host "  v Apidog credentials saved (env: APIDOG_TOKEN)"
    }
    'delete' {
        $user = Read-Host "Apidog username / email"
        Remove-AgentCredential $Slug $user
        Remove-ProfileExport $Slug
    }
    'list' { List-AgentCredentials }
}
