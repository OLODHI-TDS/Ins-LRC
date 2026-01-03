/**
 * @description Controller for Land Registry Dashboard component
 * Provides batch status, metrics, and processing controls
 */
public with sharing class LandRegistryDashboardController {

    /**
     * @description Get recent batches with status information
     * @return List of batch records with related metrics
     */
    @AuraEnabled(cacheable=true)
    public static List<BatchWrapper> getRecentBatches() {
        List<BatchWrapper> batches = new List<BatchWrapper>();

        List<Land_Registry_Batch__c> batchRecords = [
            SELECT Id, Name, Upload_Date__c, Status__c, Total_Records__c,
                   Processed_Count__c, Matched_Count__c, Failed_Count__c,
                   Progress_Percent__c, Started_At__c, Completed_At__c,
                   (SELECT Id, Status__c FROM Land_Registry_Checks__r)
            FROM Land_Registry_Batch__c
            ORDER BY Upload_Date__c DESC
            LIMIT 10
        ];

        for (Land_Registry_Batch__c batch : batchRecords) {
            batches.add(new BatchWrapper(batch));
        }

        return batches;
    }

    /**
     * @description Get overall metrics for the dashboard
     * @return Map of metric name to value
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardMetrics() {
        Map<String, Object> metrics = new Map<String, Object>();

        // Total counts
        Integer totalBatches = [SELECT COUNT() FROM Land_Registry_Batch__c];
        Integer totalChecks = [SELECT COUNT() FROM Land_Registry_Check__c];

        // Status counts for checks
        List<AggregateResult> statusCounts = [
            SELECT Status__c, COUNT(Id) cnt
            FROM Land_Registry_Check__c
            GROUP BY Status__c
        ];

        Map<String, Integer> statusMap = new Map<String, Integer>();
        for (AggregateResult ar : statusCounts) {
            statusMap.put((String)ar.get('Status__c'), (Integer)ar.get('cnt'));
        }

        // Counts by type
        Integer individualCount = [SELECT COUNT() FROM Land_Registry_Check__c WHERE Landlord_Type__c = 'Individual'];
        Integer companyCount = [SELECT COUNT() FROM Land_Registry_Check__c WHERE Landlord_Type__c = 'Company'];

        // This week's activity
        Date weekStart = Date.today().toStartOfWeek();
        Integer thisWeekBatches = [
            SELECT COUNT()
            FROM Land_Registry_Batch__c
            WHERE Upload_Date__c >= :weekStart
        ];
        Integer thisWeekChecks = [
            SELECT COUNT()
            FROM Land_Registry_Check__c
            WHERE CreatedDate >= :weekStart
        ];

        // Pending review count
        Integer pendingReview = [
            SELECT COUNT()
            FROM Land_Registry_Check__c
            WHERE Status__c = 'Under Review'
        ];

        // Needs letter count
        Integer needsLetter = [
            SELECT COUNT()
            FROM Land_Registry_Check__c
            WHERE Needs_Letter__c = true AND Status__c != 'Closed'
        ];

        metrics.put('totalBatches', totalBatches);
        metrics.put('totalChecks', totalChecks);
        metrics.put('statusCounts', statusMap);
        metrics.put('individualCount', individualCount);
        metrics.put('companyCount', companyCount);
        metrics.put('thisWeekBatches', thisWeekBatches);
        metrics.put('thisWeekChecks', thisWeekChecks);
        metrics.put('pendingReview', pendingReview);
        metrics.put('needsLetter', needsLetter);

        return metrics;
    }

    /**
     * @description Get a single batch with all check records
     * @param batchId The batch record ID
     * @return Batch with checks
     */
    @AuraEnabled
    public static Land_Registry_Batch__c getBatchWithChecks(Id batchId) {
        return [
            SELECT Id, Name, Upload_Date__c, Status__c, Total_Records__c,
                   Processed_Count__c, Matched_Count__c, Failed_Count__c,
                   Progress_Percent__c, Started_At__c, Completed_At__c, Error_Message__c,
                   (SELECT Id, Name, Landlord_ID__c, Landlord_Name__c, Landlord_Type__c,
                           Property_Address__c, Property_Postcode__c, Status__c,
                           Match_Type__c, Title_Number__c, Title_Deed_URL__c,
                           Needs_Letter__c, HMLR_Response_Date__c
                    FROM Land_Registry_Checks__r
                    ORDER BY Name)
            FROM Land_Registry_Batch__c
            WHERE Id = :batchId
        ];
    }

    /**
     * @description Start processing a batch (triggers Azure function call)
     * @param batchId The batch to process
     * @return Success message or error
     */
    @AuraEnabled
    public static String startBatchProcessing(Id batchId) {
        try {
            Land_Registry_Batch__c batch = [
                SELECT Id, Status__c, Total_Records__c
                FROM Land_Registry_Batch__c
                WHERE Id = :batchId
            ];

            if (batch.Status__c != 'Pending') {
                return 'Batch is not in Pending status. Current status: ' + batch.Status__c;
            }

            // Update batch status to Processing
            batch.Status__c = 'Processing';
            batch.Started_At__c = DateTime.now();
            update batch;

            // Update all check records to Submitted
            List<Land_Registry_Check__c> checks = [
                SELECT Id, Status__c
                FROM Land_Registry_Check__c
                WHERE Batch__c = :batchId AND Status__c = 'Pending'
            ];

            for (Land_Registry_Check__c check : checks) {
                check.Status__c = 'Submitted to HMLR';
            }
            update checks;

            // TODO: Call Azure Function to start processing
            // This will be implemented when Azure integration is ready
            // For now, just update the status

            return 'Processing started for ' + checks.size() + ' records';
        } catch (Exception e) {
            throw new AuraHandledException('Error starting processing: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper class for batch display
     */
    public class BatchWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public DateTime uploadDate;
        @AuraEnabled public String status;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer processedCount;
        @AuraEnabled public Integer matchedCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public String statusClass;
        @AuraEnabled public Map<String, Integer> checkStatusCounts;

        public BatchWrapper(Land_Registry_Batch__c batch) {
            this.id = batch.Id;
            this.name = batch.Name;
            this.uploadDate = batch.Upload_Date__c;
            this.status = batch.Status__c;
            this.totalRecords = batch.Total_Records__c != null ? batch.Total_Records__c.intValue() : 0;
            this.processedCount = batch.Processed_Count__c != null ? batch.Processed_Count__c.intValue() : 0;
            this.matchedCount = batch.Matched_Count__c != null ? batch.Matched_Count__c.intValue() : 0;
            this.failedCount = batch.Failed_Count__c != null ? batch.Failed_Count__c.intValue() : 0;
            this.progressPercent = batch.Progress_Percent__c != null ? batch.Progress_Percent__c : 0;

            // Set status CSS class
            this.statusClass = getStatusClass(batch.Status__c);

            // Count check statuses
            this.checkStatusCounts = new Map<String, Integer>();
            if (batch.Land_Registry_Checks__r != null) {
                for (Land_Registry_Check__c check : batch.Land_Registry_Checks__r) {
                    String checkStatus = check.Status__c;
                    if (!this.checkStatusCounts.containsKey(checkStatus)) {
                        this.checkStatusCounts.put(checkStatus, 0);
                    }
                    this.checkStatusCounts.put(checkStatus, this.checkStatusCounts.get(checkStatus) + 1);
                }
            }
        }

        private String getStatusClass(String status) {
            if (status == 'Complete') return 'slds-theme_success';
            if (status == 'Processing') return 'slds-theme_info';
            if (status == 'Failed') return 'slds-theme_error';
            return 'slds-theme_shade';
        }
    }
}
