/**
 * @description Test class for LandRegistryDashboardController
 */
@isTest
private class LandRegistryDashboardControllerTest {

    /**
     * @description Mock for successful Azure Function response
     */
    private class MockHttpSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Success":true,"EmailMessageId":"mock-email-123","RecordsProcessed":2,"RecipientEmail":"test@test.com"}');
            return res;
        }
    }

    /**
     * @description Mock for Azure Function failure
     */
    private class MockHttpFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Success":false,"ErrorMessage":"Test failure"}');
            return res;
        }
    }

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

        // Create test checks - 3 individuals (0, 2, 4) and 2 companies (1, 3)
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();
        for (Integer i = 0; i < 5; i++) {
            Boolean isCompany = Math.mod(i, 2) == 1;
            checks.add(new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL00' + i,
                Landlord_Name__c = isCompany ? 'Test Company ' + i + ' Ltd' : 'John Smith ' + i,
                Landlord_Type__c = isCompany ? 'Company' : 'Individual',
                Company_Name__c = isCompany ? 'Test Company ' + i + ' Ltd' : null,
                Forename__c = isCompany ? null : 'John',
                Surname__c = isCompany ? null : 'Smith',
                Property_Address__c = '123 Test Street\nTest Town\nTest County',
                Property_Postcode__c = 'TE1 1ST',
                Status__c = 'Pending'
            ));
        }
        insert checks;

        // Create custom setting for Azure Function configuration (org defaults)
        // For hierarchy custom settings, SetupOwnerId must be the org ID for org defaults
        Land_Registry_Settings__c settings = new Land_Registry_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Azure_Function_Key__c = 'test-key-123',
            Azure_Function_URL__c = 'https://func-landreg-api.azurewebsites.net'
        );
        insert settings;
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
    static void testStartBatchProcessingWithCompaniesAndIndividuals() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        LandRegistryDashboardController.ProcessingResult result =
            LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        // Verify result structure
        System.assertEquals(true, result.success, 'Processing should succeed');
        System.assertEquals(3, result.individualCount, 'Should have 3 individuals');
        System.assertEquals(2, result.companyCount, 'Should have 2 companies');

        // Company processing should succeed
        System.assertEquals(true, result.companySubmissionSuccess, 'Company submission should succeed');
        System.assertEquals(2, result.companiesSubmitted, 'Should submit 2 companies');
        System.assertNotEquals(null, result.emailMessageId, 'Should have email message ID');

        // Individual processing should report as not available
        System.assertEquals(false, result.individualSubmissionSuccess, 'Individual API not yet available');
        System.assertEquals(0, result.individualsSubmitted, 'No individuals should be submitted');
        System.assert(result.individualSubmissionMessage.contains('not yet available'),
            'Message should mention API not available');

        // Verify batch status - should be Partially Processed since individuals remain
        batch = [SELECT Status__c, Started_At__c, Processed_Count__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Partially Processed', batch.Status__c, 'Batch should be Partially Processed');
        System.assertNotEquals(null, batch.Started_At__c, 'Should have start time');
        System.assertEquals(2, batch.Processed_Count__c, 'Should show 2 processed');

        // Verify company check statuses updated to Submitted
        List<Land_Registry_Check__c> companyChecks = [
            SELECT Status__c FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Company'
        ];
        for (Land_Registry_Check__c check : companyChecks) {
            System.assertEquals('Submitted to HMLR', check.Status__c, 'Company should be Submitted');
        }

        // Verify individual check statuses remain Pending
        List<Land_Registry_Check__c> individualChecks = [
            SELECT Status__c FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Individual'
        ];
        for (Land_Registry_Check__c check : individualChecks) {
            System.assertEquals('Pending', check.Status__c, 'Individual should remain Pending');
        }
    }

    @isTest
    static void testStartBatchProcessingCompaniesOnly() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Change all records to Company type
        List<Land_Registry_Check__c> checks = [
            SELECT Id, Landlord_Type__c, Company_Name__c
            FROM Land_Registry_Check__c WHERE Batch__c = :batch.Id
        ];
        for (Land_Registry_Check__c check : checks) {
            check.Landlord_Type__c = 'Company';
            check.Company_Name__c = 'Test Company Ltd';
        }
        update checks;

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        LandRegistryDashboardController.ProcessingResult result =
            LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Processing should succeed');
        System.assertEquals(0, result.individualCount, 'Should have 0 individuals');
        System.assertEquals(5, result.companyCount, 'Should have 5 companies');
        System.assertEquals(5, result.companiesSubmitted, 'Should submit all 5 companies');

        // Batch should be Complete (no individuals pending)
        batch = [SELECT Status__c, Completed_At__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Complete', batch.Status__c, 'Batch should be Complete');
        System.assertNotEquals(null, batch.Completed_At__c, 'Should have completion time');
    }

    @isTest
    static void testStartBatchProcessingIndividualsOnly() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Change all records to Individual type
        List<Land_Registry_Check__c> checks = [
            SELECT Id, Landlord_Type__c, Company_Name__c, Forename__c, Surname__c
            FROM Land_Registry_Check__c WHERE Batch__c = :batch.Id
        ];
        for (Land_Registry_Check__c check : checks) {
            check.Landlord_Type__c = 'Individual';
            check.Company_Name__c = null;
            check.Forename__c = 'John';
            check.Surname__c = 'Smith';
        }
        update checks;

        Test.startTest();
        LandRegistryDashboardController.ProcessingResult result =
            LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        // Success is true because company submission succeeded (no companies to fail)
        System.assertEquals(true, result.success, 'Processing should succeed (companies done)');
        System.assertEquals(5, result.individualCount, 'Should have 5 individuals');
        System.assertEquals(0, result.companyCount, 'Should have 0 companies');
        System.assertEquals(0, result.individualsSubmitted, 'No individuals submitted yet');

        // Batch should be Partially Processed (individuals pending)
        batch = [SELECT Status__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Partially Processed', batch.Status__c, 'Batch should be Partially Processed');
    }

    @isTest
    static void testStartBatchProcessingCompanyFailure() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockHttpFailure());

        Test.startTest();
        LandRegistryDashboardController.ProcessingResult result =
            LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Processing should fail');
        System.assertEquals(false, result.companySubmissionSuccess, 'Company submission should fail');

        // Batch should be Failed
        batch = [SELECT Status__c, Error_Message__c FROM Land_Registry_Batch__c WHERE Id = :batch.Id];
        System.assertEquals('Failed', batch.Status__c, 'Batch should be Failed');
        System.assertNotEquals(null, batch.Error_Message__c, 'Should have error message');
    }

    @isTest
    static void testStartBatchProcessingNotPending() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];
        batch.Status__c = 'Processing';
        update batch;

        Test.startTest();
        LandRegistryDashboardController.ProcessingResult result =
            LandRegistryDashboardController.startBatchProcessing(batch.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail for non-pending batch');
        System.assert(result.message.contains('not in Pending status'),
            'Message should mention not in Pending status');
    }

    @isTest
    static void testBatchWrapperStatusClasses() {
        // Test the getStatusClass method through BatchWrapper
        Land_Registry_Batch__c pendingBatch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Test Pending status
        Land_Registry_Batch__c batchData = [
            SELECT Id, Name, Upload_Date__c, Status__c, Total_Records__c,
                   Processed_Count__c, Matched_Count__c, Failed_Count__c,
                   Progress_Percent__c, Started_At__c, Completed_At__c,
                   (SELECT Id, Status__c FROM Land_Registry_Checks__r)
            FROM Land_Registry_Batch__c
            WHERE Id = :pendingBatch.Id
        ];

        LandRegistryDashboardController.BatchWrapper wrapper =
            new LandRegistryDashboardController.BatchWrapper(batchData);
        System.assertEquals('slds-theme_shade', wrapper.statusClass, 'Pending should use shade theme');

        // Update to test other statuses
        batchData.Status__c = 'Processing';
        wrapper = new LandRegistryDashboardController.BatchWrapper(batchData);
        System.assertEquals('slds-theme_info', wrapper.statusClass, 'Processing should use info theme');

        batchData.Status__c = 'Complete';
        wrapper = new LandRegistryDashboardController.BatchWrapper(batchData);
        System.assertEquals('slds-theme_success', wrapper.statusClass, 'Complete should use success theme');

        batchData.Status__c = 'Failed';
        wrapper = new LandRegistryDashboardController.BatchWrapper(batchData);
        System.assertEquals('slds-theme_error', wrapper.statusClass, 'Failed should use error theme');

        batchData.Status__c = 'Partially Processed';
        wrapper = new LandRegistryDashboardController.BatchWrapper(batchData);
        System.assertEquals('slds-theme_warning', wrapper.statusClass, 'Partially Processed should use warning theme');
    }

    @isTest
    static void testProcessingResultDefaults() {
        LandRegistryDashboardController.ProcessingResult result =
            new LandRegistryDashboardController.ProcessingResult();

        System.assertEquals(false, result.success, 'Default success should be false');
        System.assertEquals(0, result.individualCount, 'Default individualCount should be 0');
        System.assertEquals(0, result.companyCount, 'Default companyCount should be 0');
        System.assertEquals(0, result.companiesSubmitted, 'Default companiesSubmitted should be 0');
        System.assertEquals(0, result.individualsSubmitted, 'Default individualsSubmitted should be 0');
    }
}
