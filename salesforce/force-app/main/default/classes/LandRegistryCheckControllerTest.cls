/**
 * Test class for LandRegistryCheckController
 * Covers individual record actions and bulk operations
 */
@isTest
private class LandRegistryCheckControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create a batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Status__c = 'Processing',
            Total_Records__c = 5
        );
        insert batch;

        // Create test check records with various statuses
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();

        // Record 1: Under Review, with title deed URL
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_Name__c = 'John Smith',
            Landlord_Type__c = 'Individual',
            Property_Address__c = '123 Test Street\nLondon',
            Property_Postcode__c = 'SW1A 1AA',
            Status__c = 'Under Review',
            Match_Type__c = 'Property Only',
            Title_Number__c = 'TN12345',
            Title_Deed_URL__c = 'https://stlandregblob.blob.core.windows.net/title-deeds/test.pdf',
            Needs_Letter__c = false
        ));

        // Record 2: Pending, no title deed
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_Name__c = 'ABC Ltd',
            Landlord_Type__c = 'Company',
            Company_Name__c = 'ABC Ltd',
            Property_Address__c = '456 Business Park\nManchester',
            Property_Postcode__c = 'M1 2AB',
            Status__c = 'Pending',
            Needs_Letter__c = false
        ));

        // Record 3: Matched (already verified)
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_Name__c = 'Jane Doe',
            Landlord_Type__c = 'Individual',
            Property_Address__c = '789 Oak Lane\nBirmingham',
            Property_Postcode__c = 'B1 1AA',
            Status__c = 'Matched',
            Match_Type__c = 'Property and Person Match',
            Needs_Letter__c = false
        ));

        // Record 4: Closed
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_Name__c = 'Bob Wilson',
            Landlord_Type__c = 'Individual',
            Property_Address__c = '321 Elm Street\nLeeds',
            Property_Postcode__c = 'LS1 1AA',
            Status__c = 'Closed',
            Needs_Letter__c = false
        ));

        // Record 5: No Match, already flagged for letter
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_Name__c = 'XYZ Properties Ltd',
            Landlord_Type__c = 'Company',
            Company_Name__c = 'XYZ Properties Ltd',
            Property_Address__c = '555 Industrial Estate\nBristol',
            Property_Postcode__c = 'BS1 1AA',
            Status__c = 'No Match',
            Match_Type__c = 'No Property Match',
            Needs_Letter__c = true
        ));

        insert checks;
    }

    // ====== getCheckRecord Tests ======

    @isTest
    static void testGetCheckRecord() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Landlord_Name__c = 'John Smith' LIMIT 1];

        Test.startTest();
        LandRegistryCheckController.CheckRecordWrapper wrapper = LandRegistryCheckController.getCheckRecord(check.Id);
        Test.stopTest();

        System.assertEquals('John Smith', wrapper.landlordName);
        System.assertEquals('Under Review', wrapper.status);
        System.assertEquals('Property Only', wrapper.matchType);
        System.assertEquals('TN12345', wrapper.titleNumber);
        System.assert(wrapper.hasTitleDeed, 'Should have title deed');
        System.assert(wrapper.canMarkVerified, 'Should be able to mark verified');
        System.assert(wrapper.canClose, 'Should be able to close');
        System.assert(wrapper.canFlagForLetter, 'Should be able to flag for letter');
    }

    @isTest
    static void testGetCheckRecordClosedStatus() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Closed' LIMIT 1];

        Test.startTest();
        LandRegistryCheckController.CheckRecordWrapper wrapper = LandRegistryCheckController.getCheckRecord(check.Id);
        Test.stopTest();

        System.assertEquals('Closed', wrapper.status);
        System.assert(!wrapper.canMarkVerified, 'Should not be able to mark verified');
        System.assert(!wrapper.canClose, 'Should not be able to close again');
        System.assert(!wrapper.canFlagForLetter, 'Should not be able to flag for letter');
    }

    // ====== markAsVerified Tests ======

    @isTest
    static void testMarkAsVerified() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Under Review' LIMIT 1];

        Test.startTest();
        LandRegistryCheckController.markAsVerified(check.Id);
        Test.stopTest();

        check = [SELECT Status__c, Needs_Letter__c, Reviewed_By__c, Reviewed_Date__c FROM Land_Registry_Check__c WHERE Id = :check.Id];
        System.assertEquals('Matched', check.Status__c);
        System.assertEquals(false, check.Needs_Letter__c);
        System.assertEquals(UserInfo.getUserId(), check.Reviewed_By__c);
        System.assertNotEquals(null, check.Reviewed_Date__c);
    }

    @isTest
    static void testMarkAsVerifiedAlreadyMatched() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Matched' LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LandRegistryCheckController.markAsVerified(check.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown exception for already matched record');
    }

    @isTest
    static void testMarkAsVerifiedAlreadyClosed() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Closed' LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LandRegistryCheckController.markAsVerified(check.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown exception for closed record');
    }

    // ====== flagForLetter Tests ======

    @isTest
    static void testFlagForLetter() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Under Review' AND Needs_Letter__c = false LIMIT 1];

        Test.startTest();
        LandRegistryCheckController.flagForLetter(check.Id);
        Test.stopTest();

        check = [SELECT Needs_Letter__c, Reviewed_By__c, Reviewed_Date__c FROM Land_Registry_Check__c WHERE Id = :check.Id];
        System.assertEquals(true, check.Needs_Letter__c);
        System.assertEquals(UserInfo.getUserId(), check.Reviewed_By__c);
    }

    @isTest
    static void testFlagForLetterAlreadyFlagged() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Needs_Letter__c = true LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LandRegistryCheckController.flagForLetter(check.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown exception for already flagged record');
    }

    @isTest
    static void testFlagForLetterClosedRecord() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Closed' LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LandRegistryCheckController.flagForLetter(check.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown exception for closed record');
    }

    // ====== closeRecord Tests ======

    @isTest
    static void testCloseRecord() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Under Review' LIMIT 1];

        Test.startTest();
        LandRegistryCheckController.closeRecord(check.Id);
        Test.stopTest();

        check = [SELECT Status__c, Reviewed_By__c FROM Land_Registry_Check__c WHERE Id = :check.Id];
        System.assertEquals('Closed', check.Status__c);
        System.assertEquals(UserInfo.getUserId(), check.Reviewed_By__c);
    }

    @isTest
    static void testCloseRecordAlreadyClosed() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Closed' LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LandRegistryCheckController.closeRecord(check.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown exception for already closed record');
    }

    // ====== updateNotes Tests ======

    @isTest
    static void testUpdateNotes() {
        Land_Registry_Check__c check = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Under Review' LIMIT 1];
        String testNotes = 'Reviewed title deed - landlord name matches. Verified ownership.';

        Test.startTest();
        LandRegistryCheckController.updateNotes(check.Id, testNotes);
        Test.stopTest();

        check = [SELECT Notes__c, Reviewed_By__c FROM Land_Registry_Check__c WHERE Id = :check.Id];
        System.assertEquals(testNotes, check.Notes__c);
        System.assertEquals(UserInfo.getUserId(), check.Reviewed_By__c);
    }

    // ====== Bulk Action Tests ======

    @isTest
    static void testBulkFlagForLetter() {
        List<Land_Registry_Check__c> checks = [
            SELECT Id FROM Land_Registry_Check__c
            WHERE Status__c != 'Closed' AND Needs_Letter__c = false
        ];
        List<Id> recordIds = new List<Id>();
        for (Land_Registry_Check__c check : checks) {
            recordIds.add(check.Id);
        }

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkFlagForLetter(recordIds);
        Test.stopTest();

        System.assert(result.success, 'Bulk flag should succeed');
        System.assert(result.successCount > 0, 'Should have updated some records');

        // Verify records were updated
        Integer flaggedCount = [SELECT COUNT() FROM Land_Registry_Check__c WHERE Id IN :recordIds AND Needs_Letter__c = true];
        System.assertEquals(result.successCount, flaggedCount);
    }

    @isTest
    static void testBulkFlagForLetterWithSkips() {
        // Include already flagged and closed records
        List<Land_Registry_Check__c> allChecks = [SELECT Id FROM Land_Registry_Check__c];
        List<Id> recordIds = new List<Id>();
        for (Land_Registry_Check__c check : allChecks) {
            recordIds.add(check.Id);
        }

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkFlagForLetter(recordIds);
        Test.stopTest();

        System.assert(result.skippedCount > 0, 'Should have skipped some records');
    }

    @isTest
    static void testBulkCloseRecords() {
        List<Land_Registry_Check__c> checks = [
            SELECT Id FROM Land_Registry_Check__c
            WHERE Status__c != 'Closed'
        ];
        List<Id> recordIds = new List<Id>();
        for (Land_Registry_Check__c check : checks) {
            recordIds.add(check.Id);
        }

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkCloseRecords(recordIds);
        Test.stopTest();

        System.assert(result.success, 'Bulk close should succeed');
        System.assertEquals(checks.size(), result.successCount);

        // Verify all records are now closed
        Integer closedCount = [SELECT COUNT() FROM Land_Registry_Check__c WHERE Id IN :recordIds AND Status__c = 'Closed'];
        System.assertEquals(recordIds.size(), closedCount);
    }

    @isTest
    static void testBulkCloseAlreadyClosed() {
        Land_Registry_Check__c closedCheck = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Closed' LIMIT 1];
        List<Id> recordIds = new List<Id>{ closedCheck.Id };

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkCloseRecords(recordIds);
        Test.stopTest();

        System.assert(result.success, 'Should succeed even with nothing to update');
        System.assertEquals(0, result.successCount);
        System.assertEquals(1, result.skippedCount);
    }

    @isTest
    static void testBulkUpdateStatus() {
        List<Land_Registry_Check__c> checks = [
            SELECT Id FROM Land_Registry_Check__c
            WHERE Status__c = 'Pending'
        ];
        List<Id> recordIds = new List<Id>();
        for (Land_Registry_Check__c check : checks) {
            recordIds.add(check.Id);
        }

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkUpdateStatus(recordIds, 'Under Review');
        Test.stopTest();

        System.assert(result.success, 'Bulk update should succeed');

        // Verify status was updated
        Integer updatedCount = [SELECT COUNT() FROM Land_Registry_Check__c WHERE Id IN :recordIds AND Status__c = 'Under Review'];
        System.assertEquals(result.successCount, updatedCount);
    }

    @isTest
    static void testBulkUpdateStatusInvalidStatus() {
        List<Id> recordIds = new List<Id>();
        for (Land_Registry_Check__c check : [SELECT Id FROM Land_Registry_Check__c LIMIT 2]) {
            recordIds.add(check.Id);
        }

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkUpdateStatus(recordIds, 'InvalidStatus');
        Test.stopTest();

        System.assert(!result.success, 'Should fail with invalid status');
        System.assert(result.message.contains('Invalid status'));
    }

    @isTest
    static void testBulkUpdateStatusNoChanges() {
        Land_Registry_Check__c matchedCheck = [SELECT Id FROM Land_Registry_Check__c WHERE Status__c = 'Matched' LIMIT 1];
        List<Id> recordIds = new List<Id>{ matchedCheck.Id };

        Test.startTest();
        LandRegistryCheckController.BulkActionResult result = LandRegistryCheckController.bulkUpdateStatus(recordIds, 'Matched');
        Test.stopTest();

        System.assert(result.success, 'Should succeed with nothing to update');
        System.assertEquals(0, result.successCount);
        System.assertEquals(1, result.skippedCount);
    }

    // ====== getStatusPicklistValues Test ======

    @isTest
    static void testGetStatusPicklistValues() {
        Test.startTest();
        List<LandRegistryCheckController.StatusOption> options = LandRegistryCheckController.getStatusPicklistValues();
        Test.stopTest();

        System.assert(options.size() >= 7, 'Should return all status values');

        Set<String> expectedValues = new Set<String>{
            'Pending', 'Submitted to HMLR', 'Matched', 'No Match', 'Under Review', 'Letter Sent', 'Closed'
        };

        for (LandRegistryCheckController.StatusOption option : options) {
            System.assert(expectedValues.contains(option.value), 'Unexpected status: ' + option.value);
        }
    }
}
