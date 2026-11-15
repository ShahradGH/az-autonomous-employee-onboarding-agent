<#
.SYNOPSIS
    Submits a Microsoft Entra Entitlement Management access package assignment request after SoD verification.
.DESCRIPTION
    Validates that the candidate request passed AI SoD evaluation and submits an assignment request to
    Microsoft Graph v1.0 /identityGovernance/entitlementManagement/assignmentRequests.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TargetUserPrincipalName,

    [Parameter(Mandatory)]
    [string]$TargetUserId,

    [Parameter(Mandatory)]
    [string]$AccessPackageId,

    [Parameter(Mandatory)]
    [PSCustomObject]$SodEvaluationResult,

    [Parameter()]
    [string]$Justification = 'Automated joiner onboarding within Restricted Management Administrative Unit.',

    [Parameter()]
    [scriptblock]$GraphInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SodEvaluationResult.Permitted) {
    return [PSCustomObject]@{
        User            = $TargetUserPrincipalName
        AccessPackageId = $AccessPackageId
        AssignmentState = 'BlockedBySodGate'
        Decision        = $SodEvaluationResult.Decision
        Reason          = $SodEvaluationResult.Rationale
    }
}

$payload = @{
    requestType   = 'adminAdd'
    justification = $Justification
    assignment    = @{
        targetId        = $TargetUserId
        accessPackageId = $AccessPackageId
    }
}

$uri = 'https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests'
$graphResp = $null

if ($PSCmdlet.ShouldProcess("$TargetUserPrincipalName -> $AccessPackageId", 'Submit Entitlement Management Assignment Request')) {
    if ($null -ne $GraphInvoker) {
        $graphResp = & $GraphInvoker 'POST' $uri $payload
    }
    else {
        $graphResp = Invoke-MgGraphRequest -Method Post -Uri $uri -Body ($payload | ConvertTo-Json -Depth 6) -ContentType 'application/json'
    }
}

return [PSCustomObject]@{
    User            = $TargetUserPrincipalName
    TargetUserId    = $TargetUserId
    AccessPackageId = $AccessPackageId
    RequestId       = if ($null -ne $graphResp -and $graphResp.id) { $graphResp.id } else { 'pending-whatif' }
    AssignmentState = 'SubmittedToEntitlementManagement'
    Decision        = $SodEvaluationResult.Decision
    SubmittedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
}
