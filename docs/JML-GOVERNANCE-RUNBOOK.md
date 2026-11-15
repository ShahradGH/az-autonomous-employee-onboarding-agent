# JML Governance Operations Runbook: Autonomous Joiner-Mover-Leaver Guardrails

## 1. Purpose and Scope

This runbook governs Level-2 and Level-3 Identity & Access Management (IAM) operations for the Microsoft Entra ID Governance Lifecycle Workflows onboarding pipeline, its Custom Task Extension webhook, and the AI Entitlement SoD Advisor. All procedures use PowerShell 7.4+ and Microsoft Graph v2.x (`Invoke-MgGraphRequest`).

## 2. Routine Operational Checks

### 2.1 Verifying Lifecycle Workflow & Custom Task Extension Health
1. Authenticate to Microsoft Graph with least-privilege governance scopes (`LifecycleWorkflows.ReadWrite.All`, `AdministrativeUnit.ReadWrite.All`, `EntitlementManagement.ReadWrite.All`).
2. Query active joiner workflows and inspect recent execution runs:
   ```powershell
   Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/identityGovernance/lifecycleWorkflows/workflows?$filter=category eq ''joiner'''
   ```
3. Confirm that Custom Task Extension `Contoso-SoD-Joiner-PreCheck-Extension` has `timeoutInMilliseconds` set to `10000` and `maximumRetries` set to `2`.

### 2.2 Auditing AI SoD Vetoes and Abstentions
Run `queries/Entitlement-SoD-Audit.kql` in the Azure Monitor Log Analytics workspace connected to Entra ID Diagnostic Settings (`AuditLogs`) and the Custom Task Extension Function/Logic App logs. Investigate any spike in:
- `VETO_SOD_TOXIC_COMBINATION`: Indicates a Workday role template or manager peer-clone request attempted to combine mutually exclusive entitlements (e.g., `SAP_Vendor_Master_Create` + `SAP_Payment_Release_Approve`).
- `ABSTAIN_LOW_CONFIDENCE`: Indicates a new or unmapped `JobCode` was received from Workday. Update `ai/entitlement-peer-baseline.json` following CAB approval.

## 3. Incident Response Playbooks

### 3.1 Playbook A: False-Positive Peer Anomaly Hold (`HOLD_PEER_ANOMALY`)
1. Retrieve the structured JSON evaluation output from the Custom Task Extension run log.
2. Inspect `OutlierRoles` and `AnomalyScore`.
3. If the role is legitimately required for the department, submit a Pull Request updating `optionalPeerRoles` in `ai/entitlement-peer-baseline.json` and run `Invoke-Pester ./tests/OnboardingSoD.Tests.ps1` to validate zero regressions.
4. Manually trigger the Entitlement Management Access Package assignment only after Manager + IAM Reviewer approval.

### 3.2 Playbook B: Custom Task Extension Webhook Timeout or 5xx
1. Lifecycle Workflows are configured with `continueOnError = $false` on the SoD Pre-Check task. This is **intentional fail-closed behaviour**: if the AI/SoD pre-check fails, no Access Packages are assigned.
2. Check Azure Function / Logic App health and Azure AI Foundry endpoint latency.
3. If the Foundry endpoint is degraded, `ai/Test-EntitlementSoDWithAgent.ps1` automatically falls back to deterministic local peer-baseline and toxic-pair evaluation when `-FoundryEndpoint` is omitted.

### 3.3 Playbook C: Restricted Management Administrative Unit (RMAU) Lockout
1. Verify membership of the RMAU (`AU-EMEA-Finance-Restricted`, etc.) via Graph v1.0:
   ```powershell
   Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/directory/administrativeUnits'
   ```
2. Only Privileged Authentication Administrators or AU-scoped User Administrators assigned directly to the RMAU may modify restricted accounts. Never grant tenant-wide User Administrator to regional helpdesk groups.
