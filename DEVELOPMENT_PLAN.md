# Land Registry Integration - Development Plan & Estimates

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Estimated Effort** | 25-35 days |
| **Phases** | 6 |
| **Key Dependencies** | HMLR Certificate *(awaiting Security Ops)* |
| **Target Environment** | Salesforce (OmarDev) + Azure (Personal → TDS) |
| **Last Updated** | 5 January 2026 |

### Progress Overview

| Phase | Status | Completion |
|-------|--------|------------|
| Phase 1: Salesforce Foundation | ✅ Complete | 100% |
| Phase 2: Salesforce UI Components | 🟡 In Progress | ~60% |
| Phase 3: Azure Infrastructure | ✅ Complete | 100% |
| Phase 4: Azure Functions Development | 🟡 In Progress | ~50% (blocked on HMLR cert) |
| Phase 5: Integration & Testing | 🟡 In Progress | ~30% |
| Phase 6: UAT & Documentation | ⬜ Not Started | 0% |

---

## Phase 1: Salesforce Foundation ✅

**Objective:** Create custom objects, fields, and basic configuration

**Status:** Complete

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| SF-1.1 | Create Land_Registry_Batch__c object | Object with all fields, validation rules, page layout | 0.5 days | ✅ Done |
| SF-1.2 | Create Land_Registry_Check__c object | Object with all fields, lookup to Batch, validation rules | 0.5 days | ✅ Done |
| SF-1.3 | Configure field history tracking | Enable on Status__c and key fields for audit trail | 0.25 days | ✅ Done |
| SF-1.4 | Create list views | All Checks, Pending Review, By Status, By Batch | 0.25 days | ✅ Done |
| SF-1.5 | Update Property__c object | Add/verify Land Registry fields, create lookup from Check | 0.25 days | ✅ Done |
| SF-1.6 | Create Permission Set | Land Registry Compliance access permissions | 0.25 days | ✅ Done |
| SF-1.7 | Create Connected App | For Azure integration (OAuth client credentials) | 0.5 days | ✅ Done |

**Phase 1 Total: 2.5 days** ✅ Complete

---

## Phase 2: Salesforce UI Components 🟡

**Objective:** Build user interface for CSV upload, dashboard, and review workflow

**Status:** In Progress (~60% complete)

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| SF-2.1 | CSV Upload LWC | File upload component with validation, preview, confirmation | 2 days | ✅ Done |
| SF-2.2 | CSV Parser (Apex) | Parse V+ CSV format, detect company vs individual, create records | 1.5 days | ✅ Done |
| SF-2.3 | Company Detection Logic | Keyword matching, name parsing (forename/surname split) | 1 day | ✅ Done |
| SF-2.4 | Batch Dashboard LWC | Progress indicator, status counts, recent batches | 1.5 days | ✅ Done |
| SF-2.5 | Compliance Dashboard | Summary metrics, charts, quick actions | 1 day | ⬜ Not Started |
| SF-2.6 | Record Detail Page | Lightning page with PDF viewer embed, action buttons | 1 day | ⬜ Not Started |
| SF-2.7 | Trigger Processing Button | Custom action to initiate Azure processing | 0.5 days | ✅ Done |
| SF-2.8 | Bulk Actions | Select multiple records, bulk status update | 1 day | ⬜ Not Started |

**Phase 2 Total: 9.5 days** (5.5 days complete, 4 days remaining)

---

## Phase 3: Azure Infrastructure ✅

**Objective:** Set up Azure resources and basic infrastructure

**Status:** Complete (implemented with Azure Functions + ACS instead of Logic Apps)

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| AZ-3.1 | Create Resource Group | rg-landreg-poc with tags and RBAC | 0.25 days | ✅ Done |
| AZ-3.2 | Create Storage Account | Blob storage for title deeds, containers, access policies | 0.5 days | ✅ Done (`stlandregblob`) |
| AZ-3.3 | Create Key Vault | Store HMLR certs, SF credentials, connection strings | 0.5 days | ✅ Done (`kv-landreg`) |
| AZ-3.4 | Create Function App | .NET 8 Isolated runtime, consumption plan, app settings | 0.5 days | ✅ Done (`func-landreg-api`) |
| AZ-3.5 | Configure Managed Identity | Function App identity, Key Vault access policies | 0.25 days | ✅ Done |
| AZ-3.6 | Email Send Capability | Send email with Excel attachment to HMLR | 1 day | ✅ Done (Azure Communication Services) |
| AZ-3.7 | Inbox Monitor Capability | Monitor mailbox for HMLR responses | 1.5 days | ✅ Done (M365 Graph API + Azure Functions) |
| AZ-3.8 | CI/CD Pipeline | GitHub Actions for automated deployment | 1 day | ✅ Done |

