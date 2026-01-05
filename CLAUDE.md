# Land Registry Compliance Integration Project

## Project Overview

**Project Name:** Insured Land Registry Compliance Automation
**Owner:** Omar Lodhi
**Stakeholders:** Adrian Delaporte (Head of Compliance), Sanam Khan (Head of England & Wales), Karen Spriggs (Compliance Officer)
**Start Date:** January 2026
**Status:** Company Flow Complete, Individual Flow Awaiting HMLR Certificate

### Business Context

TDS Compliance carries out weekly due diligence checks to verify that landlords protecting deposits are the legitimate owners of the properties. This involves:

1. Extracting insured deposits protected the prior week from V+ (legacy CRM)
2. Sending landlord/property details to HM Land Registry (HMLR) for verification
3. Reviewing responses and title deeds to confirm ownership matches
4. Sending compliance letters to landlords where verification fails

**Current State:** Manual process - Karen emails HMLR weekly, waits 2-3 days, manually reviews responses.

**Target State:** Automated system using HMLR APIs for individuals, automated email for companies, with Salesforce as the processing hub.

---

## Scope

### In Scope
- ALL insured deposits (~1,000/month, ~12,000/year)
- Individual landlords: Automated via HMLR OOV API
- Company landlords: Automated email generation to HMLR Data Services
- Response reconciliation and tracking in Salesforce
- PDF title deed storage in Azure Blob Storage
- Manual review workflow for non-matches

### Out of Scope
- Title number scraping (deemed unethical by management)
- Automated compliance letter generation (flagging only for MVP)
- V+ to Salesforce direct integration (CSV export/upload approach)

---

## Requirements Summary

### Process Flow

| Step | Description |
|------|-------------|
| 1 | Karen exports CSV from V+ (weekly, Mondays) |
| 2 | Uploads CSV to Salesforce dashboard |
| 3 | System auto-detects company vs individual landlords |
| 4 | Karen reviews/adjusts classifications if needed |
| 5 | Karen triggers processing |
| **Individual Landlords** | |
| 6a | Call OOV API with landlord + property details |
| 6b | If Property Found + Person Match → Mark as "Matched" |
| 6c | If Property Found + Person No Match → Get title number → Call Official Copy API → Store PDF → Mark as "Under Review" |
| 6d | If Property Not Found → Mark as "No Match" |
| **Company Landlords** | |
| 7a | Generate Excel with company records (HMLR format) |
| 7b | Auto-email to HMLR Data Services |
| 7c | Monitor inbox for response (2-3 days) |
| 7d | Parse response Excel + store PDFs in Azure Blob |
| 7e | Update SF records based on match results |
| **Review & Close** | |
| 8 | Karen reviews "Under Review" records (views PDFs) |
| 9 | Karen marks as verified or flags for letter |
| 10 | Flagged records handled manually (letter sent) |

### Company Detection Keywords (case-insensitive)
- Limited, LTD, Lettings, Holdings, Property, Assets, Homes, Housing, Residential, Estate, Estates

### Record Statuses
- `Pending` - Uploaded, awaiting processing
- `Submitted to HMLR` - Sent to API or via email
- `Matched` - HMLR confirmed landlord ownership
- `No Match` - No match found, needs review
- `Under Review` - Karen reviewing title deed
- `Letter Sent` - Compliance letter sent to landlord
- `Closed` - Process complete

---

## Architecture

### High-Level Architecture

