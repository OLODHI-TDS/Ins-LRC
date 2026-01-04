// Fix existing Landlord IDs by extracting middle value from compound format
// Format: "8421::15589::53148" -> "15589"

List<Land_Registry_Check__c> records = [
    SELECT Id, Landlord_ID__c
    FROM Land_Registry_Check__c
    WHERE Landlord_ID__c LIKE '%::%'
];

System.debug('Found ' + records.size() + ' records with compound Landlord IDs');

List<Land_Registry_Check__c> toUpdate = new List<Land_Registry_Check__c>();

for (Land_Registry_Check__c record : records) {
    String rawId = record.Landlord_ID__c;

    if (String.isNotBlank(rawId) && rawId.contains('::')) {
        List<String> parts = rawId.split('::');
        String extractedId;

        if (parts.size() >= 3) {
            extractedId = parts[1].trim();
        } else if (parts.size() == 2) {
            extractedId = parts[1].trim();
        } else {
            continue;
        }

        if (extractedId != rawId) {
            System.debug('Updating: ' + rawId + ' -> ' + extractedId);
            record.Landlord_ID__c = extractedId;
            toUpdate.add(record);
        }
    }
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
}

System.debug('=== UPDATE COMPLETE ===');
System.debug('Records updated: ' + toUpdate.size());
