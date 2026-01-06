/**
 * @description Test class for LandRegistryBatchRollupHandler and LandRegistryCheckTrigger
 */
@isTest
private class LandRegistryBatchRollupHandlerTest {

    @TestSetup
    static void setupTestData() {
        // Create a test batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Upload_Date__c = DateTime.now(),
            Status__c = 'Pending',
            Total_Records__c = 10
        );
        insert batch;
    }

    @isTest
    static void testInsertCheckRecords() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // Insert check records with various statuses
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Company'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        insert checks;
        Test.stopTest();

        // Verify batch counts
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(2, batch.Matched_Count__c, 'Matched count should be 2');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should be 1');
        System.assertEquals(3, batch.Processed_Count__c, 'Processed count should be 3 (excluding Pending)');
    }

    @isTest
    static void testUpdateCheckRecords() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert initial records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Company'));
        insert checks;

        // Verify initial counts
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(0, batch.Matched_Count__c, 'Initial matched count should be 0');
        System.assertEquals(0, batch.Processed_Count__c, 'Initial processed count should be 0');

        Test.startTest();
        // Update statuses
        checks[0].Status__c = 'Matched';
        checks[1].Status__c = 'Under Review';
        checks[2].Status__c = 'No Match';
        update checks;
        Test.stopTest();

        // Verify updated counts
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(1, batch.Matched_Count__c, 'Matched count should be 1');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should be 1');
        System.assertEquals(3, batch.Processed_Count__c, 'Processed count should be 3');
    }

    @isTest
    static void testDeleteCheckRecords() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        insert checks;

        // Verify counts before delete
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(2, batch.Matched_Count__c, 'Matched count should be 2');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should be 1');

        Test.startTest();
        // Delete one matched record
        delete checks[0];
        Test.stopTest();

        // Verify counts after delete
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(1, batch.Matched_Count__c, 'Matched count should be 1 after delete');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should still be 1');
        System.assertEquals(2, batch.Processed_Count__c, 'Processed count should be 2');
    }

    @isTest
    static void testUndeleteCheckRecords() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert and delete a record
        Land_Registry_Check__c check = createCheck(batch.Id, 'Matched', 'Individual');
        insert check;
        delete check;

        // Verify count after delete
        batch = [SELECT Matched_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(0, batch.Matched_Count__c, 'Matched count should be 0 after delete');

        Test.startTest();
        // Undelete the record
        undelete check;
        Test.stopTest();

        // Verify count after undelete
        batch = [SELECT Matched_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(1, batch.Matched_Count__c, 'Matched count should be 1 after undelete');
    }

    @isTest
    static void testAllStatusTypes() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // Insert records with all status types
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Submitted to HMLR', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        checks.add(createCheck(batch.Id, 'Under Review', 'Individual'));
        checks.add(createCheck(batch.Id, 'Letter Sent', 'Individual'));
        checks.add(createCheck(batch.Id, 'Closed', 'Individual'));
        insert checks;
        Test.stopTest();

        // Verify counts
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(1, batch.Matched_Count__c, 'Matched count should be 1');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should be 1 (No Match only)');
        System.assertEquals(6, batch.Processed_Count__c, 'Processed count should be 6 (all except Pending)');
    }

    @isTest
    static void testRecalculateBatchCounts() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert records directly without trigger (simulating existing data)
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Company'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        insert checks;

        Test.startTest();
        // Call recalculate directly
        Set<Id> batchIds = new Set<Id>{ batch.Id };
        LandRegistryBatchRollupHandler.recalculateBatchCounts(batchIds);
        Test.stopTest();

        // Verify counts
        batch = [SELECT Matched_Count__c, Failed_Count__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(2, batch.Matched_Count__c, 'Matched count should be 2');
        System.assertEquals(1, batch.Failed_Count__c, 'Failed count should be 1');
    }

    @isTest
    static void testEmptyBatchIds() {
        Test.startTest();
        // Call with empty set - should not throw error
        Set<Id> emptySet = new Set<Id>();
        LandRegistryBatchRollupHandler.recalculateBatchCounts(emptySet);
        Test.stopTest();

        // No assertions needed - just verify no exception
        System.assert(true, 'Method should handle empty set gracefully');
    }

    @isTest
    static void testBatchStatusPending() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // All records Pending - batch should be Pending
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        insert checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Pending', batch.Status__c, 'Batch status should be Pending when all checks are Pending');
    }

    @isTest
    static void testBatchStatusProcessing() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // Some records Submitted, none with results - batch should be Processing
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Submitted to HMLR', 'Individual'));
        checks.add(createCheck(batch.Id, 'Submitted to HMLR', 'Company'));
        insert checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Processing', batch.Status__c, 'Batch status should be Processing when records submitted but no results');
    }

    @isTest
    static void testBatchStatusPartiallyProcessed() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // Some records have results, some still pending/submitted - batch should be Partially Processed
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Submitted to HMLR', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'No Match', 'Company'));
        insert checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Partially Processed', batch.Status__c, 'Batch status should be Partially Processed when some have results');
    }

    @isTest
    static void testBatchStatusComplete() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        // All records have terminal statuses - batch should be Complete
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        checks.add(createCheck(batch.Id, 'Under Review', 'Individual'));
        checks.add(createCheck(batch.Id, 'Letter Sent', 'Company'));
        checks.add(createCheck(batch.Id, 'Closed', 'Company'));
        insert checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Complete', batch.Status__c, 'Batch status should be Complete when all checks have results');
    }

    @isTest
    static void testBatchStatusFailedNotOverridden() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Set batch to Failed status (simulating a technical error)
        batch.Status__c = 'Failed';
        batch.Error_Message__c = 'API connection failed';
        update batch;

        Test.startTest();
        // Insert records - Failed status should NOT be overridden
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        insert checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Failed', batch.Status__c, 'Failed status should not be overridden by trigger');
    }

    @isTest
    static void testBatchStatusTransition() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Start with Pending records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Company'));
        insert checks;

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Pending', batch.Status__c, 'Initial status should be Pending');

        Test.startTest();
        // Submit one record - should transition to Processing
        checks[0].Status__c = 'Submitted to HMLR';
        update checks[0];

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Processing', batch.Status__c, 'Status should be Processing after submission');

        // Receive result for submitted record - should transition to Partially Processed
        checks[0].Status__c = 'Matched';
        update checks[0];

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Partially Processed', batch.Status__c, 'Status should be Partially Processed with mixed results');

        // Complete all records - should transition to Complete
        checks[1].Status__c = 'No Match';
        checks[2].Status__c = 'Matched';
        update checks;
        Test.stopTest();

        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Complete', batch.Status__c, 'Status should be Complete when all have results');
    }

    @isTest
    static void testStartedAtTimestamp() {
        Land_Registry_Batch__c batch = [SELECT Id, Started_At__c FROM Land_Registry_Batch__c LIMIT 1];
        System.assertEquals(null, batch.Started_At__c, 'Started_At should be null initially');

        // Insert pending records - Started_At should remain null
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        checks.add(createCheck(batch.Id, 'Pending', 'Individual'));
        insert checks;

        batch = [SELECT Started_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(null, batch.Started_At__c, 'Started_At should still be null when all Pending');

        Test.startTest();
        // Submit first record - Started_At should be set
        checks[0].Status__c = 'Submitted to HMLR';
        update checks[0];
        Test.stopTest();

        batch = [SELECT Started_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertNotEquals(null, batch.Started_At__c, 'Started_At should be set when first record submitted');
    }

    @isTest
    static void testCompletedAtTimestamp() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert records with terminal statuses (but not Closed)
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Matched', 'Individual'));
        checks.add(createCheck(batch.Id, 'No Match', 'Individual'));
        insert checks;

        batch = [SELECT Completed_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(null, batch.Completed_At__c, 'Completed_At should be null when not all Closed');

        Test.startTest();
        // Close all records - Completed_At should be set
        checks[0].Status__c = 'Closed';
        checks[1].Status__c = 'Closed';
        update checks;
        Test.stopTest();

        batch = [SELECT Completed_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertNotEquals(null, batch.Completed_At__c, 'Completed_At should be set when all records Closed');
    }

    @isTest
    static void testCompletedAtClearedOnReopen() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Insert closed records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        checks.add(createCheck(batch.Id, 'Closed', 'Individual'));
        checks.add(createCheck(batch.Id, 'Closed', 'Individual'));
        insert checks;

        batch = [SELECT Completed_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertNotEquals(null, batch.Completed_At__c, 'Completed_At should be set when all Closed');

        Test.startTest();
        // Reopen one record - Completed_At should be cleared
        checks[0].Status__c = 'Under Review';
        update checks[0];
        Test.stopTest();

        batch = [SELECT Completed_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals(null, batch.Completed_At__c, 'Completed_At should be cleared when record reopened');
    }

    // Helper method to create check records
    private static Land_Registry_Check__c createCheck(Id batchId, String status, String landlordType) {
        return new Land_Registry_Check__c(
            Batch__c = batchId,
            Status__c = status,
            Landlord_Type__c = landlordType,
            Landlord_Name__c = 'Test Landlord',
            Property_Address__c = '123 Test Street',
            Property_Postcode__c = 'SW1A 1AA'
        );
    }
}
