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
    static void testMultipleNamesParsing() {
        // Separate full names with "and" - take first person only
        Map<String, String> result1 = LandRegistryCSVParser.parseIndividualName('Neena Manjeet and Aalok Soni');
        System.assertEquals('Neena', result1.get('forename'), 'Should take first person forename');
        System.assertEquals('Manjeet', result1.get('surname'), 'Should take first person surname');

        // Shared surname with "&"
        Map<String, String> result2 = LandRegistryCSVParser.parseIndividualName('John & Mary Smith');
        System.assertEquals('John', result2.get('forename'), 'Should take first forename');
        System.assertEquals('Smith', result2.get('surname'), 'Should take shared surname from end');

        // Shared surname with titles
        Map<String, String> result3 = LandRegistryCSVParser.parseIndividualName('Mr James & Mrs Sarah Brown');
        System.assertEquals('James', result3.get('forename'), 'Should take first forename after title removal');
        System.assertEquals('Brown', result3.get('surname'), 'Should take shared surname from end');

        // Shared surname with "and"
        Map<String, String> result4 = LandRegistryCSVParser.parseIndividualName('Peter and Jane Wilson');
        System.assertEquals('Peter', result4.get('forename'), 'Should take first forename');
        System.assertEquals('Wilson', result4.get('surname'), 'Should take shared surname from end');

        // Dr titles
        Map<String, String> result5 = LandRegistryCSVParser.parseIndividualName('Dr John Smith & Dr Jane Smith');
        System.assertEquals('John', result5.get('forename'), 'Should take first forename after title removal');
        System.assertEquals('Smith', result5.get('surname'), 'Should take surname from first person');

        // Complex case with duplicated names (like the original issue)
        Map<String, String> result6 = LandRegistryCSVParser.parseIndividualName('Neena Manjeet and Aalok Soni Aalok Soni');
        System.assertEquals('Neena', result6.get('forename'), 'Should take first person forename');
        System.assertEquals('Manjeet', result6.get('surname'), 'Should take first person surname');

        // Surname, Forename format with multiple people
        Map<String, String> result7 = LandRegistryCSVParser.parseIndividualName('Smith, John and Mary');
        System.assertEquals('John', result7.get('forename'), 'Should take first forename only');
        System.assertEquals('Smith', result7.get('surname'), 'Should take surname correctly');
    }

    @isTest
    static void testReparseExistingRecords() {
        // Create a batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Upload_Date__c = DateTime.now(),
            Status__c = 'Pending',
            Total_Records__c = 2
        );
        insert batch;

        // Create records with incorrectly parsed names
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>{
            new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL001',
                Landlord_Name__c = 'Neena Manjeet and Aalok Soni',
                Landlord_Type__c = 'Individual',
                Forename__c = 'Neena',  // Wrong - was taking first word
                Surname__c = 'Soni',     // Wrong - was taking last word
                Property_Address__c = '123 Test Street',
                Property_Postcode__c = 'TE1 1ST',
                Status__c = 'Pending'
            ),
            new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL002',
                Landlord_Name__c = 'John & Mary Smith',
                Landlord_Type__c = 'Individual',
                Forename__c = 'John',    // Correct
                Surname__c = '&',        // Wrong
                Property_Address__c = '456 Test Avenue',
                Property_Postcode__c = 'TE2 2ND',
                Status__c = 'Pending'
            )
        };
        insert checks;

        Test.startTest();
        LandRegistryCSVParser.reparseExistingRecords();
        Test.stopTest();

        // Verify records were updated correctly
        List<Land_Registry_Check__c> updatedChecks = [
            SELECT Landlord_ID__c, Forename__c, Surname__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id
            ORDER BY Landlord_ID__c
        ];

        // First record: "Neena Manjeet and Aalok Soni" → Neena / Manjeet
        System.assertEquals('Neena', updatedChecks[0].Forename__c);
        System.assertEquals('Manjeet', updatedChecks[0].Surname__c);

        // Second record: "John & Mary Smith" → John / Smith
        System.assertEquals('John', updatedChecks[1].Forename__c);
        System.assertEquals('Smith', updatedChecks[1].Surname__c);
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
