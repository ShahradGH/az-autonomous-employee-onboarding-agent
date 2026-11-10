# Invoke-ScopedJoinerProvisioning.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [PSCustomObject]$JoinerRequest,
    [Parameter(Mandatory)] [PSCustomObject[]]$RequestedGroups
)

$ErrorActionPreference = 'Stop'

# 1. Hard Veto on Privileged Role-Assignable or CA Exclusion Groups
$privilegedTargets = @($RequestedGroups | Where-Object {
    $_.IsAssignableToRole -eq $true -or
    $_.DisplayName -match '^(?i)(Tier0|Priv|CA-Exclude|GlobalAdmin)'
})

if ($privilegedTargets.Count -gt 0) {
    return [PSCustomObject]@{
        EmployeeId = $JoinerRequest.EmployeeId
        Action     = 'VETO_PRIVILEGED_GROUP_OR_ROLE_TARGET'
        Permitted  = $false
        BlockedIds = @($privilegedTargets.Id)
        Reason     = 'Automated onboarding is strictly forbidden from mutating role-assignable or CA-exclusion groups.'
    }
}

# 2. Dual-Signature Gate on B2B Guest or Hardware Token Requests
if ($JoinerRequest.UserType -eq 'Guest' -or $JoinerRequest.RequiresHardwareFidoKey) {
    return [PSCustomObject]@{
        EmployeeId = $JoinerRequest.EmployeeId
        Action     = 'HOLD_FOR_MANAGER_AND_CISO_DUAL_SIGNATURE'
        Permitted  = $false
        BlockedIds = @()
        Reason     = 'External guest federation and FIDO2 hardware issuance require dual human approval.'
    }
}

return [PSCustomObject]@{
    EmployeeId         = $JoinerRequest.EmployeeId
    Action             = 'PROVISION_AU_SCOPED_STANDARD_JOINER'
    AdministrativeUnit = $JoinerRequest.TargetAdministrativeUnitId
    Permitted          = $true
}
