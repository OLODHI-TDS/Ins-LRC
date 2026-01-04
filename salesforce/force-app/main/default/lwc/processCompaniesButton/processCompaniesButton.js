import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import submitCompanyBatch from '@salesforce/apex/HMLRCompanySubmission.submitCompanyBatch';
import getPendingCompanyCount from '@salesforce/apex/HMLRCompanySubmission.getPendingCompanyCount';

export default class ProcessCompaniesButton extends LightningElement {
    @api recordId;
    @track showModal = false;
    @track pendingCount = 0;
    @track isProcessing = false;
    @track isLoading = false;

    get buttonLabel() {
        return this.isProcessing ? 'Processing...' : 'Process Companies Only';
    }

    get submitButtonLabel() {
        return this.isProcessing ? 'Submitting...' : 'Submit to HMLR';
    }

    async handleClick() {
        this.isLoading = true;
        try {
            const count = await getPendingCompanyCount({ batchId: this.recordId });
            if (count === 0) {
                this.showToast('No Company Records', 'No pending company records found in this batch.', 'warning');
                return;
            }
            this.pendingCount = count;
            this.showModal = true;
        } catch (error) {
            this.showToast('Error', 'Error checking company records: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeModal() {
        this.showModal = false;
    }

    async handleSubmit() {
        this.isProcessing = true;
        try {
            const result = await submitCompanyBatch({ batchId: this.recordId });

            if (result.success) {
                this.showToast('Success', result.message, 'success');
                // Dispatch event to refresh the page
                this.dispatchEvent(new CustomEvent('recordchange'));
            } else {
                this.showToast('Error', result.message, 'error');
            }

            this.closeModal();
        } catch (error) {
            this.showToast('Error', 'Error processing companies: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isProcessing = false;
        }
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
