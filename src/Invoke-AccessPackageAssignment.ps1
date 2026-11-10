# Invoke-AccessPackageAssignment.ps1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TargetUserPrincipalName, [Parameter(Mandatory)][string]$AccessPackageId)
Set-StrictMode -Version Latest
return [PSCustomObject]@{ User = $TargetUserPrincipalName; AccessPackageId = $AccessPackageId; AssignmentState = 'PendingSoDVerification' }