**Phase 3 Total: 5.5 days** ✅ Complete

### Implementation Notes
- Used Azure Communication Services instead of Logic Apps for email sending (more flexible)
- Used M365 service account + Graph API instead of Logic Apps for inbox monitoring
- Set up M365 tenant `TDSLR.onmicrosoft.com` with service account `landreg-responses@TDSLR.onmicrosoft.com`
- GitHub Actions CI/CD deploys on push to `dev` branch

---

## Phase 4: Azure Functions Development 🟡

**Objective:** Build serverless functions for processing logic

**Status:** In Progress (~50% complete - HMLR API functions blocked on certificate)

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| AZ-4.1 | Durable Function Orchestrator | Main orchestration for batch processing | 1 day | ⬜ Deferred (simple pattern working) |
| AZ-4.2 | HMLR SOAP Client | mTLS authentication, certificate handling | 1.5 days | 🔒 Blocked (awaiting cert) |
| AZ-4.3 | OOV API Integration | Call OOV API, parse SOAP response, handle match types | 2 days | 🔒 Blocked (awaiting cert) |
| AZ-4.4 | Official Copy API Integration | Request title deeds, handle PDF response | 1.5 days | 🔒 Blocked (awaiting cert) |
| AZ-4.5 | Process Individual Activity | End-to-end flow for single individual landlord | 1 day | 🔒 Blocked (awaiting cert) |
| AZ-4.6 | Process Company Batch | Generate HMLR-format Excel from company records | 1 day | ✅ Done (`SendCompanyBatchToHMLR`) |
| AZ-4.7 | Salesforce API Client | OAuth token management, REST API calls, bulk updates | 1 day | ✅ Done (Apex `HMLRCompanySubmission`) |
| AZ-4.8 | Progress Update Activity | Update Batch progress in Salesforce (every 10 records) | 0.5 days | ⬜ Not Started |
| AZ-4.9 | PDF Storage Activity | Upload PDF to Blob Storage, generate SAS URL | 0.5 days | ✅ Done (`DocumentStorage` functions) |
| AZ-4.10 | HMLR Response Parser | Parse returned Excel, extract match results | 1 day | ✅ Done (`ProcessHMLRResponse`) |
| AZ-4.11 | Error Handling & Retry Logic | Robust error handling, dead-letter queue, alerts | 1 day | 🟡 Partial |

**Phase 4 Total: 12 days** (4.5 days complete, 2.5 days in progress, 5 days blocked)

### Deployed Azure Functions

| Function | Purpose | Status |
|----------|---------|--------|
| `SendCompanyBatchToHMLR` | Generate Excel, send to HMLR via email | ✅ Deployed & Tested |
| `CheckHMLRInbox` | Timer-triggered (15 min) inbox polling | ✅ Deployed & Tested |
| `CheckHMLRInboxManual` | Manual inbox check for testing | ✅ Deployed & Tested |
| `ProcessHMLRResponse` | Parse Excel, extract PDFs, update Salesforce | ✅ Deployed |
| `ProcessHMLRResponseFromBlob` | Blob-triggered response processing | ✅ Deployed |
| `NotifyComplianceTeam` | Send notification emails | ✅ Deployed & Tested |
| `NotifyComplianceTeamFromBlob` | Blob-triggered notifications | ✅ Deployed |
| `UploadDocument` | Upload PDFs to blob storage | ✅ Deployed |
| `GetDocumentUrl` | Generate SAS URLs for PDFs | ✅ Deployed |
| `ListDocuments` | List documents for a record | ✅ Deployed |
| `DeleteDocument` | Delete documents from blob | ✅ Deployed |

---

## Phase 5: Integration & Testing 🟡

**Objective:** Connect all components and validate end-to-end flow

