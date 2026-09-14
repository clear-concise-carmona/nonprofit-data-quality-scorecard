/**
 * DataQualityDashboardControllerTest
 */
@IsTest
private class DataQualityDashboardControllerTest {

    @IsTest
    static void testGetLatestSnapshotWithNoData() {
        Test.startTest();
        Data_Quality_Snapshot__c result = DataQualityDashboardController.getLatestSnapshot();
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testGetLatestSnapshotReturnsMostRecent() {
        DataQualityScorecardService.runScorecard();

        Test.startTest();
        Data_Quality_Snapshot__c result = DataQualityDashboardController.getLatestSnapshot();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.Overall_Score__c);
    }

    @IsTest
    static void testGetTrendDefaultsToTwelve() {
        DataQualityScorecardService.runScorecard();

        Test.startTest();
        List<Data_Quality_Snapshot__c> trend = DataQualityDashboardController.getTrend(null);
        Test.stopTest();

        System.assertEquals(1, trend.size());
    }

    @IsTest
    static void testGetConfigReturnsDefaults() {
        Test.startTest();
        Data_Quality_Config__mdt config = DataQualityDashboardController.getConfig();
        Test.stopTest();

        System.assertNotEquals(null, config);
    }
}
