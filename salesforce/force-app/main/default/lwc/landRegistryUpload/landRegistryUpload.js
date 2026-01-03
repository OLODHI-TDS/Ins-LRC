import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import parseAndCreateRecords from '@salesforce/apex/LandRegistryCSVParser.parseAndCreateRecords';
import previewCSV from '@salesforce/apex/LandRegistryCSVParser.previewCSV';
import getCSVStats from '@salesforce/apex/LandRegistryCSVParser.getCSVStats';

export default class LandRegistryUpload extends NavigationMixin(LightningElement) {
    @track fileName = '';
    @track csvContent = '';
    @track stats = null;
    @track previewData = null;
    @track uploadResult = null;
    @track error = null;
    @track isUploading = false;
    @track uploadComplete = false;

    get hasFile() {
        return this.csvContent !== '';
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }

        // Validate file type
        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.error = 'Please select a CSV file';
            return;
        }

        this.fileName = file.name;
        this.error = null;

        // Read file content
        const reader = new FileReader();
        reader.onload = () => {
            this.csvContent = reader.result;
            this.loadPreviewAndStats();
        };
        reader.onerror = () => {
            this.error = 'Error reading file';
        };
        reader.readAsText(file);
    }

    async loadPreviewAndStats() {
        try {
            // Load stats and preview in parallel
            const [statsResult, previewResult] = await Promise.all([
                getCSVStats({ csvContent: this.csvContent }),
                previewCSV({ csvContent: this.csvContent })
            ]);

            this.stats = statsResult;
            this.previewData = previewResult.map(row => ({
                ...row,
                badgeClass: row.landlordType === 'Company' ? 'slds-badge_inverse' : ''
            }));

            if (this.stats.total === 0) {
                this.error = 'No valid records found in CSV. Please check the file format.';
            }
        } catch (err) {
            this.error = 'Error parsing CSV: ' + (err.body?.message || err.message);
        }
    }

    async handleUpload() {
        this.isUploading = true;
        this.error = null;

        try {
            const result = await parseAndCreateRecords({ csvContent: this.csvContent });

            if (result.success) {
                this.uploadResult = result;
                this.uploadComplete = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: `Created batch with ${result.totalRecords} records`,
                        variant: 'success'
                    })
                );
            } else {
                this.error = result.errors.join(', ');
            }
        } catch (err) {
            this.error = 'Error creating records: ' + (err.body?.message || err.message);
        } finally {
            this.isUploading = false;
        }
    }

    handleReset() {
        this.fileName = '';
        this.csvContent = '';
        this.stats = null;
        this.previewData = null;
        this.uploadResult = null;
        this.error = null;
        this.isUploading = false;
        this.uploadComplete = false;
    }

    handleViewBatch() {
        if (this.uploadResult?.batchId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.uploadResult.batchId,
                    objectApiName: 'Land_Registry_Batch__c',
                    actionName: 'view'
                }
            });
        }
    }
}
