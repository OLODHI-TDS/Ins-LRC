/**
 * @description Test class for LandRegistryCSVParser
 */
@isTest
private class LandRegistryCSVParserTest {

    private static String getTestCSV() {
        return 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
               'LL001,John Smith,123 High Street,London,Greater London,SW1A 1AA\n' +
               'LL002,ABC Properties Ltd,45 Business Park,Manchester,Greater Manchester,M1 2AB\n' +
               'LL003,Jane Doe,78 Oak Avenue,Birmingham,West Midlands,B1 1CD\n' +
               'LL004,Smith Holdings Limited,99 Commerce Street,Leeds,West Yorkshire,LS1 1EF\n' +
               'LL005,Robert Johnson,12 Elm Road,Bristol,Avon,BS1 2GH';
    }

    @isTest
    static void testParseAndCreateRecords() {
        String csvContent = getTestCSV();

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
        System.assertNotEquals(null, result.batchId, 'Batch ID should be set');
        System.assertEquals(5, result.totalRecords, 'Should have 5 total records');
        System.assertEquals(3, result.individualCount, 'Should have 3 individuals');
        System.assertEquals(2, result.companyCount, 'Should have 2 companies');

        // Verify batch was created
        Land_Registry_Batch__c batch = [
            SELECT Id, Status__c, Total_Records__c
            FROM Land_Registry_Batch__c
            WHERE Id = :result.batchId
        ];
        System.assertEquals('Pending', batch.Status__c);
        System.assertEquals(5, batch.Total_Records__c);

        // Verify check records
        List<Land_Registry_Check__c> checks = [
            SELECT Id, Landlord_ID__c, Landlord_Name__c, Landlord_Type__c,
                   Forename__c, Surname__c, Company_Name__c, Property_Postcode__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            ORDER BY Landlord_ID__c
        ];
        System.assertEquals(5, checks.size());

        // Check first individual
        System.assertEquals('LL001', checks[0].Landlord_ID__c);
        System.assertEquals('Individual', checks[0].Landlord_Type__c);
        System.assertEquals('John', checks[0].Forename__c);
        System.assertEquals('Smith', checks[0].Surname__c);

        // Check first company
        System.assertEquals('LL002', checks[1].Landlord_ID__c);
        System.assertEquals('Company', checks[1].Landlord_Type__c);
        System.assertEquals('ABC Properties Ltd', checks[1].Company_Name__c);
    }

    @isTest
    static void testPreviewCSV() {
        String csvContent = getTestCSV();

        Test.startTest();
        List<Map<String, Object>> preview = LandRegistryCSVParser.previewCSV(csvContent);
        Test.stopTest();

        System.assertEquals(5, preview.size(), 'Should have 5 preview rows');

        // Check first row
        Map<String, Object> firstRow = preview[0];
        System.assertEquals('LL001', firstRow.get('landlordId'));
        System.assertEquals('Individual', firstRow.get('landlordType'));
        System.assertEquals('John', firstRow.get('forename'));
        System.assertEquals('Smith', firstRow.get('surname'));
    }

    @isTest
    static void testGetCSVStats() {
        String csvContent = getTestCSV();

        Test.startTest();
        Map<String, Integer> stats = LandRegistryCSVParser.getCSVStats(csvContent);
        Test.stopTest();

        System.assertEquals(5, stats.get('total'));
        System.assertEquals(3, stats.get('individuals'));
        System.assertEquals(2, stats.get('companies'));
    }

    @isTest
    static void testCompanyDetection() {
        // Test various company name formats
        System.assertEquals(true, LandRegistryCSVParser.isCompany('ABC Properties Ltd'));
        System.assertEquals(true, LandRegistryCSVParser.isCompany('Smith Holdings Limited'));
        System.assertEquals(true, LandRegistryCSVParser.isCompany('Jones Lettings'));
        System.assertEquals(true, LandRegistryCSVParser.isCompany('Residential Estates Ltd'));
        System.assertEquals(true, LandRegistryCSVParser.isCompany('Housing Assets PLC'));

        // Test individual names (should NOT be detected as company)
        System.assertEquals(false, LandRegistryCSVParser.isCompany('John Smith'));
        System.assertEquals(false, LandRegistryCSVParser.isCompany('Jane Doe'));
        System.assertEquals(false, LandRegistryCSVParser.isCompany('Robert Johnson'));
    }

    @isTest
    static void testNameParsing() {
        // Standard format
        Map<String, String> result1 = LandRegistryCSVParser.parseIndividualName('John Smith');
        System.assertEquals('John', result1.get('forename'));
        System.assertEquals('Smith', result1.get('surname'));

        // With title
        Map<String, String> result2 = LandRegistryCSVParser.parseIndividualName('Mr. John Smith');
        System.assertEquals('John', result2.get('forename'));
        System.assertEquals('Smith', result2.get('surname'));

        // Surname, Forename format
        Map<String, String> result3 = LandRegistryCSVParser.parseIndividualName('Smith, John');
        System.assertEquals('John', result3.get('forename'));
        System.assertEquals('Smith', result3.get('surname'));

        // With middle name
        Map<String, String> result4 = LandRegistryCSVParser.parseIndividualName('John William Smith');
        System.assertEquals('John', result4.get('forename'));
        System.assertEquals('Smith', result4.get('surname'));
    }

    @isTest
    static void testEmptyCSV() {
        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords('');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.errors.size() > 0);
    }

    @isTest
    static void testHeaderOnlyCSV() {
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        System.assertEquals(false, result.success);
    }

    @isTest
    static void testQuotedValues() {
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,"Smith, John","123 High Street, Flat 2",London,Greater London,SW1A 1AA';

        Test.startTest();
        List<Map<String, Object>> preview = LandRegistryCSVParser.previewCSV(csvContent);
        Test.stopTest();

        System.assertEquals(1, preview.size());
        System.assertEquals('Smith, John', preview[0].get('landlordName'));
    }
}
