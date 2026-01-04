/**
 * @description Service class for document storage operations (title deed PDFs)
 * Handles upload, retrieval, and management of documents in Azure Blob Storage
 */
public with sharing class DocumentStorageService {

    // Default Azure Function endpoint (can be overridden via Custom Setting)
    private static final String DEFAULT_AZURE_FUNCTION_URL = 'https://func-landreg-api.azurewebsites.net';
    private static final String UPLOAD_FUNCTION_PATH = '/api/uploaddocument';
    private static final String GET_URL_FUNCTION_PATH = '/api/getdocumenturl';
    private static final String LIST_FUNCTION_PATH = '/api/listdocuments';
    private static final String DELETE_FUNCTION_PATH = '/api/deletedocument';

    /**
     * @description Upload a PDF document to Azure Blob Storage
     * @param batchId The Salesforce Batch ID
     * @param recordId The Salesforce Check Record ID
     * @param titleNumber The HMLR title number
     * @param documentBase64 Base64-encoded PDF content
     * @param fileName Original filename (optional)
     * @return UploadResult with success/failure and blob URL
     */
    @AuraEnabled
    public static UploadResult uploadDocument(
        String batchId,
        String recordId,
        String titleNumber,
        String documentBase64,
        String fileName
    ) {
        UploadResult result = new UploadResult();

        try {
            // Validate inputs
            if (String.isBlank(batchId) || String.isBlank(recordId) || String.isBlank(titleNumber)) {
                result.success = false;
                result.errorMessage = 'BatchId, RecordId, and TitleNumber are required';
                return result;
            }

            if (String.isBlank(documentBase64)) {
                result.success = false;
                result.errorMessage = 'Document content is required';
                return result;
            }

            // Build request
            Map<String, Object> requestBody = new Map<String, Object>{
                'BatchId' => batchId,
                'RecordId' => recordId,
                'TitleNumber' => titleNumber,
                'DocumentBase64' => documentBase64,
                'ContentType' => 'application/pdf'
            };

            if (String.isNotBlank(fileName)) {
                requestBody.put('FileName', fileName);
            }

            // Call Azure Function
            HttpResponse response = callAzureFunction(UPLOAD_FUNCTION_PATH, 'POST', JSON.serialize(requestBody));

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                result.success = (Boolean) responseMap.get('Success');
                result.blobPath = (String) responseMap.get('BlobPath');
                result.blobUrl = (String) responseMap.get('BlobUrl');
                result.fileSizeBytes = responseMap.get('FileSizeBytes') != null ?
                    Long.valueOf(String.valueOf(responseMap.get('FileSizeBytes'))) : null;

                if (!result.success) {
                    result.errorMessage = (String) responseMap.get('ErrorMessage');
                }
            } else {
                result.success = false;
                result.errorMessage = 'HTTP ' + response.getStatusCode() + ': ' + response.getBody();
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'DocumentStorageService.uploadDocument error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Get a time-limited SAS URL for viewing a document
     * @param blobPath Full blob path (or use batch/record/title params)
     * @param batchId Salesforce Batch ID (alternative to blobPath)
     * @param recordId Salesforce Check Record ID (alternative to blobPath)
     * @param titleNumber HMLR title number (alternative to blobPath)
     * @param expiryMinutes How long the URL should be valid (default: 60)
     * @return DocumentUrlResult with SAS URL
     */
    @AuraEnabled
    public static DocumentUrlResult getDocumentUrl(
        String blobPath,
        String batchId,
        String recordId,
        String titleNumber,
        Integer expiryMinutes
    ) {
        DocumentUrlResult result = new DocumentUrlResult();

        try {
            // Build request
            Map<String, Object> requestBody = new Map<String, Object>();

            if (String.isNotBlank(blobPath)) {
                requestBody.put('BlobPath', blobPath);
            } else if (String.isNotBlank(batchId) && String.isNotBlank(recordId) && String.isNotBlank(titleNumber)) {
                requestBody.put('BatchId', batchId);
                requestBody.put('RecordId', recordId);
                requestBody.put('TitleNumber', titleNumber);
            } else {
                result.success = false;
                result.errorMessage = 'Either BlobPath or (BatchId, RecordId, TitleNumber) are required';
                return result;
            }

            if (expiryMinutes != null && expiryMinutes > 0) {
                requestBody.put('ExpiryMinutes', expiryMinutes);
            }

            // Call Azure Function
            HttpResponse response = callAzureFunction(GET_URL_FUNCTION_PATH, 'POST', JSON.serialize(requestBody));

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                result.success = (Boolean) responseMap.get('Success');
                result.sasUrl = (String) responseMap.get('SasUrl');
                result.blobPath = (String) responseMap.get('BlobPath');

                String expiresAtStr = (String) responseMap.get('ExpiresAt');
                if (String.isNotBlank(expiresAtStr)) {
                    result.expiresAt = DateTime.valueOf(expiresAtStr.replace('T', ' ').substring(0, 19));
                }

                if (!result.success) {
                    result.errorMessage = (String) responseMap.get('ErrorMessage');
                }
            } else if (response.getStatusCode() == 404) {
                result.success = false;
                result.errorMessage = 'Document not found';
            } else {
                result.success = false;
                result.errorMessage = 'HTTP ' + response.getStatusCode() + ': ' + response.getBody();
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'DocumentStorageService.getDocumentUrl error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Convenience method to get document URL by record ID
     * Looks up the record to get batch ID and title number
     * @param checkRecordId The Land_Registry_Check__c record ID
     * @return DocumentUrlResult with SAS URL
     */
    @AuraEnabled
    public static DocumentUrlResult getDocumentUrlForRecord(Id checkRecordId) {
        try {
            // Get record details
            Land_Registry_Check__c record = [
                SELECT Id, Batch__c, Title_Number__c, Title_Deed_URL__c
                FROM Land_Registry_Check__c
                WHERE Id = :checkRecordId
                LIMIT 1
            ];

            // If we have a stored blob path in Title_Deed_URL__c, use it
            if (String.isNotBlank(record.Title_Deed_URL__c)) {
                // Extract blob path from full URL if needed
                String blobPath = record.Title_Deed_URL__c;
                if (blobPath.contains('title-deeds/')) {
                    blobPath = blobPath.substringAfter('title-deeds/');
                }
                return getDocumentUrl(blobPath, null, null, null, 60);
            }

            // Otherwise construct from record details
            if (String.isBlank(record.Title_Number__c)) {
                DocumentUrlResult result = new DocumentUrlResult();
                result.success = false;
                result.errorMessage = 'No title number found for this record';
                return result;
            }

            return getDocumentUrl(null, record.Batch__c, checkRecordId, record.Title_Number__c, 60);

        } catch (Exception e) {
            DocumentUrlResult result = new DocumentUrlResult();
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            return result;
        }
    }

    /**
     * @description List all documents for a batch or record
     * @param batchId The batch to list documents for
     * @param recordId Optional: specific record to filter by
     * @return DocumentListResult with list of documents
     */
    @AuraEnabled
    public static DocumentListResult listDocuments(String batchId, String recordId) {
        DocumentListResult result = new DocumentListResult();

        try {
            if (String.isBlank(batchId)) {
                result.success = false;
                result.errorMessage = 'BatchId is required';
                return result;
            }

            // Build query string
            String queryParams = '?batchId=' + EncodingUtil.urlEncode(batchId, 'UTF-8');
            if (String.isNotBlank(recordId)) {
                queryParams += '&recordId=' + EncodingUtil.urlEncode(recordId, 'UTF-8');
            }

            // Call Azure Function
            HttpResponse response = callAzureFunction(LIST_FUNCTION_PATH + queryParams, 'GET', null);

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                result.success = (Boolean) responseMap.get('Success');

                if (result.success) {
                    result.documents = new List<DocumentInfo>();
                    List<Object> docList = (List<Object>) responseMap.get('Documents');

                    if (docList != null) {
                        for (Object doc : docList) {
                            Map<String, Object> docMap = (Map<String, Object>) doc;
                            DocumentInfo info = new DocumentInfo();
                            info.blobPath = (String) docMap.get('BlobPath');
                            info.fileName = (String) docMap.get('FileName');
                            info.fileSizeBytes = docMap.get('FileSizeBytes') != null ?
                                Long.valueOf(String.valueOf(docMap.get('FileSizeBytes'))) : 0;
                            info.contentType = (String) docMap.get('ContentType');
                            result.documents.add(info);
                        }
                    }
                } else {
                    result.errorMessage = (String) responseMap.get('ErrorMessage');
                }
            } else {
                result.success = false;
                result.errorMessage = 'HTTP ' + response.getStatusCode() + ': ' + response.getBody();
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'DocumentStorageService.listDocuments error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Delete a document from blob storage
     * @param blobPath Full blob path (or use batch/record/title params)
     * @param batchId Salesforce Batch ID (alternative to blobPath)
     * @param recordId Salesforce Check Record ID (alternative to blobPath)
     * @param titleNumber HMLR title number (alternative to blobPath)
     * @return DeleteResult with success/failure
     */
    @AuraEnabled
    public static DeleteResult deleteDocument(
        String blobPath,
        String batchId,
        String recordId,
        String titleNumber
    ) {
        DeleteResult result = new DeleteResult();

        try {
            // Build request
            Map<String, Object> requestBody = new Map<String, Object>();

            if (String.isNotBlank(blobPath)) {
                requestBody.put('BlobPath', blobPath);
            } else if (String.isNotBlank(batchId) && String.isNotBlank(recordId) && String.isNotBlank(titleNumber)) {
                requestBody.put('BatchId', batchId);
                requestBody.put('RecordId', recordId);
                requestBody.put('TitleNumber', titleNumber);
            } else {
                result.success = false;
                result.errorMessage = 'Either BlobPath or (BatchId, RecordId, TitleNumber) are required';
                return result;
            }

            // Call Azure Function
            HttpResponse response = callAzureFunction(DELETE_FUNCTION_PATH, 'DELETE', JSON.serialize(requestBody));

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                result.success = (Boolean) responseMap.get('Success');
                result.deletedPath = (String) responseMap.get('DeletedPath');
            } else if (response.getStatusCode() == 404) {
                result.success = false;
                result.errorMessage = 'Document not found';
            } else {
                result.success = false;
                result.errorMessage = 'HTTP ' + response.getStatusCode() + ': ' + response.getBody();
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'DocumentStorageService.deleteDocument error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Upload document and update the Land_Registry_Check__c record
     * @param checkRecordId The record to update
     * @param titleNumber The title number
     * @param documentBase64 Base64-encoded PDF content
     * @return UploadResult
     */
    @AuraEnabled
    public static UploadResult uploadAndLinkDocument(
        Id checkRecordId,
        String titleNumber,
        String documentBase64
    ) {
        UploadResult result = new UploadResult();

        try {
            // Get record to find batch ID
            Land_Registry_Check__c record = [
                SELECT Id, Batch__c
                FROM Land_Registry_Check__c
                WHERE Id = :checkRecordId
                LIMIT 1
            ];

            // Upload the document
            result = uploadDocument(
                record.Batch__c,
                checkRecordId,
                titleNumber,
                documentBase64,
                titleNumber + '.pdf'
            );

            // If successful, update the record with the URL and title number
            if (result.success) {
                record.Title_Number__c = titleNumber;
                record.Title_Deed_URL__c = result.blobPath;
                record.Status__c = 'Under Review';
                update record;
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'DocumentStorageService.uploadAndLinkDocument error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Call Azure Function with standard configuration
     */
    private static HttpResponse callAzureFunction(String functionPath, String method, String body) {
        Land_Registry_Settings__c settings = getSettings();
        String baseUrl = String.isNotBlank(settings.Azure_Function_URL__c) ?
            settings.Azure_Function_URL__c : DEFAULT_AZURE_FUNCTION_URL;
        String functionKey = settings.Azure_Function_Key__c;

        // Add function key to query string
        String separator = functionPath.contains('?') ? '&' : '?';
        String endpoint = baseUrl + functionPath + separator + 'code=' + functionKey;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setTimeout(120000); // 2 minute timeout

        if (method != 'GET' && String.isNotBlank(body)) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }

        System.debug('Calling Azure Function: ' + method + ' ' + baseUrl + functionPath);

        Http http = new Http();
        return http.send(req);
    }

    /**
     * @description Get Land Registry Settings
     */
    private static Land_Registry_Settings__c getSettings() {
        Land_Registry_Settings__c settings = Land_Registry_Settings__c.getOrgDefaults();

        if (settings == null || String.isBlank(settings.Azure_Function_Key__c)) {
            throw new AuraHandledException(
                'Azure Function Key not configured. Please set up Land_Registry_Settings__c custom setting.'
            );
        }

        return settings;
    }

    // Result wrapper classes

    public class UploadResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String blobPath;
        @AuraEnabled public String blobUrl;
        @AuraEnabled public Long fileSizeBytes;
        @AuraEnabled public String errorMessage;
    }

    public class DocumentUrlResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String sasUrl;
        @AuraEnabled public String blobPath;
        @AuraEnabled public DateTime expiresAt;
        @AuraEnabled public String errorMessage;
    }

    public class DocumentListResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<DocumentInfo> documents;
        @AuraEnabled public String errorMessage;
    }

    public class DocumentInfo {
        @AuraEnabled public String blobPath;
        @AuraEnabled public String fileName;
        @AuraEnabled public Long fileSizeBytes;
        @AuraEnabled public String contentType;
    }

    public class DeleteResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String deletedPath;
        @AuraEnabled public String errorMessage;
    }
}
