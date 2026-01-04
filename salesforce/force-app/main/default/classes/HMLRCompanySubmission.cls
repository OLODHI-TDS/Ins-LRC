/**
 * @description Handles submission of company landlord records to HMLR via Azure Function
 * Generates JSON payload and sends to SendCompanyBatchToHMLR Azure Function
 */
public with sharing class HMLRCompanySubmission {

    // Default Azure Function endpoint (can be overridden via Custom Setting)
    private static final String DEFAULT_AZURE_FUNCTION_URL = 'https://func-landreg-api.azurewebsites.net';
    private static final String FUNCTION_PATH = '/api/sendcompanybatchtohmlr';

    /**
     * @description Submit company records from a batch to HMLR
     * @param batchId The batch containing company records to submit
     * @return SubmissionResult with success/failure details
     */
    @AuraEnabled
    public static SubmissionResult submitCompanyBatch(Id batchId) {
        SubmissionResult result = new SubmissionResult();

        try {
            // Get batch details
            Land_Registry_Batch__c batch = [
                SELECT Id, Name, Status__c
                FROM Land_Registry_Batch__c
                WHERE Id = :batchId
                LIMIT 1
            ];

            // Get company records that are pending
            List<Land_Registry_Check__c> companyRecords = [
                SELECT Id, Name, Landlord_ID__c, Landlord_Name__c, Company_Name__c,
                       Forename__c, Surname__c, Property_Address__c, Property_Postcode__c,
                       Address_Line_1__c, Address_Line_2__c, Address_Line_3__c,
                       Address_Line_4__c, Address_Line_5__c, Status__c
                FROM Land_Registry_Check__c
                WHERE Batch__c = :batchId
                  AND Landlord_Type__c = 'Company'
                  AND Status__c = 'Pending'
                ORDER BY Name
            ];

            if (companyRecords.isEmpty()) {
                result.success = false;
                result.message = 'No pending company records found in this batch.';
                return result;
            }

            // Build request payload
            CompanyBatchRequest request = buildRequest(batch, companyRecords);

            // Call Azure Function
            AzureFunctionResponse azureResponse = callAzureFunction(request);

            if (azureResponse.success) {
                // Update records to Submitted status
                updateRecordsToSubmitted(companyRecords);

                result.success = true;
                result.message = 'Successfully submitted ' + companyRecords.size() + ' company records to HMLR.';
                result.recordsSubmitted = companyRecords.size();
                result.emailMessageId = azureResponse.emailMessageId;
                result.recipientEmail = azureResponse.recipientEmail;
            } else {
                result.success = false;
                result.message = 'Azure Function error: ' + azureResponse.errorMessage;
            }

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'HMLRCompanySubmission error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Get count of pending company records for a batch
     * @param batchId The batch to check
     * @return Count of pending company records
     */
    @AuraEnabled(cacheable=true)
    public static Integer getPendingCompanyCount(Id batchId) {
        return [
            SELECT COUNT()
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batchId
              AND Landlord_Type__c = 'Company'
              AND Status__c = 'Pending'
        ];
    }

    /**
     * @description Build the request payload for Azure Function
     */
    private static CompanyBatchRequest buildRequest(Land_Registry_Batch__c batch, List<Land_Registry_Check__c> records) {
        CompanyBatchRequest request = new CompanyBatchRequest();
        request.batchId = batch.Id;
        request.batchName = batch.Name;
        request.records = new List<CompanyLandlordRecord>();

        for (Land_Registry_Check__c rec : records) {
            CompanyLandlordRecord record = new CompanyLandlordRecord();
            record.recordId = rec.Id;
            record.customerRef = rec.Landlord_ID__c;
            record.companyName = rec.Company_Name__c != null ? rec.Company_Name__c : '';
            record.forename = rec.Forename__c != null ? rec.Forename__c : '';
            record.surname = rec.Surname__c != null ? rec.Surname__c : '';

            // Use split address fields if available, otherwise parse from full address
            if (rec.Address_Line_1__c != null) {
                record.address1 = rec.Address_Line_1__c;
                record.address2 = rec.Address_Line_2__c != null ? rec.Address_Line_2__c : '';
                record.address3 = rec.Address_Line_3__c != null ? rec.Address_Line_3__c : '';
                record.address4 = rec.Address_Line_4__c != null ? rec.Address_Line_4__c : '';
                record.address5 = rec.Address_Line_5__c != null ? rec.Address_Line_5__c : '';
            } else {
                // Parse from full address if split fields not populated
                List<String> addressLines = parseAddress(rec.Property_Address__c);
                record.address1 = addressLines.size() > 0 ? addressLines[0] : '';
                record.address2 = addressLines.size() > 1 ? addressLines[1] : '';
                record.address3 = addressLines.size() > 2 ? addressLines[2] : '';
                record.address4 = addressLines.size() > 3 ? addressLines[3] : '';
                record.address5 = addressLines.size() > 4 ? addressLines[4] : '';
            }

            record.postcode = rec.Property_Postcode__c != null ? rec.Property_Postcode__c : '';

            request.records.add(record);
        }

        return request;
    }

    /**
     * @description Parse full address into lines
     */
    private static List<String> parseAddress(String fullAddress) {
        List<String> lines = new List<String>();
        if (String.isBlank(fullAddress)) {
            return lines;
        }

        // Split by newline or comma
        String[] parts;
        if (fullAddress.contains('\n')) {
            parts = fullAddress.split('\n');
        } else {
            parts = fullAddress.split(',');
        }

        for (String part : parts) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                lines.add(trimmed);
            }
        }

        return lines;
    }

    /**
     * @description Call the Azure Function
     */
    private static AzureFunctionResponse callAzureFunction(CompanyBatchRequest request) {
        AzureFunctionResponse response = new AzureFunctionResponse();

        // Get settings
        Land_Registry_Settings__c settings = getSettings();
        String baseUrl = String.isNotBlank(settings.Azure_Function_URL__c) ?
            settings.Azure_Function_URL__c : DEFAULT_AZURE_FUNCTION_URL;
        String functionKey = settings.Azure_Function_Key__c;

        String endpoint = baseUrl + FUNCTION_PATH + '?code=' + functionKey;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000); // 2 minute timeout

        // Serialize request to JSON
        String jsonBody = JSON.serialize(request);
        req.setBody(jsonBody);

        System.debug('Calling Azure Function at: ' + baseUrl + FUNCTION_PATH);
        System.debug('Payload: ' + jsonBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Azure Function response status: ' + res.getStatusCode());
        System.debug('Azure Function response body: ' + res.getBody());

        if (res.getStatusCode() == 200) {
            // Parse response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            response.success = (Boolean) responseMap.get('Success');
            response.emailMessageId = (String) responseMap.get('EmailMessageId');
            response.recordsProcessed = responseMap.get('RecordsProcessed') != null ?
                Integer.valueOf(responseMap.get('RecordsProcessed')) : 0;
            response.recipientEmail = (String) responseMap.get('RecipientEmail');

            if (!response.success) {
                response.errorMessage = (String) responseMap.get('ErrorMessage');
            }
        } else {
            response.success = false;
            response.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
        }

        return response;
    }

    /**
     * @description Get Land Registry Settings with validation
     */
    private static Land_Registry_Settings__c getSettings() {
        Land_Registry_Settings__c settings = Land_Registry_Settings__c.getOrgDefaults();

        if (settings == null || String.isBlank(settings.Azure_Function_Key__c)) {
            throw new AuraHandledException(
                'Azure Function Key not configured. Please set up Land_Registry_Settings__c custom setting with the Azure_Function_Key__c value.'
            );
        }

        return settings;
    }

    /**
     * @description Update records to Submitted status
     */
    private static void updateRecordsToSubmitted(List<Land_Registry_Check__c> records) {
        for (Land_Registry_Check__c rec : records) {
            rec.Status__c = 'Submitted to HMLR';
            rec.HMLR_Response_Date__c = DateTime.now();
        }
        update records;
    }

    // Request/Response wrapper classes

    public class CompanyBatchRequest {
        public String batchId;
        public String batchName;
        public List<CompanyLandlordRecord> records;
    }

    public class CompanyLandlordRecord {
        public String recordId;
        public String customerRef;
        public String companyName;
        public String forename;
        public String surname;
        public String address1;
        public String address2;
        public String address3;
        public String address4;
        public String address5;
        public String postcode;
    }

    public class AzureFunctionResponse {
        public Boolean success;
        public String emailMessageId;
        public Integer recordsProcessed;
        public String errorMessage;
        public String recipientEmail;
    }

    public class SubmissionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer recordsSubmitted;
        @AuraEnabled public String emailMessageId;
        @AuraEnabled public String recipientEmail;
    }
}
