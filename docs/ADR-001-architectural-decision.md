# ADR-001: Autonomous Employee Onboarding: Cross-System Orchestration via Microsoft Graph v2.x

## Status
Accepted

## Service Owner & Sign-Off Authority
VP of People Operations & Chief Digital Officer

## Dominant Artefact
Cross-System JIT Identity & Access Lifecycle Matrix

## Decision & Refusal Boundary
All production state mutations must pass deterministic pre-flight policy evaluation in `src/Invoke-ScopedJoinerProvisioning.ps1` and satisfy the 16-test Pester verification contract in `tests/Boundary-Verification.Tests.ps1` before execution.
