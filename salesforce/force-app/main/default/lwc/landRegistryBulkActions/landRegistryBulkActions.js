import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';

// Apex methods
import bulkFlagForLetter from '@salesforce/apex/LandRegistryCheckController.bulkFlagForLetter';
import bulkCloseRecords from '@salesforce/apex/LandRegistryCheckController.bulkCloseRecords';
import bulkUpdateStatus from '@salesforce/apex/LandRegistryCheckController.bulkUpdateStatus';
import getStatusPicklistValues from '@salesforce/apex/LandRegistryCheckController.getStatusPicklistValues';

export default class LandRegistryBulkActions extends LightningElement {
    // Input properties from Flow
    @api recordIds = [];

    @track selectedAction = '';
    @track selectedStatus = '';
    @track statusOptions = [];
    @track isLoading = true;
    @track isProcessing = false;
    @track showResults = false;
    @track result = null;

    // Action options for radio group
    actionOptions = [
        { label: 'Flag for Letter', value: 'flagForLetter', description: 'Set Needs Letter flag on selected records' },
        { label: 'Close Records', value: 'close', description: 'Set status to Closed on selected records' },
        { label: 'Update Status', value: 'updateStatus', description: 'Change status to a specific value' }
    ];

    @wire(getStatusPicklistValues)
    wiredStatusOptions({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.statusOptions = data.map(opt => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            this.showToast('Error', 'Failed to load status options', 'error');
        }
    }

    // ====== Computed Properties ======

    get recordCount() {
        return this.recordIds?.length || 0;
    }

    get noRecordsSelected() {
        return this.recordCount === 0;
    }

    get showStatusPicker() {
        return this.selectedAction === 'updateStatus';
    }

    get confirmationMessage() {
        switch (this.selectedAction) {
            case 'flagForLetter':
                return `This will flag ${this.recordCount} records for compliance letter. Records already flagged or closed will be skipped.`;
            case 'close':
                return `This will close ${this.recordCount} records. Records already closed will be skipped.`;
            case 'updateStatus':
                if (this.selectedStatus) {
                    return `This will update the status to "${this.selectedStatus}" on ${this.recordCount} records. Records already at this status will be skipped.`;
                }
                return 'Please select a status.';
            default:
                return '';
        }
    }

    get submitButtonLabel() {
        if (this.isProcessing) {
            return 'Processing...';
        }
        switch (this.selectedAction) {
            case 'flagForLetter':
                return 'Flag Records';
            case 'close':
                return 'Close Records';
            case 'updateStatus':
                return 'Update Status';
            default:
                return 'Submit';
        }
    }

    get disableSubmit() {
        if (this.isProcessing) return true;
        if (this.recordCount === 0) return true;
        if (!this.selectedAction) return true;
        if (this.selectedAction === 'updateStatus' && !this.selectedStatus) return true;
        return false;
    }

    get hasErrors() {
        return this.result?.errors?.length > 0;
    }

    // ====== Event Handlers ======

    handleActionChange(event) {
        this.selectedAction = event.detail.value;
        // Clear status selection when switching away from updateStatus
        if (this.selectedAction !== 'updateStatus') {
            this.selectedStatus = '';
        }
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    async handleSubmit() {
        this.isProcessing = true;

        try {
            let result;

            switch (this.selectedAction) {
                case 'flagForLetter':
                    result = await bulkFlagForLetter({ recordIds: this.recordIds });
                    break;
                case 'close':
                    result = await bulkCloseRecords({ recordIds: this.recordIds });
                    break;
                case 'updateStatus':
                    result = await bulkUpdateStatus({
                        recordIds: this.recordIds,
                        newStatus: this.selectedStatus
                    });
                    break;
                default:
                    throw new Error('Invalid action selected');
            }

            this.result = result;
            this.showResults = true;

            // Show toast based on result
            if (result.success) {
                this.showToast('Success', result.message, 'success');
            } else if (result.successCount > 0) {
                this.showToast('Partial Success', result.message, 'warning');
            } else {
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
            this.result = {
                success: false,
                successCount: 0,
                errorCount: this.recordCount,
                skippedCount: 0,
                errors: [this.getErrorMessage(error)],
                message: 'An error occurred while processing records.'
            };
            this.showResults = true;
        } finally {
            this.isProcessing = false;
        }
    }

    handleCancel() {
        // Close the flow/action screen
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleDone() {
        // Close the flow/action screen - list view will auto-refresh
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ====== Helper Methods ======

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}