```
┌─────────────┐                    ┌─────────────────────────────────────┐
│     V+      │                    │            SALESFORCE               │
│   (CRM)     │  CSV Export        │  ┌─────────────────────────────┐   │
│             │ ─────────────────▶ │  │   Upload Interface (LWC)    │   │
└─────────────┘                    │  └──────────────┬──────────────┘   │
                                   │                 │                   │
                                   │  ┌──────────────▼──────────────┐   │
                                   │  │  Land_Registry_Batch__c     │   │
                                   │  │  Land_Registry_Check__c     │   │
                                   │  └──────────────┬──────────────┘   │
                                   │                 │                   │
                                   │  ┌──────────────▼──────────────┐   │
                                   │  │   Dashboard & List Views    │   │
                                   │  └─────────────────────────────┘   │
                                   └───────────────┬─────────────────────┘
                                                   │
                                                   │ Apex HTTP Callout
                                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        AZURE (rg-landreg-poc)                            │
│  ┌────────────────────┐  ┌────────────────────┐  ┌───────────────────┐  │
│  │  func-landreg-api  │  │  stlandregblob     │  │  Azure Comms Svc  │  │
│  │  (Function App)    │  │  (Blob Storage)    │  │  (Email Service)  │  │
│  │                    │  │                    │  │                   │  │
│  │  - Process         │  │  - title-deeds     │  │  - Send Excel to  │  │
│  │    Individual      │  │    container       │  │    HMLR           │  │
│  │  - Send Company    │  │  - PDF storage     │  │                   │  │
│  │    Batch           │  │                    │  │                   │  │
│  └─────────┬──────────┘  └────────────────────┘  └───────────────────┘  │
│            │                                                              │
│  ┌─────────▼──────────┐  ┌────────────────────┐                         │
│  │    kv-landreg      │  │  M365 Service Acct │                         │
│  │   (Key Vault)      │  │  (Email Receive)   │                         │
│  │                    │  │                    │                         │
│  │  - HMLR Certs      │  │  - Graph API       │                         │
│  │  - SF Credentials  │  │  - RPMSG decrypt   │                         │
│  └────────────────────┘  └────────────────────┘                         │
└──────────────────────────────────────────────────────────────────────────┘
                                                   │
                              ┌────────────────────┴────────────────────┐
                              │                                         │
                              ▼                                         ▼
                    ┌─────────────────┐                      ┌─────────────────┐
                    │   HMLR APIs     │                      │   HMLR Email    │
                    │                 │                      │                 │
                    │  - OOV API      │                      │  data.services@ │
                    │  - Official     │                      │  mail.land      │
                    │    Copy API     │                      │  registry.gov.uk│
                    └─────────────────┘                      └─────────────────┘
```

### Salesforce Components

#### Custom Objects

**Land_Registry_Batch__c** (Parent)
| Field | Type | Description |
|-------|------|-------------|
| Name | Auto Number | BATCH-{0000} |
| Upload_Date__c | DateTime | When CSV was uploaded |
| Status__c | Picklist | Pending, Processing, Complete, Failed |
| Total_Records__c | Number | Total records in batch |
| Processed_Count__c | Number | Records processed so far |
| Matched_Count__c | Number | Successful matches |
| Failed_Count__c | Number | Failed/no match |
| Progress_Percent__c | Formula | (Processed_Count / Total_Records) * 100 |
| Started_At__c | DateTime | Processing start time |
| Completed_At__c | DateTime | Processing end time |
| Error_Message__c | Text | If failed, why |

**Land_Registry_Check__c** (Child)
| Field | Type | Description |
|-------|------|-------------|
| Name | Auto Number | LRC-{0000} |
| Batch__c | Lookup | Link to parent batch |
| Landlord_ID__c | Text | V+ Landlord ID (CustomerRef) |
| Landlord_Name__c | Text | Full name from V+ |
| Landlord_Type__c | Picklist | Individual / Company |
| Forename__c | Text | Parsed first name |
| Surname__c | Text | Parsed surname |
| Company_Name__c | Text | Company name (if applicable) |
| Property_Address__c | Text Area | Full property address |
| Property_Postcode__c | Text | Postcode |
| Status__c | Picklist | Pending, Submitted, Matched, No Match, Under Review, Letter Sent, Closed |
| Match_Type__c | Picklist | Property and Person Match, Property Only, No Property Match |
| Title_Number__c | Text | Returned from HMLR |
| Title_Deed_URL__c | URL | Link to PDF in Azure Blob |
| HMLR_Response_Date__c | DateTime | When response received |
| Needs_Letter__c | Checkbox | Flagged for compliance letter |
| Notes__c | Long Text | Karen's review notes |
| Reviewed_By__c | Lookup (User) | Who reviewed |
| Reviewed_Date__c | DateTime | When reviewed |

**Property__c** (Existing - Updated on completion)
| Field | Type | Update |
|-------|------|--------|
| Land_registry_number__c | Text | Populated with title number |
| Land_registry_number_check__c | Checkbox | Set to true when verified |

#### UI Components (MVP)
- **Upload Interface** - CSV upload component (Lightning Web Component)
- **Dashboard** - Status counts, weekly metrics, progress indicator
- **List View** - Filterable by status, date, landlord type

