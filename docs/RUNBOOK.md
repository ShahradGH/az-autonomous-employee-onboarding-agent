# Operational Runbook: Autonomous Employee Onboarding: Cross-System Orchestration via Microsoft Graph v2.x (L2 / L3 Triage)

## 1. Scope & Ownership
- **Accountable Owner**: VP of People Operations & Chief Digital Officer
- **Primary Evaluator**: `src/Invoke-ScopedJoinerProvisioning.ps1`
- **Telemetry Source**: `diagnostics/Telemetry-Queries.kql`

## 2. Triage Procedure When Veto Gate Trips
1. Inspect the structured refusal object emitted by `src/Invoke-ScopedJoinerProvisioning.ps1` and correlate the timestamp in Azure Monitor Log Analytics.
2. Do not bypass or disable the pre-flight policy gate without cryptographic dual-signature approval from the VP of People Operations & Chief Digital Officer.
3. Verify remediation locally by running `Invoke-Pester -Path ./tests/Boundary-Verification.Tests.ps1 -Output Detailed`.
