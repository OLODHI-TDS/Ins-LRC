# Land Registry Integration - Development Plan & Estimates

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Estimated Effort** | 25-35 days |
| **Phases** | 6 |
| **Key Dependencies** | HMLR Certificate, Shared Mailbox |
| **Target Environment** | Salesforce (OmarDev) + Azure (Personal → TDS) |

---

## Phase 1: Salesforce Foundation

**Objective:** Create custom objects, fields, and basic configuration

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| SF-1.1 | Create Land_Registry_Batch__c object | Object with all fields, validation rules, page layout | 0.5 days | Low |
| SF-1.2 | Create Land_Registry_Check__c object | Object with all fields, lookup to Batch, validation rules | 0.5 days | Low |
| SF-1.3 | Configure field history tracking | Enable on Status__c and key fields for audit trail | 0.25 days | Low |
| SF-1.4 | Create list views | All Checks, Pending Review, By Status, By Batch | 0.25 days | Low |
| SF-1.5 | Update Property__c object | Add/verify Land Registry fields, create lookup from Check | 0.25 days | Low |
| SF-1.6 | Create Permission Set | Land Registry Compliance access permissions | 0.25 days | Low |
| SF-1.7 | Create Connected App | For Azure integration (OAuth client credentials) | 0.5 days | Medium |

**Phase 1 Total: 2.5 days**

---

## Phase 2: Salesforce UI Components

**Objective:** Build user interface for CSV upload, dashboard, and review workflow

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| SF-2.1 | CSV Upload LWC | File upload component with validation, preview, confirmation | 2 days | High |
| SF-2.2 | CSV Parser (Apex) | Parse V+ CSV format, detect company vs individual, create records | 1.5 days | Medium |
| SF-2.3 | Company Detection Logic | Keyword matching, name parsing (forename/surname split) | 1 day | Medium |
| SF-2.4 | Batch Dashboard LWC | Progress indicator, status counts, recent batches | 1.5 days | Medium |
| SF-2.5 | Compliance Dashboard | Summary metrics, charts, quick actions | 1 day | Medium |
| SF-2.6 | Record Detail Page | Lightning page with PDF viewer embed, action buttons | 1 day | Medium |
| SF-2.7 | Trigger Processing Button | Custom action to initiate Azure processing | 0.5 days | Low |
| SF-2.8 | Bulk Actions | Select multiple records, bulk status update | 1 day | Medium |

**Phase 2 Total: 9.5 days**

---

## Phase 3: Azure Infrastructure

**Objective:** Set up Azure resources and basic infrastructure

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| AZ-3.1 | Create Resource Group | rg-landreg-poc with tags and RBAC | 0.25 days | Low |
| AZ-3.2 | Create Storage Account | Blob storage for title deeds, containers, access policies | 0.5 days | Low |
| AZ-3.3 | Create Key Vault | Store HMLR certs, SF credentials, connection strings | 0.5 days | Medium |
| AZ-3.4 | Create Function App | Python/Node runtime, consumption plan, app settings | 0.5 days | Medium |
| AZ-3.5 | Configure Managed Identity | Function App identity, Key Vault access policies | 0.25 days | Low |
| AZ-3.6 | Create Logic App (Email Send) | Send email with Excel attachment to HMLR | 1 day | Medium |
| AZ-3.7 | Create Logic App (Inbox Monitor) | Monitor shared mailbox, trigger on new HMLR emails | 1.5 days | High |
| AZ-3.8 | Infrastructure as Code | Bicep templates for reproducible deployment | 1 day | Medium |

**Phase 3 Total: 5.5 days**

---

## Phase 4: Azure Functions Development

**Objective:** Build serverless functions for processing logic

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| AZ-4.1 | Durable Function Orchestrator | Main orchestration for batch processing | 1 day | High |
| AZ-4.2 | HMLR SOAP Client | mTLS authentication, certificate handling | 1.5 days | High |
| AZ-4.3 | OOV API Integration | Call OOV API, parse SOAP response, handle match types | 2 days | High |
| AZ-4.4 | Official Copy API Integration | Request title deeds, handle PDF response | 1.5 days | High |
| AZ-4.5 | Process Individual Activity | End-to-end flow for single individual landlord | 1 day | Medium |
| AZ-4.6 | Process Company Batch | Generate HMLR-format Excel from company records | 1 day | Medium |
| AZ-4.7 | Salesforce API Client | OAuth token management, REST API calls, bulk updates | 1 day | Medium |
| AZ-4.8 | Progress Update Activity | Update Batch progress in Salesforce (every 10 records) | 0.5 days | Low |
| AZ-4.9 | PDF Storage Activity | Upload PDF to Blob Storage, generate SAS URL | 0.5 days | Low |
| AZ-4.10 | HMLR Response Parser | Parse returned Excel, extract match results | 1 day | Medium |
| AZ-4.11 | Error Handling & Retry Logic | Robust error handling, dead-letter queue, alerts | 1 day | Medium |

