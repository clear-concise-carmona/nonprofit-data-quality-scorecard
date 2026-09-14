/**
 * DataQualityScorecardSchedulerTest
 *
 * Confirms the Schedulable wrapper actually invokes the scorecard - not
 * just that System.schedule() accepts the cron expression.
 */
@IsTest
private class DataQualityScorecardSchedulerTest {

    @IsTest
    static void testScheduledRunInsertsSnapshot() {
        Test.startTest();
        System.schedule('Test Data Quality Scorecard', '0 0 6 ? * MON', new DataQualityScorecardScheduler());
        Test.stopTest();

        List<Data_Quality_Snapshot__c> snapshots = [SELECT Id FROM Data_Quality_Snapshot__c];
        System.assertEquals(1, snapshots.size());
    }
}
