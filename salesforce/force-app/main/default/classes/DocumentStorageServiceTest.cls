/**
 * @description Test class for DocumentStorageService
 * Tests document upload, retrieval, listing, and deletion operations
 */
@isTest
private class DocumentStorageServiceTest {

    // Mock HTTP response for successful upload
    private class MockUploadSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => true,
                'BlobPath' => 'batch-123/record-456/NGL123456.pdf',
                'BlobUrl' => 'https://stlandregblob.blob.core.windows.net/title-deeds/batch-123/record-456/NGL123456.pdf',
                'FileSizeBytes' => 12345,
                'UploadedAt' => DateTime.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            }));
            return res;
        }
    }

    // Mock HTTP response for failed upload
    private class MockUploadFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => false,
                'ErrorMessage' => 'Invalid document format'
            }));
            return res;
        }
    }

    // Mock HTTP response for successful URL retrieval
    private class MockGetUrlSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => true,
                'SasUrl' => 'https://stlandregblob.blob.core.windows.net/title-deeds/batch-123/record-456/NGL123456.pdf?sv=2023-01-01&sr=b&sig=xxx',
                'BlobPath' => 'batch-123/record-456/NGL123456.pdf',
                'ExpiresAt' => DateTime.now().addHours(1).formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            }));
            return res;
        }
    }

    // Mock HTTP response for document not found
    private class MockNotFound implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => false,
                'ErrorMessage' => 'Document not found'
            }));
            return res;
        }
    }

    // Mock HTTP response for successful list
    private class MockListSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => true,
                'Documents' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'BlobPath' => 'batch-123/record-456/NGL123456.pdf',
                        'FileName' => 'NGL123456.pdf',
                        'FileSizeBytes' => 12345,
                        'ContentType' => 'application/pdf'
                    },
                    new Map<String, Object>{
                        'BlobPath' => 'batch-123/record-789/NGL789012.pdf',
                        'FileName' => 'NGL789012.pdf',
                        'FileSizeBytes' => 54321,
                        'ContentType' => 'application/pdf'
                    }
                }
            }));
            return res;
        }
    }

    // Mock HTTP response for successful delete
    private class MockDeleteSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'Success' => true,
                'DeletedPath' => 'batch-123/record-456/NGL123456.pdf'
            }));
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        // Create test batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Upload_Date__c = DateTime.now(),
            Status__c = 'Complete',
            Total_Records__c = 2
        );
        insert batch;

        // Create test check records
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();

        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_ID__c = 'LL001',
            Landlord_Name__c = 'Test Landlord',
            Landlord_Type__c = 'Individual',
            Property_Address__c = '123 Test Street\nLondon',
            Property_Postcode__c = 'SW1A 1AA',
            Status__c = 'Matched',
            Title_Number__c = 'NGL123456'
        ));

        checks.add(new Land_Registry_Check__c(
            Batch__c = batch.Id,
            Landlord_ID__c = 'LL002',
            Landlord_Name__c = 'ABC Properties Ltd',
            Landlord_Type__c = 'Company',
            Company_Name__c = 'ABC Properties Ltd',
            Property_Address__c = '456 Business Park\nManchester',
            Property_Postcode__c = 'M1 2AB',
            Status__c = 'Under Review',
            Title_Number__c = 'NGL789012',
            Title_Deed_URL__c = 'batch-123/record-789/NGL789012.pdf'
        ));

        insert checks;

        // Create custom setting for Azure Function configuration
        Land_Registry_Settings__c settings = new Land_Registry_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Azure_Function_Key__c = 'test-key-123',
            Azure_Function_URL__c = 'https://func-landreg-api.azurewebsites.net'
        );
        insert settings;
    }

    @isTest
    static void testUploadDocument_Success() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());

        Test.startTest();
        DocumentStorageService.UploadResult result = DocumentStorageService.uploadDocument(
            'batch-123',
            'record-456',
            'NGL123456',
            EncodingUtil.base64Encode(Blob.valueOf('Test PDF content')),
            'NGL123456.pdf'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Upload should succeed');
        System.assertEquals('batch-123/record-456/NGL123456.pdf', result.blobPath, 'Blob path should match');
        System.assertNotEquals(null, result.blobUrl, 'Blob URL should be populated');
    }

    @isTest
    static void testUploadDocument_MissingParams() {
        Test.startTest();
        DocumentStorageService.UploadResult result = DocumentStorageService.uploadDocument(
            null,
            'record-456',
            'NGL123456',
            'test',
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Upload should fail');
        System.assert(result.errorMessage.contains('required'), 'Error should mention required fields');
    }

    @isTest
    static void testUploadDocument_MissingContent() {
        Test.startTest();
        DocumentStorageService.UploadResult result = DocumentStorageService.uploadDocument(
            'batch-123',
            'record-456',
            'NGL123456',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Upload should fail');
        System.assert(result.errorMessage.contains('required'), 'Error should mention content required');
    }

    @isTest
    static void testUploadDocument_HttpFailure() {
        Test.setMock(HttpCalloutMock.class, new MockUploadFailure());

        Test.startTest();
        DocumentStorageService.UploadResult result = DocumentStorageService.uploadDocument(
            'batch-123',
            'record-456',
            'NGL123456',
            EncodingUtil.base64Encode(Blob.valueOf('Test PDF content')),
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Upload should fail');
        System.assert(result.errorMessage.contains('400'), 'Error should contain HTTP status');
    }

    @isTest
    static void testGetDocumentUrl_ByBlobPath_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGetUrlSuccess());

        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrl(
            'batch-123/record-456/NGL123456.pdf',
            null,
            null,
            null,
            60
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Get URL should succeed');
        System.assertNotEquals(null, result.sasUrl, 'SAS URL should be populated');
        System.assert(result.sasUrl.contains('?'), 'SAS URL should contain query params');
    }

    @isTest
    static void testGetDocumentUrl_ByParams_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGetUrlSuccess());

        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrl(
            null,
            'batch-123',
            'record-456',
            'NGL123456',
            30
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Get URL should succeed');
        System.assertNotEquals(null, result.sasUrl, 'SAS URL should be populated');
    }

    @isTest
    static void testGetDocumentUrl_MissingParams() {
        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrl(
            null,
            'batch-123',
            null,
            null,
            60
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Get URL should fail');
        System.assert(result.errorMessage.contains('required'), 'Error should mention required params');
    }

    @isTest
    static void testGetDocumentUrl_NotFound() {
        Test.setMock(HttpCalloutMock.class, new MockNotFound());

        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrl(
            'nonexistent/path/file.pdf',
            null,
            null,
            null,
            60
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Get URL should fail');
        System.assert(result.errorMessage.contains('not found'), 'Error should indicate not found');
    }

    @isTest
    static void testGetDocumentUrlForRecord_WithTitleDeedUrl() {
        Test.setMock(HttpCalloutMock.class, new MockGetUrlSuccess());

        Land_Registry_Check__c record = [
            SELECT Id
            FROM Land_Registry_Check__c
            WHERE Title_Deed_URL__c != null
            LIMIT 1
        ];

        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrlForRecord(record.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Get URL for record should succeed');
    }

    @isTest
    static void testGetDocumentUrlForRecord_WithTitleNumber() {
        Test.setMock(HttpCalloutMock.class, new MockGetUrlSuccess());

        Land_Registry_Check__c record = [
            SELECT Id
            FROM Land_Registry_Check__c
            WHERE Title_Deed_URL__c = null
            LIMIT 1
        ];

        Test.startTest();
        DocumentStorageService.DocumentUrlResult result = DocumentStorageService.getDocumentUrlForRecord(record.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Get URL for record should succeed');
    }

    @isTest
    static void testListDocuments_Success() {
        Test.setMock(HttpCalloutMock.class, new MockListSuccess());

        Test.startTest();
        DocumentStorageService.DocumentListResult result = DocumentStorageService.listDocuments(
            'batch-123',
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'List should succeed');
        System.assertEquals(2, result.documents.size(), 'Should return 2 documents');
        System.assertEquals('NGL123456.pdf', result.documents[0].fileName, 'First file name should match');
    }

    @isTest
    static void testListDocuments_WithRecordId() {
        Test.setMock(HttpCalloutMock.class, new MockListSuccess());

        Test.startTest();
        DocumentStorageService.DocumentListResult result = DocumentStorageService.listDocuments(
            'batch-123',
            'record-456'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'List should succeed');
    }

    @isTest
    static void testListDocuments_MissingBatchId() {
        Test.startTest();
        DocumentStorageService.DocumentListResult result = DocumentStorageService.listDocuments(
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'List should fail');
        System.assert(result.errorMessage.contains('required'), 'Error should mention required param');
    }

    @isTest
    static void testDeleteDocument_Success() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());

        Test.startTest();
        DocumentStorageService.DeleteResult result = DocumentStorageService.deleteDocument(
            'batch-123/record-456/NGL123456.pdf',
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Delete should succeed');
        System.assertEquals('batch-123/record-456/NGL123456.pdf', result.deletedPath, 'Deleted path should match');
    }

    @isTest
    static void testDeleteDocument_ByParams() {
        Test.setMock(HttpCalloutMock.class, new MockDeleteSuccess());

        Test.startTest();
        DocumentStorageService.DeleteResult result = DocumentStorageService.deleteDocument(
            null,
            'batch-123',
            'record-456',
            'NGL123456'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Delete should succeed');
    }

    @isTest
    static void testDeleteDocument_NotFound() {
        Test.setMock(HttpCalloutMock.class, new MockNotFound());

        Test.startTest();
        DocumentStorageService.DeleteResult result = DocumentStorageService.deleteDocument(
            'nonexistent/path/file.pdf',
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Delete should fail');
        System.assert(result.errorMessage.contains('not found'), 'Error should indicate not found');
    }

    @isTest
    static void testUploadAndLinkDocument_Success() {
        Test.setMock(HttpCalloutMock.class, new MockUploadSuccess());

        Land_Registry_Check__c record = [
            SELECT Id
            FROM Land_Registry_Check__c
            WHERE Landlord_Type__c = 'Individual'
            LIMIT 1
        ];

        Test.startTest();
        DocumentStorageService.UploadResult result = DocumentStorageService.uploadAndLinkDocument(
            record.Id,
            'NGL999999',
            EncodingUtil.base64Encode(Blob.valueOf('Test PDF content'))
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Upload and link should succeed');

        // Verify record was updated
        Land_Registry_Check__c updatedRecord = [
            SELECT Title_Number__c, Title_Deed_URL__c, Status__c
            FROM Land_Registry_Check__c
            WHERE Id = :record.Id
        ];

        System.assertEquals('NGL999999', updatedRecord.Title_Number__c, 'Title number should be updated');
        System.assertNotEquals(null, updatedRecord.Title_Deed_URL__c, 'Title deed URL should be populated');
        System.assertEquals('Under Review', updatedRecord.Status__c, 'Status should be Under Review');
    }
}
