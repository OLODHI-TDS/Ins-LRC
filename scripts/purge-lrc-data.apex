// Delete all Land Registry Check records first (child)
List<Land_Registry_Check__c> checks = [SELECT Id FROM Land_Registry_Check__c];
System.debug('Deleting ' + checks.size() + ' Land Registry Check records...');
if (!checks.isEmpty()) {
    delete checks;
}

// Delete all Land Registry Batch records (parent)
List<Land_Registry_Batch__c> batches = [SELECT Id FROM Land_Registry_Batch__c];
System.debug('Deleting ' + batches.size() + ' Land Registry Batch records...');
if (!batches.isEmpty()) {
    delete batches;
}

System.debug('=== PURGE COMPLETE ===');
System.debug('Checks deleted: ' + checks.size());
System.debug('Batches deleted: ' + batches.size());
