/**
 * DataQualityOrgDetectorTest
 *
 * Detection reads live org schema, so these tests can only assert against
 * whatever packages happen to be installed in the org running the test -
 * they can't fake NPSP or Nonprofit Cloud being present or absent. What
 * they do verify: detect() never throws, always returns a real enum value,
 * and toLabel()/scoresNpsp()/scoresNonprofitCloud() agree with each other
 * for every possible DataModel value. Full model-branch coverage requires
 * running this in an org with NPSP installed and, separately, in one with
 * Nonprofit Cloud enabled - see README's testing section.
 */
@IsTest
private class DataQualityOrgDetectorTest {

    @IsTest
    static void testDetectReturnsRealValue() {
        Test.startTest();
        DataQualityOrgDetector.DataModel model = DataQualityOrgDetector.detect();
        Test.stopTest();

        System.assertNotEquals(null, model, 'detect() should never return null');
    }

    @IsTest
    static void testToLabelCoversEveryEnumValue() {
        System.assertEquals('NPSP', DataQualityOrgDetector.toLabel(DataQualityOrgDetector.DataModel.NPSP));
        System.assertEquals('Nonprofit Cloud', DataQualityOrgDetector.toLabel(DataQualityOrgDetector.DataModel.NONPROFIT_CLOUD));
        System.assertEquals('Mixed (NPSP + Nonprofit Cloud)', DataQualityOrgDetector.toLabel(DataQualityOrgDetector.DataModel.MIXED));
        System.assertEquals('Unknown', DataQualityOrgDetector.toLabel(DataQualityOrgDetector.DataModel.UNKNOWN));
    }

    @IsTest
    static void testScoresNpspFlags() {
        System.assertEquals(true, DataQualityOrgDetector.scoresNpsp(DataQualityOrgDetector.DataModel.NPSP));
        System.assertEquals(true, DataQualityOrgDetector.scoresNpsp(DataQualityOrgDetector.DataModel.MIXED));
        System.assertEquals(false, DataQualityOrgDetector.scoresNpsp(DataQualityOrgDetector.DataModel.NONPROFIT_CLOUD));
        System.assertEquals(false, DataQualityOrgDetector.scoresNpsp(DataQualityOrgDetector.DataModel.UNKNOWN));
    }

    @IsTest
    static void testScoresNonprofitCloudFlags() {
        System.assertEquals(true, DataQualityOrgDetector.scoresNonprofitCloud(DataQualityOrgDetector.DataModel.NONPROFIT_CLOUD));
        System.assertEquals(true, DataQualityOrgDetector.scoresNonprofitCloud(DataQualityOrgDetector.DataModel.MIXED));
        System.assertEquals(false, DataQualityOrgDetector.scoresNonprofitCloud(DataQualityOrgDetector.DataModel.NPSP));
        System.assertEquals(false, DataQualityOrgDetector.scoresNonprofitCloud(DataQualityOrgDetector.DataModel.UNKNOWN));
    }
}
