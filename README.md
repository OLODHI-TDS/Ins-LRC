# Insured Land Registry Compliance (Ins-LRC)

Automated compliance verification system integrating TDS with HM Land Registry APIs.

## Overview

This system automates the weekly landlord ownership verification process for The Dispute Service (TDS) Compliance team.

**Key Features:**
- CSV upload from V+ (legacy CRM) into Salesforce
- Automatic landlord classification (Individual vs Company)
- HMLR API integration for individual landlord verification
- Automated email generation for company landlord verification
- Response reconciliation and tracking
- Title deed PDF storage and review workflow

## Architecture

- **Salesforce** - User interface, workflow, data storage
- **Azure Functions** - HMLR API integration, processing logic
- **Azure Logic Apps** - Email automation, inbox monitoring
- **Azure Blob Storage** - Title deed PDF storage

## Repository Structure

```
├── .github/workflows/     # CI/CD pipelines
├── salesforce/            # Salesforce metadata (sfdx format)
│   └── force-app/
├── azure/
│   ├── functions/         # Azure Functions code
│   ├── logic-apps/        # Logic App definitions
│   └── infrastructure/    # Bicep IaC templates
├── docs/                  # Documentation
├── CLAUDE.md              # Project knowledge base
└── README.md
```

## Branches

| Branch | Purpose | Deploys To |
|--------|---------|------------|
| `main` | Production-ready | TDS Production |
| `dev` | Integration/testing | OmarDev Sandbox |
| `feature/*` | Active development | Local only |

## Getting Started

### Prerequisites

- Salesforce CLI (`sf`)
- Azure CLI (`az`)
- Node.js 18+ or Python 3.11+
- Git

### Salesforce Setup

```bash
# Authenticate to sandbox
sf org login web --alias omardev --instance-url https://test.salesforce.com

# Deploy metadata
sf project deploy start --source-dir salesforce/force-app --target-org omardev
```

### Azure Setup

```bash
# Login to Azure
az login

# Deploy infrastructure
az deployment group create \
  --resource-group rg-landreg-poc \
  --template-file azure/infrastructure/main.bicep
```

## Documentation

- [CLAUDE.md](CLAUDE.md) - Full project context and architecture
- [Development Plan](docs/DEVELOPMENT_PLAN.md) - Tasks and estimates

## Contacts

- **Project Lead:** Omar Lodhi
- **Compliance:** Adrian Delaporte, Karen Spriggs
- **HMLR Contact:** Simon Devey