#### UI Components (Nice-to-have)
- **Record Detail Page** - View deed PDF, add notes, action buttons

### Azure Components

**Resource Group:** `rg-landreg-poc` (UK South)

**Deployed Resources:**
| Resource | Name | Type | Status |
|----------|------|------|--------|
| Function App | `func-landreg-api` | .NET 8 Isolated, Consumption Plan | ✅ Created |
| Storage Account | `stlandregblob` | StorageV2, Standard_LRS | ✅ Created |
| Blob Container | `title-deeds` | Private | ✅ Created |
| Key Vault | `kv-landreg` | Standard | ✅ Created |
| Application Insights | `func-landreg-api` | Monitoring | ✅ Created |
| Communication Services | `acs-landreg` | Email sending | ✅ Created |
| Email Service | `email-landreg` | Email domain management | ✅ Created |
| Email Domain | Azure-managed | `ab0150b0-c89e-4a65-829a-d151919c47d9.azurecomm.net` | ✅ Verified |

**Key Vault Secrets:**
| Secret Name | Purpose | Status |
|-------------|---------|--------|
| `sf-consumer-key` | Salesforce OAuth Client ID | ✅ Stored |
| `sf-consumer-secret` | Salesforce OAuth Client Secret | ✅ Stored |
| `sf-login-url` | `https://test.salesforce.com` | ✅ Stored |
| `sf-instance-url` | `https://thedisputeservice--omardev.sandbox.my.salesforce.com` | ✅ Stored |
| `acs-connection-string` | Azure Communication Services connection | ✅ Stored |
| `acs-sender-email` | `DoNotReply@...azurecomm.net` | ✅ Stored |
| `hmlr-certificate` | HMLR mTLS certificate (PFX) | ⏳ Awaiting cert |
| `hmlr-recipient-email` | Email recipient (dev: omar.lodhi@tdsgroup.uk) | ✅ Stored |

**Azure Functions:**
| Function | Trigger | Description | Status |
|----------|---------|-------------|--------|
| `SendCompanyBatchToHMLR` | HTTP | Generates Excel, sends email via ACS | ✅ Deployed & Tested |
| `CheckHMLRInbox` | Timer | Timer-triggered (15 min) inbox polling | ✅ Deployed & Tested |
| `CheckHMLRInboxManual` | HTTP | Manual inbox check for testing | ✅ Deployed & Tested |
| `ProcessHMLRResponse` | HTTP | Parses response Excel, updates SF records | ✅ Deployed & Tested |
| `ProcessHMLRResponseFromBlob` | Blob | Blob-triggered response processing | ✅ Deployed |
| `NotifyComplianceTeam` | HTTP | Send notification emails | ✅ Deployed & Tested |
| `UploadDocument` | HTTP | Upload PDFs to blob storage | ✅ Deployed |
| `GetDocumentUrl` | HTTP | Generate SAS URLs for PDFs | ✅ Deployed |
| `ProcessIndividualLandlord` | HTTP | Calls OOV API, then Official Copy API if needed | ⏳ Blocked by cert |

**Function Endpoints:**
- `SendCompanyBatchToHMLR`: `https://func-landreg-api.azurewebsites.net/api/sendcompanybatchtohmlr`

**Azure Blob Storage:**
- Container: `title-deeds`
- Structure: `/{batch-id}/{landlord-id}/{title-number}.pdf`

**Email Infrastructure:**
- **Sending:** Azure Communication Services ✅ Set up
  - Resource: `acs-landreg`
  - Domain: `ab0150b0-c89e-4a65-829a-d151919c47d9.azurecomm.net`
  - Sender: `DoNotReply@ab0150b0-c89e-4a65-829a-d151919c47d9.azurecomm.net`
- **Receiving:** M365 E1 License (~£5/month) for service account to receive encrypted RPMSG responses from HMLR

### Integration Patterns

**SF → Azure:**
- Apex HTTP callout to Azure Functions (REST API)
- Batch processing with progress updates every 10 records

**Azure → SF:**
- Connected App with OAuth (client credentials flow)
- Azure Functions call SF REST API to update records

### HMLR APIs

**OOV (Online Owner Verification) API**
- Protocol: SOAP over HTTPS
- Authentication: Mutual TLS (mTLS) with client certificate
- Endpoint (Test): `https://bgtest.landregistry.gov.uk`
- Endpoint (Live): `https://businessgateway.landregistry.gov.uk`
- Service Hours: 6:30 AM - 11:00 PM GMT

