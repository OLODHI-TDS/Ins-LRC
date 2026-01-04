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
    static void testUpdateEmailPhoneFromCSV() {
        // Create a batch
        Land_Registry_Batch__c batch = new Land_Registry_Batch__c(
            Upload_Date__c = DateTime.now(),
            Status__c = 'Pending',
            Total_Records__c = 2
        );
        insert batch;

        // Create records without email/phone
        List<Land_Registry_Check__c> checks = new List<Land_Registry_Check__c>{
            new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL001',
                Landlord_Name__c = 'John Smith',
                Landlord_Type__c = 'Individual',
                Property_Address__c = '123 Test Street',
                Property_Postcode__c = 'TE1 1ST',
                Status__c = 'Pending'
            ),
            new Land_Registry_Check__c(
                Batch__c = batch.Id,
                Landlord_ID__c = 'LL002',
                Landlord_Name__c = 'Jane Doe',
                Landlord_Type__c = 'Individual',
                Property_Address__c = '456 Test Avenue',
                Property_Postcode__c = 'TE2 2ND',
                Status__c = 'Pending'
            )
        };
        insert checks;

        // CSV with email and phone data
        String csvContent = 'Landlord ID,Name,Phone,Email\n' +
            'LL001,John Smith,07123456789,john@test.com\n' +
            'LL002,Jane Doe,07987654321,jane@test.com\n' +
            'LL003,Not Found,07111111111,notfound@test.com';

        Test.startTest();
        String result = LandRegistryCSVParser.updateEmailPhoneFromCSV(csvContent);
        Test.stopTest();

        // Verify result message
        System.assert(result.contains('Update Complete'), 'Should show success message');
        System.assert(result.contains('Records updated: 2'), 'Should update 2 records');

        // Verify records were updated correctly
        List<Land_Registry_Check__c> updatedChecks = [
            SELECT Landlord_ID__c, Landlord_Email__c, Landlord_Phone__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :batch.Id
            ORDER BY Landlord_ID__c
        ];

        System.assertEquals('john@test.com', updatedChecks[0].Landlord_Email__c);
        System.assertEquals('07123456789', updatedChecks[0].Landlord_Phone__c);
        System.assertEquals('jane@test.com', updatedChecks[1].Landlord_Email__c);
        System.assertEquals('07987654321', updatedChecks[1].Landlord_Phone__c);
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

    @isTest
    static void testAddressLineCleaning() {
        // Test Room X removal
        System.assertEquals('123 High Street', LandRegistryCSVParser.cleanAddressLine('Room 5 123 High Street'));
        System.assertEquals('456 Oak Avenue', LandRegistryCSVParser.cleanAddressLine('room 12 456 Oak Avenue'));
        System.assertEquals('789 Elm Road', LandRegistryCSVParser.cleanAddressLine('ROOM 3 789 Elm Road'));

        // Test comma is kept (splitting happens before cleaning)
        System.assertEquals('Flat 2, 123 High Street', LandRegistryCSVParser.cleanAddressLine('Flat 2, 123 High Street'));

        // Test hyphens are preserved (important for address numbers like 85-89)
        System.assertEquals('85-89 Plungington Road', LandRegistryCSVParser.cleanAddressLine('85-89 Plungington Road'));
        System.assertEquals('123 High-Street', LandRegistryCSVParser.cleanAddressLine('123 High-Street'));

        // Test periods and apostrophes are removed
        System.assertEquals('Apt 4B, Kings Road', LandRegistryCSVParser.cleanAddressLine('Apt. 4B, King\'s Road'));
        System.assertEquals('St Johns Close', LandRegistryCSVParser.cleanAddressLine('St. John\'s Close'));

        // Test multiple spaces collapsed
        System.assertEquals('123 High Street', LandRegistryCSVParser.cleanAddressLine('123   High   Street'));

        // Test empty and null
        System.assertEquals('', LandRegistryCSVParser.cleanAddressLine(''));
        System.assertEquals('', LandRegistryCSVParser.cleanAddressLine(null));
    }

    @isTest
    static void testPostcodeFormatting() {
        // Standard UK postcodes
        System.assertEquals('SW1A 1AA', LandRegistryCSVParser.formatPostcode('sw1a1aa'));
        System.assertEquals('SW1A 1AA', LandRegistryCSVParser.formatPostcode('SW1A1AA'));
        System.assertEquals('SW1A 1AA', LandRegistryCSVParser.formatPostcode('SW1A 1AA'));
        System.assertEquals('SW1A 1AA', LandRegistryCSVParser.formatPostcode('  sw1a  1aa  '));

        // Various formats
        System.assertEquals('M1 2AB', LandRegistryCSVParser.formatPostcode('m12ab'));
        System.assertEquals('B1 1CD', LandRegistryCSVParser.formatPostcode('B1 1CD'));
        System.assertEquals('LS1 1EF', LandRegistryCSVParser.formatPostcode('ls11ef'));
        System.assertEquals('EC1A 1BB', LandRegistryCSVParser.formatPostcode('ec1a1bb'));

        // Short postcodes (edge case)
        System.assertEquals('AB12', LandRegistryCSVParser.formatPostcode('ab12'));

        // Empty and null
        System.assertEquals('', LandRegistryCSVParser.formatPostcode(''));
        System.assertEquals('', LandRegistryCSVParser.formatPostcode(null));
    }

    @isTest
    static void testAddressWithCommaSplitting() {
        // Create a CSV with comma-separated address parts
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,"Flat 2, 123 High Street",London,Greater London,SW1A 1AA';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');

        // Verify address was split onto separate lines
        Land_Registry_Check__c check = [
            SELECT Property_Address__c, Property_Postcode__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        // Address should have each part on its own line
        System.assert(check.Property_Address__c.contains('\n'), 'Address should contain line breaks');

        // Split and verify parts
        List<String> addressLines = check.Property_Address__c.split('\n');
        System.assert(addressLines.size() >= 2, 'Should have at least 2 address lines');
        System.assertEquals('Flat 2', addressLines[0], 'First line should be Flat 2');
        System.assertEquals('123 High Street', addressLines[1], 'Second line should be 123 High Street');

        // Verify postcode is formatted
        System.assertEquals('SW1A 1AA', check.Property_Postcode__c, 'Postcode should be formatted');
    }

    @isTest
    static void testAddressWithRoomRemoval() {
        // Create a CSV with "Room X" in address
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,Room 5 123 High Street,London,Greater London,sw1a1aa';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');

        // Verify Room X was removed
        Land_Registry_Check__c check = [
            SELECT Property_Address__c, Property_Postcode__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        System.assert(!check.Property_Address__c.containsIgnoreCase('room'), 'Room should be removed from address');
        System.assert(check.Property_Address__c.contains('123 High Street'), 'Address should still contain street');

        // Verify postcode was formatted correctly
        System.assertEquals('SW1A 1AA', check.Property_Postcode__c, 'Postcode should be uppercase with space');
    }

    @isTest
    static void testAddressCleaningOnMultiLineAddress() {
        // Create a CSV with various address formats needing cleaning
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,Unit 5-A Business Park,Manchester,Greater Manchester,m12ab';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c, Property_Postcode__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        // Verify address has each component on its own line
        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(3, lines.size(), 'Should have 3 lines: address, town, county');

        // Verify hyphen is preserved (important for address numbers)
        System.assertEquals('Unit 5-A Business Park', lines[0], 'Hyphen should be preserved');
        System.assertEquals('Manchester', lines[1], 'Town should be on second line');
        System.assertEquals('Greater Manchester', lines[2], 'County should be on third line');

        // Verify postcode formatting
        System.assertEquals('M1 2AB', check.Property_Postcode__c, 'Postcode should be formatted correctly');
    }

    @isTest
    static void testAddressWithCommaSplittingAndHyphen() {
        // Test the specific case: "Flat 2, 85-89 Plungington Road" (with comma)
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,Jeffrey Duddy,"Flat 2, 85-89 Plungington Road",Preston,Lancashire,PR1 1AA';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        // Verify address is split correctly
        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('Flat 2', lines[0], 'First line should be Flat 2');
        System.assertEquals('85-89 Plungington Road', lines[1], 'Second line should preserve hyphen');
        System.assertEquals('Preston', lines[2], 'Third line should be town');
        System.assertEquals('Lancashire', lines[3], 'Fourth line should be county');
    }

    @isTest
    static void testAddressWithFlatPatternNoComma() {
        // Test the real-world case: "Flat 2 85-89 Plungington Road" (NO comma - space separated)
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,Jeffrey Duddy,Flat 2 85-89 Plungington Road,Preston,Lancashire,PR1 7EN';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        // Verify address is split correctly using pattern matching
        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('Flat 2', lines[0], 'First line should be Flat 2');
        System.assertEquals('85-89 Plungington Road', lines[1], 'Second line should be street with hyphen preserved');
        System.assertEquals('Preston', lines[2], 'Third line should be town');
        System.assertEquals('Lancashire', lines[3], 'Fourth line should be county');
    }

    @isTest
    static void testAddressWithUnitPattern() {
        // Test Unit pattern: "Unit 5A 123 Business Park"
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,Unit 5A 123 Business Park,Manchester,Greater Manchester,M1 2AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('Unit 5A', lines[0], 'First line should be Unit 5A');
        System.assertEquals('123 Business Park', lines[1], 'Second line should be street address');
    }

    @isTest
    static void testAddressWithBuildingName() {
        // Test building name pattern: "Flat 9 Canterbury Mansions Lymington Road"
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,Flat 9 Canterbury Mansions Lymington Road,London,Greater London,NW6 1AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(5, lines.size(), 'Should have 5 lines');
        System.assertEquals('Flat 9', lines[0], 'First line should be Flat 9');
        System.assertEquals('Canterbury Mansions', lines[1], 'Second line should be building name');
        System.assertEquals('Lymington Road', lines[2], 'Third line should be street');
        System.assertEquals('London', lines[3], 'Fourth line should be town');
        System.assertEquals('Greater London', lines[4], 'Fifth line should be county');
    }

    @isTest
    static void testAddressWithFloorDesignation() {
        // Test floor designation pattern: "First Floor Flat 28 Pembroke Road"
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,First Floor Flat 28 Pembroke Road,Bristol,Avon,BS8 3AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('First Floor Flat', lines[0], 'First line should be First Floor Flat');
        System.assertEquals('28 Pembroke Road', lines[1], 'Second line should be street address');
        System.assertEquals('Bristol', lines[2], 'Third line should be town');
        System.assertEquals('Avon', lines[3], 'Fourth line should be county');
    }

    @isTest
    static void testAddressWithNumberAndBuildingName() {
        // Test number + building name: "2 Gaynes Park Mansions Coopersale Street"
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,2 Gaynes Park Mansions Coopersale Street,Epping,Essex,CM16 5AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('2 Gaynes Park Mansions', lines[0], 'First line should be building with number');
        System.assertEquals('Coopersale Street', lines[1], 'Second line should be street');
        System.assertEquals('Epping', lines[2], 'Third line should be town');
        System.assertEquals('Essex', lines[3], 'Fourth line should be county');
    }

    @isTest
    static void testAddressWithCourtBuilding() {
        // Test Court building name: "15 Ashdown Court Victoria Road"
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,15 Ashdown Court Victoria Road,Brighton,East Sussex,BN1 3AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('15 Ashdown Court', lines[0], 'First line should be building with number');
        System.assertEquals('Victoria Road', lines[1], 'Second line should be street');
    }

    @isTest
    static void testAddressGroundFloorFlat() {
        // Test Ground Floor Flat pattern
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,Ground Floor Flat 5 High Street,London,Greater London,SW1A 1AA';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(4, lines.size(), 'Should have 4 lines');
        System.assertEquals('Ground Floor Flat', lines[0], 'First line should be Ground Floor Flat');
        System.assertEquals('5 High Street', lines[1], 'Second line should be street address');
    }

    @isTest
    static void testAddressSimpleStreet() {
        // Test simple street address (no pattern to split)
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           'LL001,John Smith,123 High Street,London,Greater London,SW1A 1AA';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        Land_Registry_Check__c check = [
            SELECT Property_Address__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            LIMIT 1
        ];

        List<String> lines = check.Property_Address__c.split('\n');
        System.assertEquals(3, lines.size(), 'Should have 3 lines');
        System.assertEquals('123 High Street', lines[0], 'First line should be full street address');
        System.assertEquals('London', lines[1], 'Second line should be town');
        System.assertEquals('Greater London', lines[2], 'Third line should be county');
    }

    @isTest
    static void testExtractLandlordId() {
        // Test compound landlord ID with 3 parts - should extract middle value
        System.assertEquals('15589', LandRegistryCSVParser.extractLandlordId('8421::15589::53148'));
        System.assertEquals('59550', LandRegistryCSVParser.extractLandlordId('8421::59550::85974'));
        System.assertEquals('12345', LandRegistryCSVParser.extractLandlordId('1::12345::999'));

        // Test with 2 parts - should return second value
        System.assertEquals('12345', LandRegistryCSVParser.extractLandlordId('8421::12345'));

        // Test simple ID without :: delimiter - should return as-is
        System.assertEquals('LL001', LandRegistryCSVParser.extractLandlordId('LL001'));
        System.assertEquals('12345', LandRegistryCSVParser.extractLandlordId('12345'));

        // Test with spaces - should trim
        System.assertEquals('15589', LandRegistryCSVParser.extractLandlordId(' 8421::15589::53148 '));

        // Test empty and null
        System.assertEquals('', LandRegistryCSVParser.extractLandlordId(''));
        System.assertEquals('', LandRegistryCSVParser.extractLandlordId(null));
    }

    @isTest
    static void testLandlordIdExtractionInParsing() {
        // Test that landlord ID is correctly extracted during CSV parsing
        String csvContent = 'Landlord ID,Name,Tenancy First Line,Tenancy Town,Tenancy County,Tenancy Postcode\n' +
                           '8421::15589::53148,John Smith,123 High Street,London,Greater London,SW1A 1AA\n' +
                           '8421::59550::85974,Jane Doe,456 Oak Avenue,Manchester,Greater Manchester,M1 2AB';

        Test.startTest();
        LandRegistryCSVParser.ParseResult result = LandRegistryCSVParser.parseAndCreateRecords(csvContent);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');

        List<Land_Registry_Check__c> checks = [
            SELECT Landlord_ID__c, Landlord_Name__c
            FROM Land_Registry_Check__c
            WHERE Batch__c = :result.batchId
            ORDER BY Landlord_Name__c
        ];

        System.assertEquals(2, checks.size(), 'Should have 2 records');
        // Jane Doe comes first alphabetically
        System.assertEquals('59550', checks[0].Landlord_ID__c, 'Jane Doe landlord ID should be 59550');
        System.assertEquals('15589', checks[1].Landlord_ID__c, 'John Smith landlord ID should be 15589');
    }
}
