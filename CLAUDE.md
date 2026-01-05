# Land Registry Compliance Integration Project

## Project Overview

**Project Name:** Insured Land Registry Compliance Automation
**Owner:** Omar Lodhi
**Start Date:** January 2026

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
│                              AZURE                                        │
│  ┌────────────────────┐  ┌────────────────────┐  ┌───────────────────┐  │
│  │  Azure Functions   │  │  Azure Blob        │  │  Azure Logic Apps │  │
│  │  (Durable)         │  │  Storage           │  │                   │  │
│  │                    │  │                    │  │  - Send Email     │  │
│  │  - Process         │  │  - Title Deed      │  │  - Monitor Inbox  │  │
│  │    Individual      │  │    PDFs            │  │  - Notify Karen   │  │
│  │  - Process Batch   │  │                    │  │                   │  │
│  └─────────┬──────────┘  └────────────────────┘  └───────────────────┘  │
│            │                                                              │
│  ┌─────────▼──────────┐                                                  │
│  │  Azure Key Vault   │                                                  │
│  │  - HMLR Certs      │                                                  │
│  │  - SF Credentials  │                                                  │
│  └────────────────────┘                                                  │
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
| Match_Type__c | Picklist | Property+Person Match, Property Only, No Property Match |
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

**Resource Naming Convention:**
- Resource Group: `rg-landreg-poc` → `rg-landreg` (production)
- Function App: `func-landreg-api`
- Storage Account: `stlandregblob`
- Key Vault: `kv-landreg`
- Logic Apps: `logic-landreg-email`, `logic-landreg-inbox`

**Azure Functions (Durable Functions for long-running orchestration):**
| Function | Trigger | Description |
|----------|---------|-------------|
| ProcessIndividualLandlord | HTTP | Calls OOV API, then Official Copy API if needed |
| ProcessCompanyBatch | HTTP | Generates Excel, triggers email send |
| HandleHMLRResponse | Logic App | Parses response Excel, updates SF records |
| StoreDocument | HTTP | Uploads PDF to Blob Storage, returns URL |
| UpdateSalesforce | Activity | Bulk updates SF records |

**Azure Logic Apps:**
| Flow | Purpose |
|------|---------|
| SendToHMLR | Sends email with Excel attachment to HMLR |
| MonitorHMLRInbox | Watches shared mailbox for responses |
| NotifyCompliance | Sends notification email to Karen |

**Azure Blob Storage:**
- Container: `title-deeds`
- Structure: `/{batch-id}/{landlord-id}/{title-number}.pdf`

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

### Shared Mailbox (for HMLR Response Monitoring)
- To be created by IT
- Will receive RPMSG encrypted responses from HMLR
- Must be authorized by HMLR to receive protected emails
- Accessed via Microsoft Graph API

---

## Environment Setup

### Salesforce
- **Sandbox:** OmarDev (`omar.lodhi@tdsgroup.uk.omar`)
- **Org ID:** 00DAe000007km5dMAA

### Azure
- **Development:** Omar's personal Azure subscription (PoC)
- **Production:** TDS Azure subscription (post-validation)
- **Infrastructure as Code:** Bicep/ARM templates for easy migration

---

## Open Items & Dependencies

### Blockers
| Item | Status | Dependency |
|------|--------|------------|
| HMLR BGTest Certificate | Waiting | Simon Devey response |
| Shared Mailbox for HMLR responses | Not started | IT to create |

### Pre-Production Requirements
| Item | Description |
|------|-------------|
| Record Matching Strategy | Define how V+ records map to SF Property__c to prevent duplicate checks |
| Production HMLR Certificate | Request after BGTest validation |
| TDS Azure Migration | Move from personal to TDS subscription |

---

## Project Timeline

| Phase | Tasks | Status |
|-------|-------|--------|
| Discovery | Requirements gathering, architecture design | Complete |
| Certificate Setup | Generate CSR, obtain HMLR certificate | In Progress |
| Salesforce Setup | Custom objects, UI components | Not Started |
| Azure Setup | Resource group, Functions, Logic Apps | Not Started |
| Integration | SF-Azure connectivity, HMLR API integration | Not Started |
| Testing | End-to-end testing with BGTest | Not Started |
| UAT | Testing with Karen Spriggs | Not Started |
| Production | Go-live with production certificate | Not Started |

---

## Contacts

| Name | Role | Email |
|------|------|-------|
| Omar Lodhi | Project Lead | omar.lodhi@tdsgroup.uk |

---

## References

- **Original Project Folder:** `C:\Users\Omar.Lodhi\OneDrive - The Dispute Service\Projects\Land Reg API`
- **HMLR Business Gateway Docs:** https://landregistry.github.io/bgtechdoc/
- **OOV API Docs:** https://landregistry.github.io/bgtechdoc/services/online_owner_verification/
- **Official Copy API Docs:** https://landregistry.github.io/bgtechdoc/services/official_copy_title_known/