**Official Copy Title Known API**
- Same authentication as OOV
- Returns PDF title documents

**Email to Data Services (Company Landlords)**
- To: `data.services@mail.landregistry.gov.uk`
- Format: Excel with columns: CustomerRef, Forename, Surname, Company Name Supplied, Input Address 1-5, Input Postcode

---

## Company Landlord Email Implementation

### Overview Flow

```
┌────────────────┐     HTTP POST      ┌─────────────────────┐     Email      ┌──────────────┐
│   Salesforce   │ ─────────────────► │   Azure Function    │ ─────────────► │    HMLR      │
│                │   Company records  │                     │   Excel file   │ Data Services│
│ Karen clicks   │   as JSON          │ • Generate Excel    │                │              │
│ "Send to HMLR" │                    │ • Send via ACS      │                │              │
└────────────────┘                    └─────────────────────┘                └──────────────┘
```

### Implementation Phases

#### Phase 1: Azure Communication Services Setup ✅ Complete
| Step | Task | Status |
|------|------|--------|
| 1.1 | Create ACS resource in Azure | ✅ `acs-landreg` |
| 1.2 | Set up Email Communication Service | ✅ `email-landreg` |
| 1.3 | Configure Azure-managed domain | ✅ `ab0150b0-c89e-4a65-829a-d151919c47d9.azurecomm.net` |
| 1.4 | Store connection string in Key Vault | ✅ `acs-connection-string` |

#### Phase 2: Azure Function - Generate & Send Excel ✅ Complete
| Step | Task | Status |
|------|------|--------|
| 2.1 | Create `SendCompanyBatchToHMLR` HTTP-triggered function | ✅ Deployed |
| 2.2 | Accept JSON payload with company landlord records | ✅ Implemented |
| 2.3 | Generate Excel file in HMLR format using ClosedXML | ✅ Implemented |
| 2.4 | Send email via ACS with Excel attachment | ✅ Tested |
| 2.5 | Return success/failure response to Salesforce | ✅ Implemented |

#### Phase 3: Salesforce Integration ✅ Complete
| Step | Task | Status |
|------|------|--------|
| 3.1 | Create Apex class `HMLRCompanySubmission` | ✅ Deployed |
| 3.2 | Query company records from batch | ✅ Implemented |
| 3.3 | Call Azure Function with JSON payload | ✅ Implemented |
| 3.4 | Update record statuses to "Submitted to HMLR" | ✅ Implemented |
| 3.5 | Add Remote Site Setting | ✅ Deployed |
| 3.6 | Configure Azure Function Key in Custom Setting | ⏳ Manual step |

**Configuration Required:**
After deployment, set up `Land_Registry_Settings__c` custom setting with:
- `Azure_Function_Key__c`: The function key from Azure
- `Azure_Function_URL__c`: `https://func-landreg-api.azurewebsites.net` (optional, has default)

### HMLR Excel Format

| Column | SF Source Field | Notes |
|--------|-----------------|-------|
| CustomerRef | `Landlord_ID__c` | Middle value extracted from V+ compound ID |
| Forename | `Forename__c` | Blank for companies |
| Surname | `Surname__c` | Blank for companies |
| Company Name Supplied | `Company_Name__c` | Full company name |
| Input Address 1 | `Property_Address__c` line 1 | First line of split address |
| Input Address 2 | `Property_Address__c` line 2 | Second line |
| Input Address 3 | `Property_Address__c` line 3 | Third line (usually town) |
| Input Address 4 | `Property_Address__c` line 4 | Fourth line (usually county) |
| Input Address 5 | `Property_Address__c` line 5 | Fifth line (if needed) |
| Input Postcode | `Property_Postcode__c` | Formatted: "SW1A 1AA" |

### JSON Payload (Salesforce → Azure Function)

```json
{
  "batchId": "a0Ae000001ABC123",
  "batchName": "BATCH-0042",
  "records": [
    {
      "recordId": "a1Ae000001XYZ789",
      "customerRef": "15589",
      "companyName": "ABC Properties Ltd",
      "forename": "",
      "surname": "",
      "address1": "45 Business Park",
      "address2": "Manchester",
      "address3": "Greater Manchester",
      "address4": "",
      "address5": "",
      "postcode": "M1 2AB"
    }
  ]
}
```

