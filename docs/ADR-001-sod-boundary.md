# ADR-001: Epistemic & Segregation of Duties (SoD) Boundary for Autonomous Joiner Onboarding

- **Status:** Accepted
- **Date:** 2026-11-15
- **Owners:** Enterprise Identity Architecture & IAM Security Operations

## 1. Context and Problem Statement

Automated employee onboarding pipelines frequently fail in one of two ways: either they remain manual and slow (delaying Day-1 productivity for new joiners), or they over-automate via naive "peer-cloning" scripts that copy every Microsoft Entra group and application role held by a colleague. Over time, peer cloning creates silent privilege creep, violates Segregation of Duties (SoD) controls, and allows an automated service principal to mutate Tier-0 or Conditional Access exclusion groups.

Our architecture must enable Day-1 zero-touch onboarding for standard departmental roles whilst enforcing hard, deterministic security boundaries and an AI-assisted peer-baseline anomaly advisor.

## 2. Decision

We adopt a **Three-Gate Scoped Joiner Architecture** built exclusively on Microsoft Entra ID Governance Lifecycle Workflows, Custom Task Extensions, Restricted Management Administrative Units (RMAUs), and PowerShell 7.4+ / Microsoft Graph v2.x:

1. **Deterministic Hard-Veto Gate (`src/Invoke-ScopedJoinerProvisioning.ps1`)**:
   - Any target group with `IsAssignableToRole = $true` or matching Tier-0 / Conditional Access exclusion naming patterns (`Tier0`, `Priv`, `CA-Exclude`, `GlobalAdmin`) triggers an immediate, non-overridable `VETO_PRIVILEGED_GROUP_OR_ROLE_TARGET`.
   - External B2B guest invitations or hardware FIDO2 token requests are held for dual human signature (`HOLD_FOR_MANAGER_AND_CISO_DUAL_SIGNATURE`).

2. **AI Entitlement Anomaly & Toxic-Combination Advisor (`ai/Test-EntitlementSoDWithAgent.ps1`)**:
   - Evaluates requested roles against `policies/sod-toxic-combinations.json` and `ai/entitlement-peer-baseline.json`.
   - Computes a peer-distance `AnomalyScore` and `Confidence` metric, optionally enriched by an Azure AI Foundry deployment using strict JSON schema output and prompt-injection isolation (candidate fields are treated strictly as untrusted data).
   - **Abstention Gate**: If confidence falls below `0.75` (for example, an unmapped or executive job code), the advisor emits `ABSTAIN_LOW_CONFIDENCE` and routes the request to a human IAM reviewer rather than guessing.

3. **Administrative Unit Containment & Entitlement Management (`graph/Deploy-LifecycleWorkflowExtension.ps1`)**:
   - Lifecycle Workflows trigger 1 day prior to `employeeHireDate`, invoking the Custom Task Extension before assigning standard departmental Access Packages via `/identityGovernance/entitlementManagement/assignmentRequests`.
   - Newly provisioned identities are placed inside a Restricted Management Administrative Unit (`isMemberManagementRestricted = $true`) so regional IT administrators cannot escalate privileges outside their blast-radius boundary.

## 3. Consequences

- **Positive**: Eliminates silent peer-clone privilege creep, enforces deterministic SoD vetoes, and provides an auditable JSON decision trail for every joiner event.
- **Negative / Trade-offs**: Unmapped job codes and novel role combinations incur a human review step (`ABSTAIN_LOW_CONFIDENCE`), requiring IAM Operations to maintain `ai/entitlement-peer-baseline.json` as new departments onboard.
- **Compliance Alignment**: Supports SOX, ISO 27001 A.9, and NIST AC-5 Segregation of Duties audit evidence via Log Analytics KQL (`queries/Entitlement-SoD-Audit.kql`).
