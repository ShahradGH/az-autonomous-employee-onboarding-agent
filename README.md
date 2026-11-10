# Autonomous Employee Onboarding: Cross-System Orchestration via Microsoft Graph v2.x

[![Pester Verification](https://img.shields.io/badge/pester-16%2F16%20passing-brightgreen)](tests/OnboardingSoD.Tests.ps1)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Architecture Deep-Dive](https://img.shields.io/badge/blog-alerasoul.net-0a1128)](https://alerasoul.net/autonomous-cross-system-employee-onboarding/)

> **Primary Governance Artefact:** Cross-System JIT Identity & Access Lifecycle Matrix  
> **Accountable Service Owner:** VP of People Operations & Chief Digital Officer  
> **Full Architectural Deep-Dive:** [https://alerasoul.net/autonomous-cross-system-employee-onboarding/](https://alerasoul.net/autonomous-cross-system-employee-onboarding/)

---

## Repository Layout (14 Files)

```text
├── .github/workflows/ci.yml
├── LICENSE
├── README.md
├── SECURITY.md
├── docs/ADR-001-sod-boundary.md
├── docs/JML-GOVERNANCE-RUNBOOK.md
├── fixtures/candidate-role-requests.json
├── infra/identity-governance.bicep
├── policies/sod-toxic-combinations.json
├── queries/Entitlement-SoD-Audit.kql
├── schemas/workday-hire-event.schema.json
├── src/Invoke-AccessPackageAssignment.ps1
├── src/Invoke-ScopedJoinerProvisioning.ps1
└── tests/OnboardingSoD.Tests.ps1
```

## Quickstart & Offline Verification

```powershell
# 1. Execute the primary PowerShell 7 evaluator
pwsh -NoProfile -File ./src/Invoke-ScopedJoinerProvisioning.ps1

# 2. Run the 16-test Pester verification contract
Invoke-Pester -Path ./tests/OnboardingSoD.Tests.ps1 -Output Detailed
```

## License

Released under the [MIT License](LICENSE). Authored by **Shahrad Alerasoul** ([alerasoul.net](https://alerasoul.net)).