### Azure Function Response

```json
{
  "success": true,
  "batchId": "a0Ae000001ABC123",
  "recordsProcessed": 15,
  "emailMessageId": "acs-message-id-here",
  "sentAt": "2026-01-04T12:00:00Z"
}
```

### Technology Stack

| Component | Technology |
|-----------|------------|
| Email Service | Azure Communication Services |
| Function Runtime | .NET 8 Isolated |
| Excel Generation | ClosedXML NuGet package |
| Email SDK | Azure.Communication.Email |
| SF Callout | Apex HttpRequest |

---

## Data Mapping

### V+ CSV to Salesforce

| V+ Field | SF Field | Notes |
|----------|----------|-------|
| Landlord ID | Landlord_ID__c | Used as CustomerRef |
| Name | Landlord_Name__c, Forename__c, Surname__c, Company_Name__c | Parsed based on company detection |
| Tenancy First Line | Property_Address__c (line 1) | |
| Tenancy Town | Property_Address__c (line 2) | |
| Tenancy County | Property_Address__c (line 3) | |
| Tenancy Postcode | Property_Postcode__c | |

### Salesforce to HMLR Excel (Company Landlords)

| SF Field | HMLR Column |
|----------|-------------|
| Landlord_ID__c | CustomerRef |
| Forename__c | Forename |
| Surname__c | Surname |
| Company_Name__c | Company Name Supplied |
| Property_Address__c (parsed) | Input Address one - five |
| Property_Postcode__c | Input Postcode |

---

## Security & Certificates

### HMLR Certificate Setup

**Files Location:** `C:\Users\Omar.Lodhi\Projects\Insured Land Reg\certificates\`

| File | Purpose | Status |
|------|---------|--------|
| tds_bgtest_private.key | Private key (NEVER SHARE) | Generated |
| tds_bgtest.csr | Certificate Signing Request | Generated, sent to HMLR |
| LR Root CA 2017.txt | HMLR Root CA | Have |
| LR Issuing CA 2020.txt | HMLR Intermediate CA | Have |
| (pending) | Signed certificate from HMLR | Awaiting response |

**Certificate Request:**
- Reference: Original #1915482 (expired), new request sent 02/01/2026
- Contact: Simon Devey (simon.devey@landregistry.gov.uk)
- Common Name: `The Dispute Service Ltd [BGTest]`

### Email Response Handling (M365 Service Account)

**Approach:** Dedicated M365 E1 licensed service account (not IT-managed shared mailbox)

| Aspect | Details |
|--------|---------|
| License Type | Microsoft 365 E1 (~£5/month) |
| Purpose | Receive RPMSG encrypted responses from HMLR |
| Account Name | TBD (e.g., `landreg-responses@tdsgroup.uk`) |
| Authorization | Must be registered with HMLR to receive protected emails |
| Access Method | Microsoft Graph API from Azure Function |

**Why M365 E1 License:**
- HMLR sends responses as encrypted RPMSG files (Microsoft Rights Management)
- Only M365 licensed accounts can decrypt RPMSG in automated workflows
- Azure Communication Services cannot receive/decrypt RPMSG
- Keeps email handling within project scope (no IT dependency for mailbox creation)

---

## Environment Setup

### Salesforce
| Property | Value |
|----------|-------|
| Sandbox Name | OmarDev |
| Username | `omar.lodhi@tdsgroup.uk.omar` |
| Org ID | `00DAe000007km5dMAA` |
| Instance URL | `https://thedisputeservice--omardev.sandbox.my.salesforce.com` |
| API Version | 59.0 |

**Connected App:**
- Name: `Land Registry Azure Integration`
- OAuth Scopes: `Api`, `RefreshToken`
- Callback URL: `https://func-landreg-api.azurewebsites.net/oauth/callback`

### Azure
| Property | Value |
|----------|-------|
| Subscription | Omar's personal Azure (PoC phase) |
| Resource Group | `rg-landreg-poc` |
| Location | UK South |

**Production Migration:** After BGTest validation, migrate to TDS Azure subscription using ARM/Bicep templates

---

## Open Items & Dependencies

### Blockers
| Item | Status | Dependency | Notes |
|------|--------|------------|-------|
| HMLR BGTest Certificate | Waiting | Simon Devey | CSR sent 02/01/2026, awaiting signed certificate |