**Status:** In Progress (~30% complete)

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| INT-5.1 | SF to Azure Integration | Apex callouts to Azure Functions, authentication | 1 day | ✅ Done |
| INT-5.2 | Azure to SF Integration | Test Connected App, bulk record updates | 0.5 days | 🟡 Partial (company flow only) |
| INT-5.3 | HMLR BGTest Validation | Test OOV and Official Copy APIs with real certificate | 1 day | 🔒 Blocked (awaiting cert) |
| INT-5.4 | Email Flow Testing | Test automated email send and inbox monitoring | 1 day | ✅ Done |
| INT-5.5 | End-to-End Test (Individuals) | Full flow: Upload → OOV → Official Copy → SF Update | 1 day | 🔒 Blocked (awaiting cert) |
| INT-5.6 | End-to-End Test (Companies) | Full flow: Upload → Excel → Email → Response → SF Update | 1 day | 🟡 Partial (outbound works, response pending real data) |
| INT-5.7 | Performance Testing | Test with realistic batch sizes (~250 records) | 0.5 days | ⬜ Not Started |
| INT-5.8 | Error Scenario Testing | Network failures, API errors, invalid data | 0.5 days | ⬜ Not Started |

**Phase 5 Total: 6.5 days** (2 days complete, 1.5 days partial, 3 days blocked)

---

## Phase 6: UAT & Documentation ⬜

**Objective:** User acceptance testing and handover documentation

**Status:** Not Started (waiting for HMLR certificate to enable full testing)

### Tasks

| ID | Task | Description | Estimate | Status |
|----|------|-------------|----------|--------|
| UAT-6.1 | UAT Test Scripts | Create test scenarios for Karen | 0.5 days | ⬜ Not Started |
| UAT-6.2 | UAT Execution | Support Karen through testing, capture feedback | 1 day | ⬜ Not Started |
| UAT-6.3 | Bug Fixes & Refinements | Address UAT feedback | 1.5 days | ⬜ Not Started |
| UAT-6.4 | User Guide | Step-by-step guide for compliance team | 0.5 days | ⬜ Not Started |
| UAT-6.5 | Technical Documentation | Architecture, deployment, troubleshooting guide | 0.5 days | ⬜ Not Started |

**Phase 6 Total: 4 days** (0 days complete)

---

## Effort Summary

| Phase | Description | Estimate (Days) |
|-------|-------------|-----------------|
| Phase 1 | Salesforce Foundation | 2.5 |
| Phase 2 | Salesforce UI Components | 9.5 |
| Phase 3 | Azure Infrastructure | 5.5 |
| Phase 4 | Azure Functions Development | 12 |
| Phase 5 | Integration & Testing | 6.5 |
| Phase 6 | UAT & Documentation | 4 |
| **TOTAL** | | **40 days** |

### Contingency & Risk Buffer

| Factor | Adjustment |
|--------|------------|
| HMLR API complexity/undocumented behaviors | +3 days |
| Certificate/authentication issues | +2 days |
| Salesforce platform quirks | +1 day |
| Scope changes/refinements | +2 days |
| **Risk Buffer** | **+8 days** |

### Final Estimate

| Scenario | Days | Working Weeks |
|----------|------|---------------|
| **Optimistic** | 32 days | ~6.5 weeks |
| **Realistic** | 40 days | ~8 weeks |
| **Pessimistic** | 48 days | ~10 weeks |

---

## Dependencies & Blockers

### Critical Path Dependencies

```
HMLR Certificate ──► Phase 4 (HMLR Integration) ──► Phase 5 (Testing) ──► Phase 6 (UAT)
       🔒                      🔒                          🟡
```

### Resolved Dependencies ✅

| Dependency | Resolution |
|------------|------------|
| Shared Mailbox | ✅ M365 service account `landreg-responses@TDSLR.onmicrosoft.com` |
| SF Objects | ✅ Land_Registry_Batch__c and Land_Registry_Check__c deployed |
| Azure Infrastructure | ✅ All resources deployed (func-landreg-api, stlandregblob, kv-landreg) |
| Email Send Capability | ✅ Azure Communication Services configured |
| Inbox Monitoring | ✅ Graph API + Azure Functions deployed |

### Remaining Blocker 🔒

**HMLR BGTest Certificate**
- Status: CSR submitted, awaiting Security Operations contact
- Reference: #2582266
- Expected: Within 10 working days from 2 January 2026
- Contact: Sheena Orchin (Security Operations)

### Blocked Until Certificate Received
- AZ-4.2: HMLR SOAP Client (testing)
- AZ-4.3: OOV API Integration
- AZ-4.4: Official Copy API Integration
- AZ-4.5: Process Individual Activity
- INT-5.3: HMLR BGTest Validation
- INT-5.5: End-to-End Test (Individuals)