**Phase 4 Total: 12 days**

---

## Phase 5: Integration & Testing

**Objective:** Connect all components and validate end-to-end flow

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| INT-5.1 | SF to Azure Integration | Apex callouts to Azure Functions, authentication | 1 day | Medium |
| INT-5.2 | Azure to SF Integration | Test Connected App, bulk record updates | 0.5 days | Medium |
| INT-5.3 | HMLR BGTest Validation | Test OOV and Official Copy APIs with real certificate | 1 day | High |
| INT-5.4 | Email Flow Testing | Test automated email send and inbox monitoring | 1 day | Medium |
| INT-5.5 | End-to-End Test (Individuals) | Full flow: Upload → OOV → Official Copy → SF Update | 1 day | High |
| INT-5.6 | End-to-End Test (Companies) | Full flow: Upload → Excel → Email → Response → SF Update | 1 day | High |
| INT-5.7 | Performance Testing | Test with realistic batch sizes (~250 records) | 0.5 days | Medium |
| INT-5.8 | Error Scenario Testing | Network failures, API errors, invalid data | 0.5 days | Medium |

**Phase 5 Total: 6.5 days**

---

## Phase 6: UAT & Documentation

**Objective:** User acceptance testing and handover documentation

### Tasks

| ID | Task | Description | Estimate | Complexity |
|----|------|-------------|----------|------------|
| UAT-6.1 | UAT Test Scripts | Create test scenarios for Karen | 0.5 days | Low |
| UAT-6.2 | UAT Execution | Support Karen through testing, capture feedback | 1 day | Medium |
| UAT-6.3 | Bug Fixes & Refinements | Address UAT feedback | 1.5 days | Medium |
| UAT-6.4 | User Guide | Step-by-step guide for compliance team | 0.5 days | Low |
| UAT-6.5 | Technical Documentation | Architecture, deployment, troubleshooting guide | 0.5 days | Low |

**Phase 6 Total: 4 days**

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
HMLR Certificate ──► Phase 4 (HMLR Integration) ──► Phase 5 (Testing)
                                                          │
Shared Mailbox ──► Phase 3 (Logic App Inbox) ─────────────┘
                                                          │
Phase 1 (SF Objects) ──► Phase 2 (SF UI) ─────────────────┘
```

### Parallel Workstreams

These can be developed in parallel:

| Workstream A | Workstream B |
|--------------|--------------|
| Phase 1: SF Foundation | Phase 3: Azure Infrastructure |
| Phase 2: SF UI Components | Phase 4: Azure Functions (non-HMLR) |

### Blocked Until Certificate Received
- AZ-4.2: HMLR SOAP Client (testing)
- AZ-4.3: OOV API Integration
- AZ-4.4: Official Copy API Integration
- INT-5.3: HMLR BGTest Validation
- INT-5.5: End-to-End Test (Individuals)

**Mitigation:** Build with mock/stub responses, swap for real API when certificate arrives.

---

## Recommended Development Order

### Week 1-2: Foundation (No external dependencies)
- [x] Generate CSR, request certificate
- [ ] SF-1.1 to SF-1.7: Salesforce objects and config
- [ ] AZ-3.1 to AZ-3.5: Azure infrastructure
- [ ] AZ-3.8: Infrastructure as Code

### Week 3-4: Core Development
- [ ] SF-2.1 to SF-2.3: CSV Upload and Parser
- [ ] SF-2.4 to SF-2.5: Dashboards
- [ ] AZ-4.1: Durable Function Orchestrator
- [ ] AZ-4.6: Company Excel Generator
- [ ] AZ-4.7: Salesforce API Client

### Week 5-6: HMLR Integration (Certificate required)
- [ ] AZ-4.2 to AZ-4.4: HMLR API integration
- [ ] AZ-4.5: Individual landlord processing
- [ ] AZ-3.6 to AZ-3.7: Logic Apps (Email)
- [ ] SF-2.6 to SF-2.8: Record detail, actions

### Week 7-8: Integration & Testing
- [ ] INT-5.1 to INT-5.8: All integration testing
- [ ] Bug fixes and refinements

### Week 9-10: UAT & Go-Live Prep
- [ ] UAT-6.1 to UAT-6.5: UAT and documentation
- [ ] Production certificate request
- [ ] TDS Azure migration

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Salesforce UI | Lightning Web Components (LWC) | Modern, performant, standard |
| Salesforce Logic | Apex | Required for callouts, complex logic |
| Azure Functions | Python 3.11 | Good SOAP/XML libraries, familiar |
| Azure Orchestration | Durable Functions | Long-running, stateful workflows |
| Infrastructure | Bicep | Native Azure IaC, simpler than ARM |
| SOAP Client | zeep (Python) | Best Python SOAP library |
| Email | Azure Logic Apps | Built-in O365 connector |
| Storage | Azure Blob Storage | Scalable, cheap, SAS URL support |

---

## Production Deployment Strategy

### Salesforce Production Constraints

**Issue:** Salesforce production has strict login IP restrictions. GitHub Actions runners use dynamic IPs that are not whitelisted.

**Solution:** JWT Bearer Flow via dedicated Connected App

The "Relax IP restrictions" setting is per-Connected App, not org-wide. Creating a dedicated CI/CD Connected App with relaxed IP restrictions does not affect the org's general security.

### CI/CD Pipeline Summary

| Environment | Workflow | Runner | Auth Method |
|-------------|----------|--------|-------------|
| OmarDev (Dev) | `sf-deploy-dev.yml` | `ubuntu-latest` | SFDX Auth URL |
| Production | `sf-deploy-prod.yml` | `ubuntu-latest` | JWT Bearer Flow |

### JWT Bearer Flow Setup (Production)

#### Step 1: Generate Certificate Keypair

```bash
# Generate private key
openssl genrsa -out server.key 2048

