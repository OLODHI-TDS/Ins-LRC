import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRecentBatches from '@salesforce/apex/LandRegistryDashboardController.getRecentBatches';
import getDashboardMetrics from '@salesforce/apex/LandRegistryDashboardController.getDashboardMetrics';
import startBatchProcessing from '@salesforce/apex/LandRegistryDashboardController.startBatchProcessing';
import submitCompanyBatch from '@salesforce/apex/HMLRCompanySubmission.submitCompanyBatch';
import getPendingCompanyCount from '@salesforce/apex/HMLRCompanySubmission.getPendingCompanyCount';

const COLUMNS = [
    {
        label: 'Batch',
        fieldName: 'batchUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    {
        label: 'Upload Date',
        fieldName: 'uploadDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Total', fieldName: 'totalRecords', type: 'number' },
    { label: 'Matched', fieldName: 'matchedCount', type: 'number' },
    { label: 'Failed', fieldName: 'failedCount', type: 'number' },
    {
        label: 'Progress',
        fieldName: 'progressPercent',
        type: 'percent',
        typeAttributes: { maximumFractionDigits: 0 }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View', name: 'view' },
                { label: 'Process Companies Only', name: 'process_companies' },
                { label: 'Start Full Processing', name: 'process' }
            ]
        }
    }
];

export default class LandRegistryDashboard extends NavigationMixin(LightningElement) {
    @track batches = [];
    @track metrics = {
        thisWeekChecks: 0,
        pendingReview: 0,
        needsLetter: 0,
        totalChecks: 0
    };
    @track isLoading = true;
    @track showProcessingModal = false;
    @track showCompanyProcessingModal = false;
    @track selectedBatch = null;
    @track pendingCompanyCount = 0;
    @track isProcessingCompanies = false;

    columns = COLUMNS;
    wiredBatchesResult;
    wiredMetricsResult;

    get hasBatches() {
        return this.batches && this.batches.length > 0;
    }

    get companyProcessButtonLabel() {
        return this.isProcessingCompanies ? 'Processing...' : 'Submit to HMLR';
    }

    @wire(getRecentBatches)
    wiredBatches(result) {
        this.wiredBatchesResult = result;
        if (result.data) {
            this.batches = result.data.map(batch => ({
                ...batch,
                batchUrl: `/lightning/r/Land_Registry_Batch__c/${batch.id}/view`,
                progressPercent: batch.progressPercent / 100 // Convert to decimal for percent type
            }));
            this.isLoading = false;
        } else if (result.error) {
            this.showError('Error loading batches: ' + result.error.body?.message);
            this.isLoading = false;
        }
    }

    @wire(getDashboardMetrics)
    wiredMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) {
            this.metrics = result.data;
        } else if (result.error) {
            console.error('Error loading metrics:', result.error);
        }
    }

    handleNewUpload() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Land_Registry_Upload'
            }
        });
    }

    handleViewPendingReview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Land_Registry_Check__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Pending_Review'
            }
        });
    }

    handleViewNeedsLetter() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Land_Registry_Check__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Needs_Letter'
            }
        });
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view':
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: row.id,
                        objectApiName: 'Land_Registry_Batch__c',
                        actionName: 'view'
                    }
                });
                break;
            case 'process':
                if (row.status === 'Pending') {
                    this.selectedBatch = row;
                    this.showProcessingModal = true;
                } else {
                    this.showError('Only batches in Pending status can be processed');
                }
                break;
            case 'process_companies':
                this.handleProcessCompaniesOnly(row);
                break;
            default:
                break;
        }
    }

    async handleProcessCompaniesOnly(row) {
        // Check if batch has pending company records
        try {
            const count = await getPendingCompanyCount({ batchId: row.id });
            if (count === 0) {
                this.showError('No pending company records found in this batch.');
                return;
            }
            this.selectedBatch = row;
            this.pendingCompanyCount = count;
            this.showCompanyProcessingModal = true;
        } catch (error) {
            this.showError('Error checking company records: ' + (error.body?.message || error.message));
        }
    }

    closeCompanyProcessingModal() {
        this.showCompanyProcessingModal = false;
        this.selectedBatch = null;
        this.pendingCompanyCount = 0;
    }

    async confirmProcessCompanies() {
        if (!this.selectedBatch) return;

        this.isProcessingCompanies = true;
        try {
            const result = await submitCompanyBatch({ batchId: this.selectedBatch.id });

            if (result.success) {
                this.showSuccess(result.message);
            } else {
                this.showError(result.message);
            }

            this.closeCompanyProcessingModal();
            // Refresh the data
            await refreshApex(this.wiredBatchesResult);
            await refreshApex(this.wiredMetricsResult);
        } catch (error) {
            this.showError('Error processing companies: ' + (error.body?.message || error.message));
        } finally {
            this.isProcessingCompanies = false;
        }
    }

    closeProcessingModal() {
        this.showProcessingModal = false;
        this.selectedBatch = null;
    }

    async confirmStartProcessing() {
        if (!this.selectedBatch) return;

        try {
            const result = await startBatchProcessing({ batchId: this.selectedBatch.id });
            this.showSuccess(result);
            this.closeProcessingModal();
            // Refresh the data
            await refreshApex(this.wiredBatchesResult);
            await refreshApex(this.wiredMetricsResult);
        } catch (error) {
            this.showError('Error starting processing: ' + (error.body?.message || error.message));
        }
    }

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: message,
                variant: 'success'
            })
        );
    }

    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error'
            })
        );
    }
}
