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
     * @description Get status distribution for donut chart
     * @return List of chart data points with label, value, and color
     */
    @AuraEnabled(cacheable=true)
    public static List<ChartDataPoint> getStatusDistribution() {
        List<ChartDataPoint> dataPoints = new List<ChartDataPoint>();

        // Color mapping for each status
        Map<String, String> statusColors = new Map<String, String>{
            'Matched' => '#2e844a',
            'Under Review' => '#fe9339',
            'No Match' => '#ea001e',
            'Pending' => '#706e6b',
            'Submitted to HMLR' => '#0176d3',
            'Letter Sent' => '#aa46be',
            'Closed' => '#444444'
        };

        List<AggregateResult> results = [
            SELECT Status__c, COUNT(Id) cnt
            FROM Land_Registry_Check__c
            GROUP BY Status__c
            ORDER BY Status__c
        ];

        for (AggregateResult ar : results) {
            String status = (String)ar.get('Status__c');
            Integer count = (Integer)ar.get('cnt');

            if (status != null && count > 0) {
                ChartDataPoint dp = new ChartDataPoint();
                dp.label = status;
                dp.value = count;
                dp.color = statusColors.containsKey(status) ? statusColors.get(status) : '#706e6b';
                dataPoints.add(dp);
            }
        }

        return dataPoints;
    }

    /**
     * @description Get weekly processing trends for bar chart (last 8 weeks)
     * @return WeeklyTrendData with labels and datasets
     */
    @AuraEnabled(cacheable=true)
    public static WeeklyTrendData getWeeklyTrends() {
        WeeklyTrendData trendData = new WeeklyTrendData();
        trendData.labels = new List<String>();
        trendData.processed = new List<Integer>();
        trendData.matched = new List<Integer>();

        // Calculate date 8 weeks ago
        Date eightWeeksAgo = Date.today().addDays(-56);

        // Query records grouped by week
        List<AggregateResult> results = [
            SELECT WEEK_IN_YEAR(CreatedDate) weekNum,
                   CALENDAR_YEAR(CreatedDate) yr,
                   COUNT(Id) total
            FROM Land_Registry_Check__c
            WHERE CreatedDate >= :eightWeeksAgo
            GROUP BY WEEK_IN_YEAR(CreatedDate), CALENDAR_YEAR(CreatedDate)
            ORDER BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
        ];

        // Query matched records separately
        List<AggregateResult> matchedResults = [
            SELECT WEEK_IN_YEAR(CreatedDate) weekNum,
                   CALENDAR_YEAR(CreatedDate) yr,
                   COUNT(Id) matchedCount
            FROM Land_Registry_Check__c
            WHERE CreatedDate >= :eightWeeksAgo
              AND Status__c = 'Matched'
            GROUP BY WEEK_IN_YEAR(CreatedDate), CALENDAR_YEAR(CreatedDate)
            ORDER BY CALENDAR_YEAR(CreatedDate), WEEK_IN_YEAR(CreatedDate)
        ];

        // Build matched lookup map
        Map<String, Integer> matchedMap = new Map<String, Integer>();
        for (AggregateResult ar : matchedResults) {
            String key = String.valueOf(ar.get('yr')) + '-' + String.valueOf(ar.get('weekNum'));
            matchedMap.put(key, (Integer)ar.get('matchedCount'));
        }

        // Build the trend data
        for (AggregateResult ar : results) {
            Integer weekNum = (Integer)ar.get('weekNum');
            Integer year = (Integer)ar.get('yr');
            Integer total = (Integer)ar.get('total');

            String key = String.valueOf(year) + '-' + String.valueOf(weekNum);
            Integer matched = matchedMap.containsKey(key) ? matchedMap.get(key) : 0;

            trendData.labels.add('Week ' + weekNum);
            trendData.processed.add(total);
            trendData.matched.add(matched);
        }

        // If no data, add placeholder
        if (trendData.labels.isEmpty()) {
            trendData.labels.add('No Data');
            trendData.processed.add(0);
            trendData.matched.add(0);
        }

        return trendData;
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
     * @description Start processing a batch - handles both individual and company records
     * Individual records: Will be processed via HMLR OOV API (pending certificate)
     * Company records: Processed via Azure Function email to HMLR Data Services
     *
     * IMPORTANT: Salesforce requires callouts to happen BEFORE any DML operations.
     * This method is structured to make all HTTP callouts first, then perform DML.
     *
     * @param batchId The batch to process
     * @return ProcessingResult with details of what was processed
     */
    @AuraEnabled
    public static ProcessingResult startBatchProcessing(Id batchId) {
        ProcessingResult result = new ProcessingResult();

        try {
            Land_Registry_Batch__c batch = [
                SELECT Id, Name, Status__c, Total_Records__c
                FROM Land_Registry_Batch__c
                WHERE Id = :batchId
            ];

            if (batch.Status__c != 'Pending') {
                result.success = false;
                result.message = 'Batch is not in Pending status. Current status: ' + batch.Status__c;
                return result;
            }

            // Count pending records by type
            List<Land_Registry_Check__c> pendingIndividuals = [
                SELECT Id FROM Land_Registry_Check__c
                WHERE Batch__c = :batchId
                  AND Landlord_Type__c = 'Individual'
                  AND Status__c = 'Pending'
            ];

            List<Land_Registry_Check__c> pendingCompanies = [
                SELECT Id FROM Land_Registry_Check__c
                WHERE Batch__c = :batchId
                  AND Landlord_Type__c = 'Company'
                  AND Status__c = 'Pending'
            ];

            result.individualCount = pendingIndividuals.size();
            result.companyCount = pendingCompanies.size();

            // ============================================================
            // PHASE 1: CALLOUTS (must happen before any DML)
            // ============================================================

            // Process Company Records via Azure Function (HTTP callout)
            if (!pendingCompanies.isEmpty()) {
                HMLRCompanySubmission.SubmissionResult companyResult =
                    HMLRCompanySubmission.submitCompanyBatch(batchId);

                result.companySubmissionSuccess = companyResult.success;
                result.companySubmissionMessage = companyResult.message;
                result.companiesSubmitted = companyResult.recordsSubmitted != null ?
                    companyResult.recordsSubmitted : 0;
                result.emailMessageId = companyResult.emailMessageId;
            } else {
                result.companySubmissionSuccess = true;
                result.companySubmissionMessage = 'No company records to process.';
                result.companiesSubmitted = 0;
            }

            // Process Individual Records via HMLR OOV API
            // Currently blocked - awaiting HMLR certificate from Simon Devey
            if (!pendingIndividuals.isEmpty()) {
                result.individualSubmissionSuccess = false;
                result.individualSubmissionMessage =
                    'Individual landlord processing is not yet available. ' +
                    'Awaiting HMLR API certificate. ' + pendingIndividuals.size() +
                    ' individual records remain in Pending status.';
                result.individualsSubmitted = 0;
            } else {
                result.individualSubmissionSuccess = true;
                result.individualSubmissionMessage = 'No individual records to process.';
                result.individualsSubmitted = 0;
            }

            // ============================================================
            // PHASE 2: DML (after all callouts complete)
            // ============================================================

            // Determine overall success and update batch status
            Boolean allProcessed = pendingIndividuals.isEmpty() && result.companySubmissionSuccess;

            batch.Started_At__c = DateTime.now();

            if (allProcessed) {
                batch.Status__c = 'Complete';
                batch.Completed_At__c = DateTime.now();
                batch.Processed_Count__c = result.companiesSubmitted;
            } else if (!result.companySubmissionSuccess) {
                batch.Status__c = 'Failed';
                batch.Error_Message__c = result.companySubmissionMessage;
            } else {
                // Partial processing - companies done, individuals pending
                batch.Status__c = 'Partially Processed';
                batch.Processed_Count__c = result.companiesSubmitted;
            }
            update batch;

            // Build result message
            result.success = result.companySubmissionSuccess;
            result.message = buildResultMessage(result);

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'startBatchProcessing error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Build a user-friendly result message
     */
    private static String buildResultMessage(ProcessingResult result) {
        List<String> messages = new List<String>();

        if (result.companiesSubmitted > 0) {
            messages.add(result.companiesSubmitted + ' company records submitted to HMLR via email.');
        } else if (result.companyCount == 0) {
            messages.add('No company records in batch.');
        } else if (!result.companySubmissionSuccess) {
            messages.add('Company submission failed: ' + result.companySubmissionMessage);
        }

        if (result.individualCount > 0) {
            messages.add(result.individualCount + ' individual records pending (API not yet available).');
        } else {
            messages.add('No individual records in batch.');
        }

        return String.join(messages, ' ');
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
            if (status == 'Partially Processed') return 'slds-theme_warning';
            return 'slds-theme_shade';
        }
    }

    /**
     * @description Wrapper class for processing results
     * Provides detailed feedback on both individual and company processing
     */
    public class ProcessingResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;

        // Record counts
        @AuraEnabled public Integer individualCount;
        @AuraEnabled public Integer companyCount;

        // Company submission results
        @AuraEnabled public Boolean companySubmissionSuccess;
        @AuraEnabled public String companySubmissionMessage;
        @AuraEnabled public Integer companiesSubmitted;
        @AuraEnabled public String emailMessageId;

        // Individual submission results
        @AuraEnabled public Boolean individualSubmissionSuccess;
        @AuraEnabled public String individualSubmissionMessage;
        @AuraEnabled public Integer individualsSubmitted;

        public ProcessingResult() {
            this.success = false;
            this.individualCount = 0;
            this.companyCount = 0;
            this.companiesSubmitted = 0;
            this.individualsSubmitted = 0;
        }
    }

    /**
     * @description Data point for chart visualization
     */
    public class ChartDataPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public String color;
    }

    /**
     * @description Weekly trend data for bar chart
     */
    public class WeeklyTrendData {
        @AuraEnabled public List<String> labels;
        @AuraEnabled public List<Integer> processed;
        @AuraEnabled public List<Integer> matched;
    }
}
