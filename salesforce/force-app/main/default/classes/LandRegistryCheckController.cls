/**
 * Controller for Land Registry Check record actions and bulk operations.
 * Used by landRegistryCheckActions (SF-2.6) and landRegistryBulkActions (SF-2.8) LWC components.
 */
public with sharing class LandRegistryCheckController {

    // ====== SF-2.6: Individual Record Actions ======

    /**
     * Get record data for the check actions component
     */
    @AuraEnabled(cacheable=true)
    public static CheckRecordWrapper getCheckRecord(Id recordId) {
        Land_Registry_Check__c record = [
            SELECT Id, Name, Status__c, Match_Type__c, Title_Deed_URL__c,
                   Title_Number__c, Notes__c, Needs_Letter__c, Landlord_Name__c,
                   Property_Address__c, Property_Postcode__c
            FROM Land_Registry_Check__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        return new CheckRecordWrapper(record);
    }

    /**
     * Mark record as verified - sets Status to Matched and clears Needs_Letter flag
     */
    @AuraEnabled
    public static void markAsVerified(Id recordId) {
        Land_Registry_Check__c record = [
            SELECT Id, Status__c, Needs_Letter__c
            FROM Land_Registry_Check__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (record.Status__c == 'Matched' || record.Status__c == 'Closed') {
            throw new AuraHandledException('Record is already verified or closed.');
        }

        record.Status__c = 'Matched';
        record.Needs_Letter__c = false;
        setReviewFields(record);

        update record;
    }

    /**
     * Flag record for compliance letter
     */
    @AuraEnabled
    public static void flagForLetter(Id recordId) {
        Land_Registry_Check__c record = [
            SELECT Id, Status__c, Needs_Letter__c
            FROM Land_Registry_Check__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (record.Status__c == 'Closed') {
            throw new AuraHandledException('Cannot flag a closed record for letter.');
        }

        if (record.Needs_Letter__c == true) {
            throw new AuraHandledException('Record is already flagged for letter.');
        }

        record.Needs_Letter__c = true;
        setReviewFields(record);

        update record;
    }

    /**
     * Close the record
     */
    @AuraEnabled
    public static void closeRecord(Id recordId) {
        Land_Registry_Check__c record = [
            SELECT Id, Status__c
            FROM Land_Registry_Check__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (record.Status__c == 'Closed') {
            throw new AuraHandledException('Record is already closed.');
        }

        record.Status__c = 'Closed';
        setReviewFields(record);

        update record;
    }

    /**
     * Update notes on the record
     */
    @AuraEnabled
    public static void updateNotes(Id recordId, String notes) {
        Land_Registry_Check__c record = [
            SELECT Id, Notes__c
            FROM Land_Registry_Check__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        record.Notes__c = notes;
        setReviewFields(record);

        update record;
    }

    // ====== SF-2.8: Bulk Actions ======

    /**
     * Bulk flag records for compliance letter
     */
    @AuraEnabled
    public static BulkActionResult bulkFlagForLetter(List<Id> recordIds) {
        List<Land_Registry_Check__c> records = [
            SELECT Id, Status__c, Needs_Letter__c
            FROM Land_Registry_Check__c
            WHERE Id IN :recordIds
        ];

        List<Land_Registry_Check__c> toUpdate = new List<Land_Registry_Check__c>();
        Integer skipped = 0;

        for (Land_Registry_Check__c record : records) {
            if (record.Status__c == 'Closed' || record.Needs_Letter__c == true) {
                skipped++;
                continue;
            }
            record.Needs_Letter__c = true;
            setReviewFields(record);
            toUpdate.add(record);
        }

        return processBulkUpdate(toUpdate, skipped, 'flagged for letter');
    }

    /**
     * Bulk close records
     */
    @AuraEnabled
    public static BulkActionResult bulkCloseRecords(List<Id> recordIds) {
        List<Land_Registry_Check__c> records = [
            SELECT Id, Status__c
            FROM Land_Registry_Check__c
            WHERE Id IN :recordIds
        ];

        List<Land_Registry_Check__c> toUpdate = new List<Land_Registry_Check__c>();
        Integer skipped = 0;

        for (Land_Registry_Check__c record : records) {
            if (record.Status__c == 'Closed') {
                skipped++;
                continue;
            }
            record.Status__c = 'Closed';
            setReviewFields(record);
            toUpdate.add(record);
        }

        return processBulkUpdate(toUpdate, skipped, 'closed');
    }

    /**
     * Bulk update status on records
     */
    @AuraEnabled
    public static BulkActionResult bulkUpdateStatus(List<Id> recordIds, String newStatus) {
        // Validate status is a valid picklist value
        Set<String> validStatuses = new Set<String>{
            'Pending', 'Submitted to HMLR', 'Matched', 'No Match',
            'Under Review', 'Letter Sent', 'Closed'
        };

        if (!validStatuses.contains(newStatus)) {
            BulkActionResult result = new BulkActionResult();
            result.success = false;
            result.message = 'Invalid status value: ' + newStatus;
            return result;
        }

        List<Land_Registry_Check__c> records = [
            SELECT Id, Status__c
            FROM Land_Registry_Check__c
            WHERE Id IN :recordIds
        ];

        List<Land_Registry_Check__c> toUpdate = new List<Land_Registry_Check__c>();
        Integer skipped = 0;

        for (Land_Registry_Check__c record : records) {
            if (record.Status__c == newStatus) {
                skipped++;
                continue;
            }
            record.Status__c = newStatus;
            setReviewFields(record);
            toUpdate.add(record);
        }

        return processBulkUpdate(toUpdate, skipped, 'updated to ' + newStatus);
    }

    /**
     * Get status picklist values for dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<StatusOption> getStatusPicklistValues() {
        List<StatusOption> options = new List<StatusOption>();

        Schema.DescribeFieldResult fieldResult = Land_Registry_Check__c.Status__c.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new StatusOption(entry.getLabel(), entry.getValue()));
            }
        }

        return options;
    }

    // ====== Helper Methods ======

    /**
     * Set review tracking fields on record
     */
    private static void setReviewFields(Land_Registry_Check__c record) {
        record.Reviewed_By__c = UserInfo.getUserId();
        record.Reviewed_Date__c = DateTime.now();
    }

    /**
     * Process bulk update with partial success handling
     */
    private static BulkActionResult processBulkUpdate(List<Land_Registry_Check__c> toUpdate, Integer skipped, String actionName) {
        BulkActionResult result = new BulkActionResult();

        if (toUpdate.isEmpty()) {
            result.success = true;
            result.successCount = 0;
            result.errorCount = 0;
            result.skippedCount = skipped;
            result.message = 'No records to update. ' + skipped + ' records skipped.';
            return result;
        }

        Database.SaveResult[] saveResults = Database.update(toUpdate, false);

        Integer successCount = 0;
        Integer errorCount = 0;
        List<String> errors = new List<String>();

        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                successCount++;
            } else {
                errorCount++;
                for (Database.Error err : saveResults[i].getErrors()) {
                    errors.add(toUpdate[i].Id + ': ' + err.getMessage());
                }
            }
        }

        result.success = (errorCount == 0);
        result.successCount = successCount;
        result.errorCount = errorCount;
        result.skippedCount = skipped;
        result.errors = errors;

        if (errorCount == 0) {
            result.message = successCount + ' records ' + actionName + ' successfully.';
            if (skipped > 0) {
                result.message += ' ' + skipped + ' records skipped.';
            }
        } else if (successCount > 0) {
            result.message = 'Partial success: ' + successCount + ' updated, ' + errorCount + ' failed.';
        } else {
            result.message = 'Failed to update records. See errors for details.';
        }

        return result;
    }

    // ====== Wrapper Classes ======

    /**
     * Wrapper for check record data sent to LWC
     */
    public class CheckRecordWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String matchType;
        @AuraEnabled public String titleDeedUrl;
        @AuraEnabled public String titleNumber;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean needsLetter;
        @AuraEnabled public String landlordName;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String postcode;

        // Computed properties for button state
        @AuraEnabled public Boolean hasTitleDeed;
        @AuraEnabled public Boolean canMarkVerified;
        @AuraEnabled public Boolean canClose;
        @AuraEnabled public Boolean canFlagForLetter;

        public CheckRecordWrapper(Land_Registry_Check__c record) {
            this.id = record.Id;
            this.name = record.Name;
            this.status = record.Status__c;
            this.matchType = record.Match_Type__c;
            this.titleDeedUrl = record.Title_Deed_URL__c;
            this.titleNumber = record.Title_Number__c;
            this.notes = record.Notes__c;
            this.needsLetter = record.Needs_Letter__c;
            this.landlordName = record.Landlord_Name__c;
            this.propertyAddress = record.Property_Address__c;
            this.postcode = record.Property_Postcode__c;

            // Compute button states
            this.hasTitleDeed = String.isNotBlank(record.Title_Deed_URL__c);
            this.canMarkVerified = record.Status__c != 'Matched' && record.Status__c != 'Closed';
            this.canClose = record.Status__c != 'Closed';
            this.canFlagForLetter = record.Status__c != 'Closed' && record.Needs_Letter__c != true;
        }
    }

    /**
     * Result wrapper for bulk operations
     */
    public class BulkActionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public String message;

        public BulkActionResult() {
            this.errors = new List<String>();
            this.skippedCount = 0;
        }
    }

    /**
     * Status option for picklist dropdown
     */
    public class StatusOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public StatusOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