### To Procure
| Item | Cost | Purpose | Status |
|------|------|---------|--------|
| M365 E1 License | ~£5/month | Service account for receiving encrypted HMLR responses | ⏳ Pending |
| Azure Communication Services | Pay-as-you-go | Sending Excel files to HMLR | ✅ Set up |

### Pre-Production Requirements
| Item | Description |
|------|-------------|
| Record Matching Strategy | Define how V+ records map to SF Property__c to prevent duplicate checks |
| Production HMLR Certificate | Request after BGTest validation |
| TDS Azure Migration | Move from personal to TDS subscription |
| Register Email with HMLR | Register M365 service account email to receive protected HMLR responses |

---

## Project Timeline

| Phase | Tasks | Status |
|-------|-------|--------|
| Discovery | Requirements gathering, architecture design | ✅ Complete |
| Certificate Setup | Generate CSR, obtain HMLR certificate | ⏳ Awaiting HMLR |
| Salesforce Setup | Custom objects, UI components, CSV parser | ✅ Complete |
| Azure Infrastructure | Resource group, Storage, Key Vault, Function App | ✅ Complete |
| Azure Functions | Company email, Individual API, Response handling | ✅ Complete (Company flow), ⏳ Blocked (Individual) |
| SF-Azure Integration | Connected App, Apex callouts | ✅ Complete |
| Testing | End-to-end testing with BGTest environment | ⏳ Blocked by cert |
| UAT | Testing with Karen Spriggs | ⏳ Not Started |
| Production | Go-live with production certificate | ⏳ Not Started |

### Completed Items (January 2026)
- ✅ CSV parser with UK address splitting and company detection
- ✅ Landlord ID extraction (middle value from compound format)
- ✅ Land Registry Check custom objects and UI components in Salesforce
- ✅ Azure resource group `rg-landreg-poc` (UK South)
- ✅ Azure Storage Account `stlandregblob` with `title-deeds` container
- ✅ Azure Key Vault `kv-landreg` with SF credentials
- ✅ Azure Function App `func-landreg-api` (.NET 8 Isolated)
- ✅ Salesforce Connected App for Azure integration (password OAuth flow)
- ✅ Azure Communication Services `acs-landreg` with email domain configured
- ✅ `SendCompanyBatchToHMLR` Azure Function deployed and tested
- ✅ GitHub Actions CI/CD for Azure Functions (.NET 8 build and deploy)
- ✅ `HMLRCompanySubmission` Apex class for Salesforce → Azure integration
- ✅ `Land_Registry_Settings__c` custom setting for Azure configuration
- ✅ Remote Site Setting for Azure Functions endpoint
- ✅ M365 service account `landreg-responses@TDSLR.onmicrosoft.com` for HMLR response monitoring
- ✅ `CheckHMLRInbox` and `CheckHMLRInboxManual` Azure Functions for inbox polling
- ✅ `ProcessHMLRResponse` Azure Function for parsing HMLR Excel and updating Salesforce
- ✅ RPMSG decryption and Excel/ZIP extraction from encrypted HMLR emails
- ✅ PDF title deed storage in Azure Blob with SAS URL generation
- ✅ End-to-end company landlord flow tested (12 records: 7 Matched, 3 Under Review, 2 No Match)
- ✅ Salesforce record updates from Azure Functions (Status, Match_Type, Title_Number, Title_Deed_URL)

---

## Contacts

| Name | Role | Email |
|------|------|-------|
| Omar Lodhi | Project Lead | omar.lodhi@tdsgroup.uk |
| Adrian Delaporte | Head of Compliance | adrian.delaporte@tdsgroup.uk |
| Karen Spriggs | Compliance Officer | karen.spriggs@tdsgroup.uk |
| Sanam Khan | Head of England & Wales | |
| Simon Devey | HMLR Account Manager | simon.devey@landregistry.gov.uk |
| Daniel/Owen | Liit (MSP) - Infrastructure | |

---

## References

- **Original Project Folder:** `C:\Users\Omar.Lodhi\OneDrive - The Dispute Service\Projects\Land Reg API`
- **HMLR Business Gateway Docs:** https://landregistry.github.io/bgtechdoc/
- **OOV API Docs:** https://landregistry.github.io/bgtechdoc/services/online_owner_verification/
- **Official Copy API Docs:** https://landregistry.github.io/bgtechdoc/services/official_copy_title_known/
