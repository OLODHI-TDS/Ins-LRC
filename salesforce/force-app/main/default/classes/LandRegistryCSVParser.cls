/**
 * @description Parses V+ CSV exports and creates Land Registry Check records
 * Handles company detection and name parsing for individual landlords
 */
public with sharing class LandRegistryCSVParser {

    // Company detection keywords (case-insensitive)
    private static final Set<String> COMPANY_KEYWORDS = new Set<String>{
        'limited', 'ltd', 'lettings', 'holdings', 'property', 'assets',
        'homes', 'housing', 'residential', 'estate', 'estates', 'plc',
        'llp', 'partnership', 'investments', 'management', 'services',
        'group', 'corporation', 'corp', 'inc', 'properties'
    };

    /**
     * @description Result wrapper for CSV parsing operation
     */
    public class ParseResult {
        @AuraEnabled public Id batchId;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer individualCount;
        @AuraEnabled public Integer companyCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public Boolean success;

        public ParseResult() {
            this.errors = new List<String>();
            this.totalRecords = 0;
            this.individualCount = 0;
            this.companyCount = 0;
            this.success = true;
        }
    }

    /**
     * @description Parsed row from CSV
     */
    public class CSVRow {
        public String landlordId;
        public String landlordName;
        public String addressLine1;
        public String town;
        public String county;
        public String postcode;
    }

    /**
     * @description Parse CSV content and create batch with check records
     * @param csvContent The raw CSV content as string
     * @return ParseResult with batch ID and statistics
     */
    @AuraEnabled
    public static ParseResult parseAndCreateRecords(String csvContent) {
        ParseResult result = new ParseResult();

        try {
            // Parse CSV rows
            List<CSVRow> rows = parseCSV(csvContent);

            if (rows.isEmpty()) {
                result.success = false;
                result.errors.add('No valid data rows found in CSV');
                return result;
            }

            // Create batch record
            Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
                Upload_Date__c = DateTime.now(),
                Status__c = 'Pending',
                Total_Records__c = rows.size(),
                Processed_Count__c = 0,
                Matched_Count__c = 0,
                Failed_Count__c = 0
            );
            insert batch;
            result.batchId = batch.Id;

            // Create check records
            List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>();

            for (CSVRow row : rows) {
                Land_Registry_Check__c check = createCheckRecord(row, batch.Id);
                checks.add(check);

                if (check.Landlord_Type__c == 'Company') {
                    result.companyCount++;
                } else {
                    result.individualCount++;
                }
            }

            insert checks;
            result.totalRecords = checks.size();

        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error processing CSV: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Preview CSV without creating records
     * @param csvContent The raw CSV content
     * @return List of preview data for UI display
     */
    @AuraEnabled
    public static List<Map<String, Object>> previewCSV(String csvContent) {
        List<Map<String, Object>> preview = new List<Map<String, Object>>();
        List<CSVRow> rows = parseCSV(csvContent);

        Integer previewLimit = Math.min(rows.size(), 10); // Show first 10 rows

        for (Integer i = 0; i < previewLimit; i++) {
            CSVRow row = rows[i];
            Map<String, Object> previewRow = new Map<String, Object>();

            previewRow.put('landlordId', row.landlordId);
            previewRow.put('landlordName', row.landlordName);
            previewRow.put('landlordType', isCompany(row.landlordName) ? 'Company' : 'Individual');
            previewRow.put('address', buildFullAddress(row));
            previewRow.put('postcode', row.postcode);

            if (!isCompany(row.landlordName)) {
                Map<String, String> nameParts = parseIndividualName(row.landlordName);
                previewRow.put('forename', nameParts.get('forename'));
                previewRow.put('surname', nameParts.get('surname'));
            }

            preview.add(previewRow);
        }

        return preview;
    }

    /**
     * @description Get statistics about the CSV content
     * @param csvContent The raw CSV content
     * @return Map with total, individual, and company counts
     */
    @AuraEnabled
    public static Map<String, Integer> getCSVStats(String csvContent) {
        Map<String, Integer> stats = new Map<String, Integer>{
            'total' => 0,
            'individuals' => 0,
            'companies' => 0
        };

        List<CSVRow> rows = parseCSV(csvContent);
        stats.put('total', rows.size());

        for (CSVRow row : rows) {
            if (isCompany(row.landlordName)) {
                stats.put('companies', stats.get('companies') + 1);
            } else {
                stats.put('individuals', stats.get('individuals') + 1);
            }
        }

        return stats;
    }

    /**
     * @description Parse CSV content into structured rows
     */
    private static List<CSVRow> parseCSV(String csvContent) {
        List<CSVRow> rows = new List<CSVRow>();

        if (String.isBlank(csvContent)) {
            return rows;
        }

        // Split into lines, handling both \r\n and \n
        List<String> lines = csvContent.replace('\r\n', '\n').replace('\r', '\n').split('\n');

        if (lines.size() < 2) {
            return rows; // Need at least header + 1 data row
        }

        // Parse header to find column indices
        String headerLine = lines[0];
        Map<String, Integer> columnIndex = parseHeader(headerLine);

        // Process data rows
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) {
                continue;
            }

            List<String> values = parseCSVLine(line);
            CSVRow row = mapValuesToRow(values, columnIndex);

            if (row != null && String.isNotBlank(row.landlordId)) {
                rows.add(row);
            }
        }

        return rows;
    }

    /**
     * @description Parse header line to get column indices
     */
    private static Map<String, Integer> parseHeader(String headerLine) {
        Map<String, Integer> columnIndex = new Map<String, Integer>();
        List<String> headers = parseCSVLine(headerLine);

        for (Integer i = 0; i < headers.size(); i++) {
            String header = headers[i].toLowerCase().trim();

            // Map various possible header names to our fields
            if (header.contains('landlord') && header.contains('id')) {
                columnIndex.put('landlordId', i);
            } else if (header == 'name' || header == 'landlord name' || header.contains('landlord') && header.contains('name')) {
                columnIndex.put('name', i);
            } else if (header.contains('first line') || header.contains('address1') || header.contains('address 1')) {
                columnIndex.put('addressLine1', i);
            } else if (header.contains('town') || header.contains('city')) {
                columnIndex.put('town', i);
            } else if (header.contains('county')) {
                columnIndex.put('county', i);
            } else if (header.contains('postcode') || header.contains('post code') || header.contains('zip')) {
                columnIndex.put('postcode', i);
            }
        }

        return columnIndex;
    }

    /**
     * @description Parse a single CSV line handling quoted values
     */
    private static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();
        Boolean inQuotes = false;
        String currentValue = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                values.add(currentValue.trim());
                currentValue = '';
            } else {
                currentValue += c;
            }
        }

        // Add last value
        values.add(currentValue.trim());

        return values;
    }

    /**
     * @description Map parsed values to CSVRow object
     */
    private static CSVRow mapValuesToRow(List<String> values, Map<String, Integer> columnIndex) {
        CSVRow row = new CSVRow();

        if (columnIndex.containsKey('landlordId') && columnIndex.get('landlordId') < values.size()) {
            row.landlordId = values[columnIndex.get('landlordId')];
        }
        if (columnIndex.containsKey('name') && columnIndex.get('name') < values.size()) {
            row.landlordName = values[columnIndex.get('name')];
        }
        if (columnIndex.containsKey('addressLine1') && columnIndex.get('addressLine1') < values.size()) {
            row.addressLine1 = values[columnIndex.get('addressLine1')];
        }
        if (columnIndex.containsKey('town') && columnIndex.get('town') < values.size()) {
            row.town = values[columnIndex.get('town')];
        }
        if (columnIndex.containsKey('county') && columnIndex.get('county') < values.size()) {
            row.county = values[columnIndex.get('county')];
        }
        if (columnIndex.containsKey('postcode') && columnIndex.get('postcode') < values.size()) {
            row.postcode = values[columnIndex.get('postcode')];
        }

        return row;
    }

    /**
     * @description Create a Land_Registry_Check__c record from CSV row
     */
    private static Land_Registry_Check__c createCheckRecord(CSVRow row, Id batchId) {
        Land_Registry_Check__c check = new Land_Registry_Check__c();

        check.Batch__c = batchId;
        check.Landlord_ID__c = row.landlordId;
        check.Landlord_Name__c = row.landlordName;
        check.Property_Address__c = buildFullAddress(row);
        check.Property_Postcode__c = row.postcode;
        check.Status__c = 'Pending';

        // Determine landlord type
        if (isCompany(row.landlordName)) {
            check.Landlord_Type__c = 'Company';
            check.Company_Name__c = row.landlordName;
        } else {
            check.Landlord_Type__c = 'Individual';
            Map<String, String> nameParts = parseIndividualName(row.landlordName);
            check.Forename__c = nameParts.get('forename');
            check.Surname__c = nameParts.get('surname');
        }

        return check;
    }

    /**
     * @description Build full address from components
     */
    private static String buildFullAddress(CSVRow row) {
        List<String> parts = new List<String>();

        if (String.isNotBlank(row.addressLine1)) parts.add(row.addressLine1);
        if (String.isNotBlank(row.town)) parts.add(row.town);
        if (String.isNotBlank(row.county)) parts.add(row.county);

        return String.join(parts, '\n');
    }

    /**
     * @description Check if landlord name indicates a company
     */
    @TestVisible
    private static Boolean isCompany(String name) {
        if (String.isBlank(name)) {
            return false;
        }

        String lowerName = name.toLowerCase();

        for (String keyword : COMPANY_KEYWORDS) {
            // Check for keyword as whole word (with word boundaries)
            if (lowerName.contains(' ' + keyword + ' ') ||
                lowerName.contains(' ' + keyword) && lowerName.endsWith(keyword) ||
                lowerName.startsWith(keyword + ' ') ||
                lowerName == keyword) {
                return true;
            }
            // Also check for common patterns like "Ltd" at end
            if (lowerName.endsWith(' ' + keyword) || lowerName.endsWith('.' + keyword)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Parse individual name into forename and surname
     * Handles formats like "John Smith", "Smith, John", "Mr John Smith"
     */
    @TestVisible
    private static Map<String, String> parseIndividualName(String fullName) {
        Map<String, String> result = new Map<String, String>{
            'forename' => '',
            'surname' => ''
        };

        if (String.isBlank(fullName)) {
            return result;
        }

        String name = fullName.trim();

        // Remove common titles
        name = name.replaceAll('(?i)^(mr\\.?|mrs\\.?|ms\\.?|miss|dr\\.?|prof\\.?)\\s+', '');

        // Check for "Surname, Forename" format
        if (name.contains(',')) {
            List<String> parts = name.split(',');
            if (parts.size() >= 2) {
                result.put('surname', parts[0].trim());
                result.put('forename', parts[1].trim());
                return result;
            }
        }

        // Standard "Forename Surname" format
        List<String> parts = name.split('\\s+');
        if (parts.size() >= 2) {
            result.put('forename', parts[0]);
            // Last part is surname, everything in between is middle names (ignore)
            result.put('surname', parts[parts.size() - 1]);
        } else if (parts.size() == 1) {
            // Single name - assume surname
            result.put('surname', parts[0]);
        }

        return result;
    }
}
