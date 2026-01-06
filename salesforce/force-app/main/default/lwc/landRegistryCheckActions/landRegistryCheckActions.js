import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

// Apex methods
import getCheckRecord from '@salesforce/apex/LandRegistryCheckController.getCheckRecord';
import markAsVerified from '@salesforce/apex/LandRegistryCheckController.markAsVerified';
import flagForLetter from '@salesforce/apex/LandRegistryCheckController.flagForLetter';
import closeRecord from '@salesforce/apex/LandRegistryCheckController.closeRecord';
import updateNotes from '@salesforce/apex/LandRegistryCheckController.updateNotes';

export default class LandRegistryCheckActions extends LightningElement {
    @api recordId;

    @track recordData;
    @track showPdfModal = false;
    @track showNotesModal = false;
    @track notesValue = '';
    @track isProcessing = false;
    @track isSavingNotes = false;
    @track isLoading = true;

    connectedCallback() {
        this.loadRecordData();
    }

    async loadRecordData() {
        this.isLoading = true;
        try {
            this.recordData = await getCheckRecord({ recordId: this.recordId });
            this.notesValue = this.recordData?.notes || '';
        } catch (error) {
            this.showToast('Error', 'Failed to load record data: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ====== Computed Properties ======

    get hasTitleDeed() {
        return this.recordData?.hasTitleDeed;
    }

    get disableMarkVerified() {
        return !this.recordData?.canMarkVerified || this.isProcessing;
    }

    get disableClose() {
        return !this.recordData?.canClose || this.isProcessing;
    }

    get disableFlagForLetter() {
        return !this.recordData?.canFlagForLetter || this.isProcessing;
    }

    get markVerifiedLabel() {
        return this.isProcessing ? 'Processing...' : 'Mark Verified';
    }

    get flagForLetterLabel() {
        if (this.recordData?.needsLetter) {
            return 'Already Flagged';
        }
        return this.isProcessing ? 'Processing...' : 'Flag for Letter';
    }

    get closeRecordLabel() {
        return this.isProcessing ? 'Processing...' : 'Close Record';
    }

    get saveNotesLabel() {
        return this.isSavingNotes ? 'Saving...' : 'Save Notes';
    }

    // ====== Action Handlers ======

    async handleMarkVerified() {
        this.isProcessing = true;
        try {
            await markAsVerified({ recordId: this.recordId });
            this.showToast('Success', 'Record marked as verified', 'success');
            await this.refreshRecord();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleFlagForLetter() {
        this.isProcessing = true;
        try {
            await flagForLetter({ recordId: this.recordId });
            this.showToast('Success', 'Record flagged for compliance letter', 'success');
            await this.refreshRecord();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleCloseRecord() {
        this.isProcessing = true;
        try {
            await closeRecord({ recordId: this.recordId });
            this.showToast('Success', 'Record closed', 'success');
            await this.refreshRecord();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ====== PDF Modal Handlers ======

    handleViewPdf() {
        this.showPdfModal = true;
    }

    closePdfModal() {
        this.showPdfModal = false;
    }

    handleOpenInNewTab() {
        if (this.recordData?.titleDeedUrl) {
            window.open(this.recordData.titleDeedUrl, '_blank');
        }
    }

    // ====== Notes Modal Handlers ======

    handleOpenNotesModal() {
        this.notesValue = this.recordData?.notes || '';
        this.showNotesModal = true;
    }

    closeNotesModal() {
        this.showNotesModal = false;
    }

    handleNotesChange(event) {
        this.notesValue = event.target.value;
    }

    async handleSaveNotes() {
        this.isSavingNotes = true;
        try {
            await updateNotes({ recordId: this.recordId, notes: this.notesValue });
            this.showToast('Success', 'Notes saved successfully', 'success');
            this.closeNotesModal();
            await this.refreshRecord();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSavingNotes = false;
        }
    }

    // ====== Helper Methods ======

    async refreshRecord() {
        // Reload the record data
        await this.loadRecordData();
        // Notify the platform to refresh the record page
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    }

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