**Mitigation:** Company landlord flow is fully built and ready to test with real HMLR responses.

---

## Recommended Development Order

### Week 1-2: Foundation (No external dependencies) ✅ COMPLETE
- [x] Generate CSR, request certificate
- [x] SF-1.1 to SF-1.7: Salesforce objects and config
- [x] AZ-3.1 to AZ-3.5: Azure infrastructure
- [x] AZ-3.8: CI/CD Pipeline (GitHub Actions)

### Week 3-4: Core Development ✅ COMPLETE
- [x] SF-2.1 to SF-2.3: CSV Upload and Parser
- [x] SF-2.4: Batch Dashboard LWC
- [x] AZ-4.6: Company Excel Generator (`SendCompanyBatchToHMLR`)
- [x] AZ-4.7: Salesforce API Client (`HMLRCompanySubmission`)
- [x] AZ-3.6 to AZ-3.7: Email send (ACS) and inbox monitoring (Graph API)
- [x] AZ-4.9: PDF Storage (`DocumentStorage` functions)
- [x] AZ-4.10: HMLR Response Parser (`ProcessHMLRResponse`)

### Week 5-6: HMLR Integration (Certificate required) 🔒 BLOCKED
- [ ] AZ-4.2 to AZ-4.4: HMLR API integration
- [ ] AZ-4.5: Individual landlord processing
- [ ] SF-2.6 to SF-2.8: Record detail, actions

### Week 7-8: Integration & Testing 🟡 IN PROGRESS
- [x] INT-5.1: SF to Azure Integration
- [x] INT-5.4: Email Flow Testing
- [ ] INT-5.2 to INT-5.8: Remaining integration testing
- [ ] Bug fixes and refinements

### Week 9-10: UAT & Go-Live Prep ⬜ NOT STARTED
- [ ] UAT-6.1 to UAT-6.5: UAT and documentation
- [ ] Production certificate request
- [ ] TDS Azure migration

---

## Technology Stack

| Component | Technology | Status |
|-----------|------------|--------|
| Salesforce UI | Lightning Web Components (LWC) | ✅ Implemented |
| Salesforce Logic | Apex | ✅ Implemented |
| Azure Functions | .NET 8 Isolated | ✅ Implemented |
| Email Sending | Azure Communication Services | ✅ Implemented |
| Email Receiving | Microsoft Graph API + M365 | ✅ Implemented |
| Excel Generation | ClosedXML (.NET) | ✅ Implemented |
| Storage | Azure Blob Storage | ✅ Implemented |
| Secrets | Azure Key Vault | ✅ Implemented |
| CI/CD | GitHub Actions | ✅ Implemented |
| SOAP Client (HMLR) | TBD (.NET) | ⬜ Pending certificate |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation | Status |
|------|------------|--------|------------|--------|
| HMLR certificate delays | Medium | High | Work on non-HMLR components first, use mocks | 🟡 Active - awaiting Security Ops |
| HMLR API undocumented behaviors | Medium | Medium | Build comprehensive error handling, logging | ⬜ TBD when cert arrives |
| RPMSG email decryption issues | Medium | High | M365 service account can decrypt; fallback to manual | ✅ Mitigated |
| V+ data quality issues | Low | Medium | Robust validation in CSV parser | ✅ Mitigated |
| Salesforce governor limits | Low | Medium | Batch processing, async patterns | ✅ Mitigated |
| Azure Function timeouts | Low | Medium | Simple patterns working, Durable available if needed | ✅ Mitigated |

---

## Assumptions

1. Karen's workflow doesn't change significantly during development
2. V+ CSV export format remains stable
3. HMLR APIs work as documented
4. Shared mailbox can be configured to receive HMLR protected emails
5. Azure consumption plan is sufficient (no need for premium)
6. No significant Salesforce customizations conflict with our objects

---

## Out of Scope (Future Phases)

| Item | Description | Potential Phase |
|------|-------------|-----------------|
| Automated letter generation | Generate compliance letters from SF | Phase 2 |
| V+ direct integration | API/database connection instead of CSV | Phase 2 |
| Historical data migration | Import past compliance checks | Phase 2 |
| Reporting & Analytics | Power BI / Tableau dashboards | Phase 2 |
| Mobile access | Salesforce mobile optimization | Phase 2 |
