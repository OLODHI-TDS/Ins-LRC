/**
 * @description Trigger on Land_Registry_Check__c to maintain parent batch rollup counts
 */
trigger LandRegistryCheckTrigger on Land_Registry_Check__c (after insert, after update, after delete, after undelete) {

    if (Trigger.isAfter) {
        List<Land_Registry_Check__c> records = Trigger.isDelete ? Trigger.old : Trigger.new;
        Map<Id, Land_Registry_Check__c> oldMap = Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap;

        LandRegistryBatchRollupHandler.updateBatchCounts(records, oldMap);
    }
}
