/**
 * @description Handler class for rolling up Land_Registry_Check__c counts to parent batch
 * Updates Matched_Count__c, Failed_Count__c, Processed_Count__c, and Status__c on Land_Registry_Batch__c
 *
 * Batch Status Logic:
 * - Pending: All checks are in "Pending" status
 * - Processing: At least one check is "Submitted to HMLR", no results received yet
 * - Partially Processed: Some checks have results, but others are still Pending/Submitted
 * - Complete: All checks have terminal statuses (Matched, No Match, Under Review, Letter Sent, Closed)
 * - Failed: Technical error occurred (set by processing code, not overridden by trigger)
 */
public with sharing class LandRegistryBatchRollupHandler {

    // Terminal statuses - check has received a result from HMLR
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Matched', 'No Match', 'Under Review', 'Letter Sent', 'Closed'
    };

    // In-progress statuses - check is awaiting processing or results
    private static final Set<String> IN_PROGRESS_STATUSES = new Set<String>{
        'Pending', 'Submitted to HMLR'
    };

    /**
     * @description Recalculates batch counts when check records are inserted, updated, or deleted
     * @param checkRecords The check records being processed
     * @param oldMap The old values (for update/delete operations)
     */
    public static void updateBatchCounts(List<Land_Registry_Check__c> checkRecords, Map<Id, Land_Registry_Check__c> oldMap) {
        // Collect all batch IDs that need recalculation
        Set<Id> batchIds = new Set<Id>();

        for (Land_Registry_Check__c check : checkRecords) {
            if (check.Batch__c != null) {
                batchIds.add(check.Batch__c);
            }
            // Also include old batch ID if it changed (reparenting)
            if (oldMap != null && oldMap.containsKey(check.Id)) {
                Land_Registry_Check__c oldCheck = oldMap.get(check.Id);
                if (oldCheck.Batch__c != null && oldCheck.Batch__c != check.Batch__c) {
                    batchIds.add(oldCheck.Batch__c);
                }
            }
        }

        // Also handle deleted records
        if (oldMap != null && checkRecords.isEmpty()) {
            for (Land_Registry_Check__c oldCheck : oldMap.values()) {
                if (oldCheck.Batch__c != null) {
                    batchIds.add(oldCheck.Batch__c);
                }
            }
        }

        if (batchIds.isEmpty()) {
            return;
        }

        recalculateBatchCounts(batchIds);
    }

    /**
     * @description Recalculates counts for the specified batches
     * @param batchIds Set of batch IDs to recalculate
     */
    public static void recalculateBatchCounts(Set<Id> batchIds) {
        // Query aggregate counts for each batch
        List<AggregateResult> statusCounts = [
            SELECT Batch__c, Status__c, COUNT(Id) cnt
            FROM Land_Registry_Check__c
            WHERE Batch__c IN :batchIds
            GROUP BY Batch__c, Status__c
        ];

        // Build a map of batch ID to status counts
        Map<Id, Map<String, Integer>> batchStatusMap = new Map<Id, Map<String, Integer>>();
        for (Id batchId : batchIds) {
            batchStatusMap.put(batchId, new Map<String, Integer>());
        }

        for (AggregateResult ar : statusCounts) {
            Id batchId = (Id)ar.get('Batch__c');
            String status = (String)ar.get('Status__c');
            Integer count = (Integer)ar.get('cnt');

            if (batchStatusMap.containsKey(batchId)) {
                batchStatusMap.get(batchId).put(status, count);
            }
        }

        // Query existing batches
        List<Land_Registry_Batch__c> batchesToUpdate = [
            SELECT Id, Status__c, Matched_Count__c, Failed_Count__c, Processed_Count__c,
                   Started_At__c, Completed_At__c
            FROM Land_Registry_Batch__c
            WHERE Id IN :batchIds
        ];

        // Calculate and set counts and status
        for (Land_Registry_Batch__c batch : batchesToUpdate) {
            Map<String, Integer> statusMap = batchStatusMap.get(batch.Id);

            Integer matchedCount = 0;
            Integer failedCount = 0;
            Integer processedCount = 0;
            Integer pendingCount = 0;
            Integer submittedCount = 0;
            Integer terminalCount = 0;
            Integer totalCount = 0;
            Integer closedCount = 0;

            if (statusMap != null) {
                // Matched = Status is 'Matched'
                matchedCount = statusMap.containsKey('Matched') ? statusMap.get('Matched') : 0;

                // No Match count
                failedCount = statusMap.containsKey('No Match') ? statusMap.get('No Match') : 0;

                // Calculate counts by category
                for (String status : statusMap.keySet()) {
                    Integer count = statusMap.get(status);
                    totalCount += count;

                    if (status == 'Pending') {
                        pendingCount += count;
                    } else if (status == 'Submitted to HMLR') {
                        submittedCount += count;
                        processedCount += count;
                    } else if (TERMINAL_STATUSES.contains(status)) {
                        terminalCount += count;
                        processedCount += count;
                        if (status == 'Closed') {
                            closedCount += count;
                        }
                    }
                }
            }

            batch.Matched_Count__c = matchedCount;
            batch.Failed_Count__c = failedCount;
            batch.Processed_Count__c = processedCount;

            // Calculate batch status (don't override Failed status set by error handling)
            if (batch.Status__c != 'Failed') {
                batch.Status__c = calculateBatchStatus(totalCount, pendingCount, submittedCount, terminalCount);
            }

            // Set Started_At__c when first record is submitted (only if not already set)
            if (batch.Started_At__c == null && (submittedCount > 0 || terminalCount > 0)) {
                batch.Started_At__c = DateTime.now();
            }

            // Set Completed_At__c when all records are Closed
            if (totalCount > 0 && closedCount == totalCount) {
                if (batch.Completed_At__c == null) {
                    batch.Completed_At__c = DateTime.now();
                }
            } else {
                // Clear Completed_At__c if not all records are Closed (in case of undelete/status change)
                batch.Completed_At__c = null;
            }
        }

        if (!batchesToUpdate.isEmpty()) {
            update batchesToUpdate;
        }
    }

    /**
     * @description Calculates the appropriate batch status based on check record statuses
     * @param totalCount Total number of check records
     * @param pendingCount Number of checks in Pending status
     * @param submittedCount Number of checks in Submitted to HMLR status
     * @param terminalCount Number of checks in terminal statuses (have results)
     * @return The calculated batch status
     */
    private static String calculateBatchStatus(Integer totalCount, Integer pendingCount, Integer submittedCount, Integer terminalCount) {
        // No records - stay Pending
        if (totalCount == 0) {
            return 'Pending';
        }

        // All checks have terminal statuses (received results) - Complete
        if (terminalCount == totalCount) {
            return 'Complete';
        }

        // Some checks have results, but others are still pending/submitted - Partially Processed
        if (terminalCount > 0 && (pendingCount > 0 || submittedCount > 0)) {
            return 'Partially Processed';
        }

        // At least one check submitted, but no results yet - Processing
        if (submittedCount > 0 && terminalCount == 0) {
            return 'Processing';
        }

        // All checks are pending - Pending
        return 'Pending';
    }
}
