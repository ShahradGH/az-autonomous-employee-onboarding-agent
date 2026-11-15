<#
.SYNOPSIS
    Deploys Microsoft Entra ID Governance Lifecycle Workflow, Custom Task Extension, and Restricted Management Administrative Unit via Graph v2.x.
.DESCRIPTION
    Uses Invoke-MgGraphRequest (Microsoft Graph v1.0/beta) to provision a Restricted Management Administrative Unit
    and wire a Joiner Lifecycle Workflow with a Custom Task Extension backed by an Azure Logic App / Function webhook.
    Supports -WhatIf and an injectable -GraphInvoker for deterministic Pester verification.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$AdministrativeUnitName,

    [Parameter(Mandatory)]
    [string]$WorkflowDisplayName,

    [Parameter(Mandatory)]
    [string]$LogicAppCallbackUrl,

    [Parameter()]
    [string]$ExtensionDisplayName = 'Contoso-SoD-Joiner-PreCheck-Extension',

    [Parameter()]
    [string]$ClientAppId = '00000000-0000-0000-0000-000000000110',

    [Parameter()]
    [int]$DaysBeforeHire = 1,

    [Parameter()]
    [scriptblock]$GraphInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GraphCall {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter()] [object]$Body
    )
    if ($null -ne $GraphInvoker) {
        return & $GraphInvoker $Method $Uri $Body
    }
    $params = @{
        Method      = $Method
        Uri         = $Uri
        ContentType = 'application/json'
    }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
    }
    return Invoke-MgGraphRequest @params
}

$auBody = @{
    displayName                   = $AdministrativeUnitName
    description                   = 'Restricted Management Administrative Unit for automated joiner onboarding guardrails.'
    isMemberManagementRestricted  = $true
    membershipType                = 'Assigned'
}

$extensionBody = @{
    displayName             = $ExtensionDisplayName
    description             = 'Invokes AI SoD and peer-baseline entitlement evaluation before access package assignment.'
    endpointConfiguration   = @{
        '@odata.type' = '#microsoft.graph.logicAppTriggerEndpointConfiguration'
        subscriptionId = '00000000-0000-0000-0000-000000000000'
        resourceGroupName = 'rg-contoso-iam-governance'
        logicAppName = 'la-sod-joiner-precheck'
        url = $LogicAppCallbackUrl
    }
    authenticationConfiguration = @{
        '@odata.type' = '#microsoft.graph.azureAdTokenAuthentication'
        resourceId    = "api://$ClientAppId"
    }
    clientConfiguration     = @{
        timeoutInMilliseconds     = 10000
        maximumRetries            = 2
    }
}

$auResponse = $null
$extResponse = $null
$wfResponse = $null

if ($PSCmdlet.ShouldProcess($AdministrativeUnitName, 'Create Restricted Management Administrative Unit via Graph v1.0')) {
    $auResponse = Invoke-GraphCall -Method 'POST' -Uri 'https://graph.microsoft.com/v1.0/directory/administrativeUnits' -Body $auBody
}

if ($PSCmdlet.ShouldProcess($ExtensionDisplayName, 'Create Lifecycle Workflows Custom Task Extension via Graph v1.0')) {
    $extResponse = Invoke-GraphCall -Method 'POST' -Uri 'https://graph.microsoft.com/v1.0/identityGovernance/lifecycleWorkflows/customTaskExtensions' -Body $extensionBody
}

$extensionId = if ($null -ne $extResponse -and $extResponse.id) { $extResponse.id } else { '00000000-0000-0000-0000-000000000220' }
$auId = if ($null -ne $auResponse -and $auResponse.id) { $auResponse.id } else { '00000000-0000-0000-0000-000000000330' }

$workflowBody = @{
    displayName        = $WorkflowDisplayName
    description        = 'Scoped joiner onboarding workflow with AI SoD pre-check and Restricted AU containment.'
    category           = 'joiner'
    isEnabled          = $true
    isSchedulingEnabled = $true
    executionConditions = @{
        '@odata.type' = '#microsoft.graph.identityGovernance.triggerAndScopeBasedConditions'
        scope         = @{
            '@odata.type' = '#microsoft.graph.identityGovernance.ruleBasedSubjectSet'
            rule          = "(department eq 'Finance-AccountsPayable') or (department eq 'Platform-Engineering')"
        }
        trigger       = @{
            '@odata.type'       = '#microsoft.graph.identityGovernance.timeBasedAttributeTrigger'
            timeBasedAttribute  = 'employeeHireDate'
            offsetInDays        = -1 * [Math]::Abs($DaysBeforeHire)
        }
    }
    tasks              = @(
        @{
            category               = 'joiner'
            continueOnError        = $false
            description            = 'Invoke AI SoD & Peer Baseline Pre-Check Custom Task Extension'
            displayName            = 'Run AI SoD Pre-Check'
            executionSequence      = 1
            isEnabled              = $true
            taskDefinitionId       = '1b555e50-7f65-41d5-b514-5894a026d10d'
            arguments              = @(
                @{
                    name  = 'customTaskExtensionId'
                    value = $extensionId
                }
            )
        },
        @{
            category               = 'joiner'
            continueOnError        = $false
            description            = 'Assign standard department Access Package in Entitlement Management'
            displayName            = 'Assign Scoped Access Package'
            executionSequence      = 2
            isEnabled              = $true
            taskDefinitionId       = 'c26c15f0-608c-4c3c-96f9-2f4c8d1b51f1'
        }
    )
}

if ($PSCmdlet.ShouldProcess($WorkflowDisplayName, 'Create Entra ID Governance Lifecycle Workflow via Graph v1.0')) {
    $wfResponse = Invoke-GraphCall -Method 'POST' -Uri 'https://graph.microsoft.com/v1.0/identityGovernance/lifecycleWorkflows/workflows' -Body $workflowBody
}

return [PSCustomObject]@{
    AdministrativeUnitId   = $auId
    AdministrativeUnitName = $AdministrativeUnitName
    CustomTaskExtensionId  = $extensionId
    WorkflowId             = if ($null -ne $wfResponse -and $wfResponse.id) { $wfResponse.id } else { '00000000-0000-0000-0000-000000000440' }
    WorkflowDisplayName    = $WorkflowDisplayName
    GraphApiVersion        = 'v1.0'
    DeployedAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
}
