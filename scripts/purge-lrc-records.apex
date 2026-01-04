// Purge all Land Registry Check and Batch records for fresh testing
// Run in OmarDev sandbox

// First delete all check records (child)
List<Land_Registry_Check__c> checks = [SELECT Id FROM Land_Registry_Check__c LIMIT 10000];
System.debug('Found ' + checks.size() + ' Land_Registry_Check__c records to delete');

if (!checks.isEmpty()) {
    delete checks;
    System.debug('Deleted ' + checks.size() + ' check records');
}

// Then delete all batch records (parent)
List<Land_Registry_Batch__c> batches = [SELECT Id FROM Land_Registry_Batch__c LIMIT 10000];
System.debug('Found ' + batches.size() + ' Land_Registry_Batch__c records to delete');

if (!batches.isEmpty()) {
    delete batches;
    System.debug('Deleted ' + batches.size() + ' batch records');
}

System.debug('=== PURGE COMPLETE ===');