# Generate self-signed certificate (valid 1 year)
openssl req -new -x509 -key server.key -out server.crt -days 365 \
  -subj "/C=GB/ST=Hertfordshire/L=Hemel Hempstead/O=The Dispute Service Ltd/CN=GitHub Actions CI"
```

**Files created:**
- `server.key` - Private key (store as GitHub secret)
- `server.crt` - Certificate (upload to Connected App)

#### Step 2: Create Connected App in Salesforce Production

1. **Setup → App Manager → New Connected App**
2. **Basic Information:**
   - Connected App Name: `GitHub Actions Deploy`
   - API Name: `GitHub_Actions_Deploy`
   - Contact Email: `omar.lodhi@tdsgroup.uk`

3. **API (Enable OAuth Settings):**
   - Enable OAuth Settings: ✅
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback`
   - Use digital signatures: ✅ → Upload `server.crt`
   - Selected OAuth Scopes:
     - `api` (Access and manage your data)
     - `refresh_token, offline_access`

4. **Save and wait 2-10 minutes for propagation**

#### Step 3: Configure Connected App Policies

1. **Setup → App Manager → GitHub Actions Deploy → Manage**
2. **OAuth Policies:**
   - Permitted Users: `Admin approved users are pre-authorized`
   - IP Relaxation: `Relax IP restrictions`
3. **Save**

#### Step 4: Assign Permission Set to Integration User

1. Create a Permission Set: `GitHub Actions Integration`
2. Under "Assigned Connected Apps", add `GitHub Actions Deploy`
3. Assign the Permission Set to your deployment user

#### Step 5: Add GitHub Secrets

| Secret Name | Value |
|-------------|-------|
| `SF_PROD_CLIENT_ID` | Consumer Key from Connected App |
| `SF_PROD_USERNAME` | Username of integration user (e.g., `deploy@tdsgroup.uk`) |
| `SF_PROD_SERVER_KEY` | Contents of `server.key` file |
| `SF_PROD_INSTANCE_URL` | `https://login.salesforce.com` |

#### Step 6: Production Workflow Authentication

```yaml
- name: Authenticate to Salesforce (JWT)
  run: |
    echo "${{ secrets.SF_PROD_SERVER_KEY }}" > server.key
    sf org login jwt \
      --client-id ${{ secrets.SF_PROD_CLIENT_ID }} \
      --jwt-key-file server.key \
      --username ${{ secrets.SF_PROD_USERNAME }} \
      --instance-url ${{ secrets.SF_PROD_INSTANCE_URL }} \
      --alias prod \
      --set-default
    rm server.key
```

### Security Notes

- The private key (`server.key`) is stored only in GitHub Secrets
- IP restrictions remain enforced for all other logins
- Only the CI/CD Connected App bypasses IP restrictions
- Certificate can be rotated annually by generating new keypair

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| HMLR certificate delays | Medium | High | Work on non-HMLR components first, use mocks |
| HMLR API undocumented behaviors | Medium | Medium | Build comprehensive error handling, logging |
| RPMSG email decryption issues | Medium | High | Early testing with shared mailbox, fallback to manual |
| V+ data quality issues | Low | Medium | Robust validation in CSV parser |
| Salesforce governor limits | Low | Medium | Batch processing, async patterns |
| Azure Function timeouts | Low | Medium | Durable Functions handles this |
| SF Prod IP restrictions | Confirmed | High | JWT Bearer Flow via dedicated Connected App |

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
