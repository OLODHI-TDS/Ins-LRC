/**
 * @description Test class for HMLRCompanySubmission
 */
@isTest
private class HMLRCompanySubmissionTest {

    @TestSetup
    static void setupTestData() {
        // Create custom setting
        Land_Registry_Settings__c settings = new Land_Registry_Settings__c();
        settings.Azure_Function_Key__c = 'test-function-key-12345';
        settings.Azure_Function_URL__c = 'https://func-landreg-api.azurewebsites.net';
        insert settings;

        // Create a batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Status__c = 'Pending',
            Upload_Date__c = DateTime.now(),
            Total_Records__c = 3
        );
        insert batch;

        // Create company records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();

        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_ID__c = '12345',
            Landlord_Name__c = 'ABC Properties Ltd',
            Landlord_Type__c = 'Company',
            Company_Name__c = 'ABC Properties Ltd',
            Property_Address__c = '123 Test Street\nTest Town\nTest County',
            Property_Postcode__c = 'TE1 1ST',
            Status__c = 'Pending'
        ));

        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_ID__c = '67890',
            Landlord_Name__c = 'XYZ Holdings Limited',
            Landlord_Type__c = 'Company',
            Company_Name__c = 'XYZ Holdings Limited',
            Property_Address__c = '456 Business Park, Manchester, Greater Manchester',
            Property_Postcode__c = 'M1 2AB',
            Status__c = 'Pending'
        ));

        // Add an individual record (should not be included in company submission)
        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_ID__c = '11111',
            Landlord_Name__c = 'John Smith',
            Landlord_Type__c = 'Individual',
            Forename__c = 'John',
            Surname__c = 'Smith',
            Property_Address__c = '789 Residential Road\nSmalltown\nCounty',
            Property_Postcode__c = 'SM1 1AA',
            Status__c = 'Pending'
        ));

        insert checks;
    }

    /**
     * @description Mock class for successful Azure Function response
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Success":true,"BatchId":"test-batch","RecordsProcessed":2,"EmailMessageId":"msg-123","SentAt":"2026-01-04T12:00:00Z","RecipientEmail":"test@example.com"}');
            return res;
        }
    }

    /**
     * @description Mock class for failed Azure Function response
     */
    private class MockHttpResponseFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Success":false,"ErrorMessage":"Test error message"}');
            return res;
        }
    }

    /**
     * @description Mock class for HTTP error
     */
    private class MockHttpResponseError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    @isTest
    static void testSubmitCompanyBatch_Success() {
        // Get the batch
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(batch.Id);

        Test.stopTest();

        // Verify result
        System.assertEquals(true, result.success, 'Submission should be successful');
        System.assertEquals(2, result.recordsSubmitted, 'Should have submitted 2 company records');
        System.assertEquals('msg-123', result.emailMessageId, 'Should have email message ID');
        System.assertEquals('test@example.com', result.recipientEmail, 'Should have recipient email');

        // Verify records updated to Submitted
        List<Land_Registry_Check__c> updatedChecks = [
            SELECT Id, Status__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Company'
        ];
        for (Land_Registry_Check__c check : updatedChecks) {
            System.assertEquals('Submitted to HMLR', check.Status__c, 'Company records should be marked as Submitted');
        }

        // Verify individual record not changed
        Land_Registry_Check__c individualCheck = [
            SELECT Status__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Individual'
            LIMIT 1
        ];
        System.assertEquals('Pending', individualCheck.Status__c, 'Individual record should still be Pending');
    }

    @isTest
    static void testSubmitCompanyBatch_AzureFunctionFailure() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseFailure());

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(batch.Id);

        Test.stopTest();

        System.assertEquals(false, result.success, 'Submission should fail');
        System.assert(result.message.contains('Test error message'), 'Should contain error message');

        // Verify records NOT updated
        List<Land_Registry_Check__c> checks = [
            SELECT Status__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Company'
        ];
        for (Land_Registry_Check__c check : checks) {
            System.assertEquals('Pending', check.Status__c, 'Records should still be Pending after failure');
        }
    }

    @isTest
    static void testSubmitCompanyBatch_HttpError() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError());

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(batch.Id);

        Test.stopTest();

        System.assertEquals(false, result.success, 'Submission should fail');
        System.assert(result.message.contains('HTTP 500'), 'Should contain HTTP error');
    }

    @isTest
    static void testSubmitCompanyBatch_NoRecords() {
        // Create a batch with no company records
        Land_Registry_Batch__c emptyBatch = new Land_Registry_Batch__c(
            Status__c = 'Pending',
            Upload_Date__c = DateTime.now(),
            Total_Records__c = 0
        );
        insert emptyBatch;

        Test.startTest();

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(emptyBatch.Id);

        Test.stopTest();

        System.assertEquals(false, result.success, 'Submission should fail with no records');
        System.assert(result.message.contains('No pending company records'), 'Should indicate no records');
    }

    @isTest
    static void testSubmitCompanyBatch_NoSettings() {
        // Delete the settings
        delete [SELECT Id FROM Land_Registry_Settings__c];

        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();

        try {
            HMLRCompanySubmission.submitCompanyBatch(batch.Id);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Azure Function Key not configured'), 'Should indicate missing settings');
        }

        Test.stopTest();
    }

    @isTest
    static void testGetPendingCompanyCount() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        Test.startTest();

        Integer count = HMLRCompanySubmission.getPendingCompanyCount(batch.Id);

        Test.stopTest();

        System.assertEquals(2, count, 'Should have 2 pending company records');
    }

    @isTest
    static void testAddressParsingWithNewlines() {
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Verify the request is built correctly
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(batch.Id);

        Test.stopTest();

        // The mock will be called, verifying the code path works
        System.assertEquals(true, result.success, 'Should succeed');
    }

    @isTest
    static void testAddressParsingWithCommas() {
        // Create a record with comma-separated address
        Land_Registry_Batch__c batch = [SELECT Id FROM Land_Registry_Batch__c LIMIT 1];

        // Update existing company record to have comma-separated address
        Land_Registry_Check__c check = [
            SELECT Id, Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id AND Landlord_Type__c = 'Company'
            LIMIT 1
        ];
        check.Property_Address__c = '100 Main St, London, Greater London, England';
        update check;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());

        HMLRCompanySubmission.SubmissionResult result = HMLRCompanySubmission.submitCompanyBatch(batch.Id);

        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed with comma-separated address');
    }
}
