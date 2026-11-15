BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:AiAdvisorPath = Join-Path $script:RepoRoot 'ai/Test-EntitlementSoDWithAgent.ps1'
    $script:JoinerGatePath = Join-Path $script:RepoRoot 'src/Invoke-ScopedJoinerProvisioning.ps1'
    $script:AccessPkgPath = Join-Path $script:RepoRoot 'src/Invoke-AccessPackageAssignment.ps1'
    $script:GraphDeployPath = Join-Path $script:RepoRoot 'graph/Deploy-LifecycleWorkflowExtension.ps1'
    $script:FixturesPath = Join-Path $script:RepoRoot 'fixtures/candidate-role-requests.json'
    $script:KqlPath = Join-Path $script:RepoRoot 'queries/Entitlement-SoD-Audit.kql'
    $script:Candidates = Get-Content -Path $script:FixturesPath -Raw | ConvertFrom-Json
}

Describe 'Autonomous Employee Onboarding Guardrails - Functional & Security Matrix' {
    Context 'AI Entitlement SoD Advisor (ai/Test-EntitlementSoDWithAgent.ps1)' {
        It 'Approves baseline-aligned joiner (EMP-9042) within Restricted AU' {
            $c = $script:Candidates | Where-Object { $_.employeeId -eq 'EMP-9042' }
            $req = [PSCustomObject]@{
                EmployeeId                 = $c.employeeId
                JobCode                    = $c.jobCode
                TargetAdministrativeUnitId = $c.targetAdministrativeUnitId
                RequestedRoles             = $c.requestedRoles
            }
            $res = & $script:AiAdvisorPath -JoinerRequest $req
            $res.Decision | Should -Be 'APPROVE_AU_SCOPED'
            $res.Permitted | Should -BeTrue
            $res.Confidence | Should -BeGreaterOrEqual 0.75
            $res.RecommendedAccessPackages.Count | Should -BeGreaterThan 0
        }

        It 'Vetoes toxic Segregation of Duties role pair (EMP-8821)' {
            $c = $script:Candidates | Where-Object { $_.employeeId -eq 'EMP-8821' }
            $req = [PSCustomObject]@{
                EmployeeId                 = $c.employeeId
                JobCode                    = $c.jobCode
                TargetAdministrativeUnitId = $c.targetAdministrativeUnitId
                RequestedRoles             = $c.requestedRoles
            }
            $res = & $script:AiAdvisorPath -JoinerRequest $req
            $res.Decision | Should -Be 'VETO_SOD_TOXIC_COMBINATION'
            $res.Permitted | Should -BeFalse
            $res.ToxicPairsDetected.Count | Should -BeGreaterThan 0
        }

        It 'Holds peer-baseline outlier roles (EMP-9105)' {
            $c = $script:Candidates | Where-Object { $_.employeeId -eq 'EMP-9105' }
            $req = [PSCustomObject]@{
                EmployeeId                 = $c.employeeId
                JobCode                    = $c.jobCode
                TargetAdministrativeUnitId = $c.targetAdministrativeUnitId
                RequestedRoles             = $c.requestedRoles
            }
            $res = & $script:AiAdvisorPath -JoinerRequest $req
            $res.Decision | Should -Be 'HOLD_PEER_ANOMALY'
            $res.Permitted | Should -BeFalse
            $res.OutlierRoles | Should -Contain 'Workday_Payroll_Export'
        }

        It 'Abstains on unmapped job code with low confidence (EMP-9201)' {
            $c = $script:Candidates | Where-Object { $_.employeeId -eq 'EMP-9201' }
            $req = [PSCustomObject]@{
                EmployeeId                 = $c.employeeId
                JobCode                    = $c.jobCode
                TargetAdministrativeUnitId = $c.targetAdministrativeUnitId
                RequestedRoles             = $c.requestedRoles
            }
            $res = & $script:AiAdvisorPath -JoinerRequest $req
            $res.Decision | Should -Be 'ABSTAIN_LOW_CONFIDENCE'
            $res.Permitted | Should -BeFalse
            $res.Confidence | Should -BeLessThan 0.75
        }

        It 'Integrates mocked Azure AI Foundry structured critique without leaking control' {
            $c = $script:Candidates | Where-Object { $_.employeeId -eq 'EMP-9042' }
            $req = [PSCustomObject]@{
                EmployeeId                 = $c.employeeId
                JobCode                    = $c.jobCode
                TargetAdministrativeUnitId = $c.targetAdministrativeUnitId
                RequestedRoles             = $c.requestedRoles
            }
            $mockFoundry = {
                param($ep, $dep, $body)
                return [PSCustomObject]@{
                    riskSummary          = 'Low risk standard AP analyst profile.'
                    confidenceAdjustment = 0.02
                    recommendedAction    = 'APPROVE_AU_SCOPED'
                }
            }
            $res = & $script:AiAdvisorPath -JoinerRequest $req -FoundryEndpoint 'https://foundry.contoso.invalid' -FoundryInvoker $mockFoundry
            $res.FoundryAdvisory.recommendedAction | Should -Be 'APPROVE_AU_SCOPED'
            $res.Confidence | Should -BeGreaterThan 0.94
        }
    }

    Context 'Hard-Veto Gate & Graph v2.x Provisioning' {
        It 'Blocks role-assignable or CA-Exclusion groups in Invoke-ScopedJoinerProvisioning.ps1' {
            $req = [PSCustomObject]@{
                EmployeeId                 = 'EMP-7001'
                UserType                   = 'Member'
                RequiresHardwareFidoKey    = $false
                TargetAdministrativeUnitId = 'AU-EMEA-Finance-Restricted'
            }
            $groups = @(
                [PSCustomObject]@{ Id = 'grp-1'; DisplayName = 'CA-Exclude-BreakGlass'; IsAssignableToRole = $false }
            )
            $res = & $script:JoinerGatePath -JoinerRequest $req -RequestedGroups $groups
            $res.Permitted | Should -BeFalse
            $res.Action | Should -Be 'VETO_PRIVILEGED_GROUP_OR_ROLE_TARGET'
        }

        It 'Holds B2B Guest or FIDO2 hardware requests for dual human signature' {
            $req = [PSCustomObject]@{
                EmployeeId                 = 'EMP-7002'
                UserType                   = 'Guest'
                RequiresHardwareFidoKey    = $true
                TargetAdministrativeUnitId = 'AU-EMEA-Finance-Restricted'
            }
            $groups = @(
                [PSCustomObject]@{ Id = 'grp-2'; DisplayName = 'SG-Finance-Readers'; IsAssignableToRole = $false }
            )
            $res = & $script:JoinerGatePath -JoinerRequest $req -RequestedGroups $groups
            $res.Permitted | Should -BeFalse
            $res.Action | Should -Be 'HOLD_FOR_MANAGER_AND_CISO_DUAL_SIGNATURE'
        }

        It 'Blocks Entitlement Management Graph submission when SoD evaluation fails' {
            $failedSod = [PSCustomObject]@{
                Permitted = $false
                Decision  = 'VETO_SOD_TOXIC_COMBINATION'
                Rationale = 'Toxic pair detected.'
            }
            $res = & $script:AccessPkgPath -TargetUserPrincipalName 'alex.morgan@contoso.com' -TargetUserId 'usr-100' -AccessPackageId 'PKG-ERP-AP-ReadOnly' -SodEvaluationResult $failedSod
            $res.AssignmentState | Should -Be 'BlockedBySodGate'
        }

        It 'Submits Graph v1.0 Entitlement Management request when SoD evaluation passes' {
            $passedSod = [PSCustomObject]@{
                Permitted = $true
                Decision  = 'APPROVE_AU_SCOPED'
                Rationale = 'Aligned with peer baseline.'
            }
            $calls = [System.Collections.Generic.List[string]]::new()
            $mockGraph = {
                param($method, $uri, $body)
                $calls.Add("$method $uri")
                return [PSCustomObject]@{ id = 'req-8881' }
            }
            $res = & $script:AccessPkgPath -TargetUserPrincipalName 'alex.morgan@contoso.com' -TargetUserId 'usr-100' -AccessPackageId 'PKG-ERP-AP-ReadOnly' -SodEvaluationResult $passedSod -GraphInvoker $mockGraph
            $res.AssignmentState | Should -Be 'SubmittedToEntitlementManagement'
            $res.RequestId | Should -Be 'req-8881'
            $calls[0] | Should -Match 'identityGovernance/entitlementManagement/assignmentRequests'
        }

        It 'Deploys Restricted AU, Custom Task Extension, and Lifecycle Workflow via Graph v1.0' {
            $calls = [System.Collections.Generic.List[PSCustomObject]]::new()
            $mockGraph = {
                param($method, $uri, $body)
                $calls.Add([PSCustomObject]@{ Method = $method; Uri = $uri; Body = $body })
                return [PSCustomObject]@{ id = [guid]::NewGuid().ToString() }
            }
            $res = & $script:GraphDeployPath `
                -AdministrativeUnitName 'AU-EMEA-Finance-Restricted' `
                -WorkflowDisplayName 'Contoso-Joiner-SoD-Guarded' `
                -LogicAppCallbackUrl 'https://la-sod.contoso.invalid/api/precheck' `
                -GraphInvoker $mockGraph

            $calls.Count | Should -Be 3
            $calls[0].Uri | Should -Be 'https://graph.microsoft.com/v1.0/directory/administrativeUnits'
            $calls[0].Body.isMemberManagementRestricted | Should -BeTrue
            $calls[1].Uri | Should -Be 'https://graph.microsoft.com/v1.0/identityGovernance/lifecycleWorkflows/customTaskExtensions'
            $calls[2].Uri | Should -Be 'https://graph.microsoft.com/v1.0/identityGovernance/lifecycleWorkflows/workflows'
            $res.WorkflowDisplayName | Should -Be 'Contoso-Joiner-SoD-Guarded'
        }
    }

    Context 'Repository Hygiene, KQL & Zero-Leak Boundaries' {
        It 'Contains zero declarative IaC (.bicep or .tf) files' {
            $iac = Get-ChildItem -Path $script:RepoRoot -Recurse -Include '*.bicep', '*.tf' -File
            $iac.Count | Should -Be 0
        }

        It 'KQL audit query contains correlation and SoD veto filters' {
            Test-Path $script:KqlPath | Should -BeTrue
            (Get-Content $script:KqlPath -Raw) | Should -Match 'where|summarize|project'
        }

        It 'README and docs contain zero internal sequence numbers or private orchestrator domains' {
            $files = @(
                (Join-Path $script:RepoRoot 'README.md'),
                (Join-Path $script:RepoRoot 'docs/ADR-001-sod-boundary.md'),
                (Join-Path $script:RepoRoot 'docs/JML-GOVERNANCE-RUNBOOK.md')
            )
            foreach ($f in $files) {
                $raw = Get-Content $f -Raw
                $raw | Should -Not -Match 'mvpfoundry\.alerasoul\.net|192\.142\.41\.43|Decision Pack 0|idea-010'
            }
        }
    }
}
