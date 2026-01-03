/**
 * @description Test class for LandRegistryDashboardController
 */
@isTest
private class LandRegistryDashboardControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Upload_Date__c = DateTime.now(),
            Status__c = 'Pending',
            Total_Records__c = 5,
            Processed_Count__c = 0,
            Matched_Count__c = 0,
            Failed_Count__c = 0
        );
        insert batch;

        // Create test checks
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        for (Integer i = 0; i < 5; i++) {
            checks.add(new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL00' + i,
                Landlord_Name__c = 'Test Landlord ' + i,
                Landlord_Type__c = Math.mod(i, 2) == 0 ? 'Individual' : 'Company',
                Property_Address__c = '123 Test Street',
                Property_Postcode__c = 'TE1 1ST',
                Status__c = 'Pending'
            ));
        }
        insert checks;
    }

    @isTest
    static void testGetRecentBatches() {
        Test.startTest();
        List<LandRegistryDashboardController.BatchWrapper> batches =
            LandRegistryDashboardController.getRecentBatches();
        Test.stopTest();

        System.assertEquals(1, batches.size(), 'Should return 1 batch');
        System.assertEquals('Pending', batches[0].status);
        System.assertEquals(5, batches[0].totalRecords);
    }

    @isTest
    static void testGetDashboardMetrics() {
        Test.startTest();
        Map<String, Object> metrics = LandRegistryDashboardController.getDashboardMetrics();
        Test.stopTest();

        System.assertEquals(1, metrics.get('totalBatches'));
        System.assertEquals(5, metrics.get('totalChecks'));
        System.assertEquals(3, metrics.get('individualCount')); // 0, 2, 4 are individuals
        System.assertEquals(2, metrics.get('companyCount')); // 1, 3 are companies
    }

    @isTest
    static void testGetBatchWithChecks() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        Land_Registry_Batch__c result = LandRegistryDashboardController.getBatchWithChecks(batch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(5, result.Land_Registry_Checks__r.size());
    }

    @isTest
    static void testStartBatchProcessing() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        String result = LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        System.assert(result.contains('Processing started'));

        // Verify batch status updated
        batch = [SELECT Status__c, Started_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Processing', batch.Status__c);
        System.assertNotEquals(null, batch.Started_At__c);

        // Verify check statuses updated
        List<Land_Registry_Check__c> checks = [
            SELECT Status__c FROM Land_Registry_Check__c WHERE Batch__c = :batch.Id
        ];
        for (Land_Registry_Check__c check : checks) {
            System.assertEquals('Submitted to HMLR', check.Status__c);
        }
    }

    @isTest
    static void testStartBatchProcessingNotPending() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];
        batch.Status__c = 'Processing';
        update batch;

        Test.startTest();
        String result = LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        System.assert(result.contains('not in Pending status'));
    }
}
