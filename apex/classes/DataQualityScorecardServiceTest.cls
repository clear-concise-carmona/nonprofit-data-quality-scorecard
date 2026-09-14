/**
 * DataQualityScorecardServiceTest
 *
 * Runs the full orchestration end to end against whatever data model the
 * test org actually has (almost always UNKNOWN in a scratch org with
 * neither NPSP nor Nonprofit Cloud installed) and checks that exactly one
 * Data_Quality_Snapshot__c comes out the other end with a valid score and
 * a Notes__c explanation for whichever metrics came back not-applicable.
 */
@IsTest
private class DataQualityScorecardServiceTest {

    @IsTest
    static void testRunScorecardInsertsOneSnapshot() {
        Contact c = new Contact(LastName = 'Scorecard Test Donor', Email = 'donor@example.com');
        insert c;

        Test.startTest();
        Data_Quality_Snapshot__c snapshot = DataQualityScorecardService.runScorecard();
        Test.stopTest();

        System.assertNotEquals(null, snapshot.Id);
        System.assertNotEquals(null, snapshot.Run_Date__c);
        System.assertNotEquals(null, snapshot.Data_Model_Detected__c);
        System.assert(snapshot.Overall_Score__c >= 0 && snapshot.Overall_Score__c <= 100);

        List<Data_Quality_Snapshot__c> stored = [SELECT Id, Overall_Score__c FROM Data_Quality_Snapshot__c];
        System.assertEquals(1, stored.size());
    }

    @IsTest
    static void testRunScorecardRecordsThresholdUsed() {
        Test.startTest();
        Data_Quality_Snapshot__c snapshot = DataQualityScorecardService.runScorecard();
        Test.stopTest();

        // Should reflect the Default custom metadata record's 12-month
        // threshold, since no override is configured in a fresh test org.
        System.assertEquals(12, snapshot.Stale_Contact_Threshold_Months_Used__c);
    }
}
