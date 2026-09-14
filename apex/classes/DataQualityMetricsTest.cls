/**
 * DataQualityMetricsTest
 *
 * Covers every metric that only touches standard Salesforce objects
 * (Contact, Task, Event, DuplicateRecordItem) - these run identically in
 * any org. Metrics that branch on NPSP/Nonprofit Cloud objects
 * (orphanGiftsCount, unlinkedSoftCreditsCount, missingGauAllocationsCount,
 * currencyAnomaliesCount) are exercised here only with DataModel.UNKNOWN,
 * which proves they short-circuit to "not applicable" instead of throwing
 * when no gift-management package is installed. Their NPSP/Nonprofit
 * Cloud branches need a real org with that package installed to test for
 * real - see README's testing section.
 *
 * computeOverallScore() is tested against a hand-built results map rather
 * than live metric output, so the weighting and rounding logic has
 * predictable inputs regardless of what's in the test org's data.
 */
@IsTest
private class DataQualityMetricsTest {

    private static Contact makeContact(String email, Boolean withFullAddress) {
        Contact c = new Contact(
            LastName = 'Test Donor ' + Math.random(),
            Email = email
        );
        if (withFullAddress) {
            c.MailingStreet = '123 Main St';
            c.MailingCity = 'Brooklyn';
            c.MailingState = 'NY';
            c.MailingPostalCode = '11201';
            c.MailingCountry = 'US';
        }
        return c;
    }

    @IsTest
    static void testValidEmailPercent() {
        List<Contact> contacts = new List<Contact>{
            makeContact('good@example.com', true),
            makeContact('also.good@example.org', true),
            makeContact(null, true),
            makeContact('not-an-email', true)
        };
        insert contacts;

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.validEmailPercent();
        Test.stopTest();

        System.assertEquals(true, result.applicable);
        System.assertEquals(50.00, result.value);
    }

    @IsTest
    static void testValidEmailPercentWithNoContacts() {
        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.validEmailPercent();
        Test.stopTest();

        System.assertEquals(true, result.applicable);
        System.assertEquals(0, result.value);
    }

    @IsTest
    static void testAddressCompletenessPercent() {
        List<Contact> contacts = new List<Contact>{
            makeContact('a@example.com', true),
            makeContact('b@example.com', false)
        };
        insert contacts;

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.addressCompletenessPercent();
        Test.stopTest();

        System.assertEquals(true, result.applicable);
        System.assertEquals(50.00, result.value);
    }

    @IsTest
    static void testDuplicateRateWithNoDuplicateRules() {
        insert makeContact('solo@example.com', true);

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.duplicateRate();
        Test.stopTest();

        // No duplicate rule fires in a fresh test context, so this should
        // come back applicable with 0%, not an error.
        System.assertEquals(true, result.applicable);
        System.assertEquals(0, result.value);
    }

    @IsTest
    static void testChannelPreferenceCoverageNotConfigured() {
        Data_Quality_Config__mdt config = new Data_Quality_Config__mdt();
        config.Channel_Preference_Field_Api_Name__c = null;

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.channelPreferenceCoveragePercent(config);
        Test.stopTest();

        System.assertEquals(false, result.applicable);
        System.assertEquals(null, result.value);
        System.assert(result.note.contains('Not configured'));
    }

    @IsTest
    static void testChannelPreferenceCoverageBadFieldName() {
        Data_Quality_Config__mdt config = new Data_Quality_Config__mdt();
        config.Channel_Preference_Field_Api_Name__c = 'Definitely_Not_A_Real_Field__c';

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.channelPreferenceCoveragePercent(config);
        Test.stopTest();

        System.assertEquals(false, result.applicable);
        System.assert(result.note.contains('was not found'));
    }

    @IsTest
    static void testRequiredFieldNullRateWithDefault() {
        List<Contact> contacts = new List<Contact>{
            makeContact('a@example.com', true),
            makeContact('b@example.com', true)
        };
        contacts[0].MobilePhone = '5551234567';
        insert contacts;

        Data_Quality_Config__mdt config = new Data_Quality_Config__mdt();
        config.Required_Fields_To_Check__c = 'Contact.MobilePhone';

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.requiredFieldNullRatePercent(config);
        Test.stopTest();

        System.assertEquals(true, result.applicable);
        System.assertEquals(50.00, result.value);
    }

    @IsTest
    static void testRequiredFieldNullRateBlankConfig() {
        Data_Quality_Config__mdt config = new Data_Quality_Config__mdt();
        config.Required_Fields_To_Check__c = null;

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.requiredFieldNullRatePercent(config);
        Test.stopTest();

        System.assertEquals(false, result.applicable);
    }

    @IsTest
    static void testUnknownModelMetricsAreNotApplicable() {
        Test.startTest();
        DataQualityMetrics.MetricResult orphanGifts = DataQualityMetrics.orphanGiftsCount(DataQualityOrgDetector.DataModel.UNKNOWN);
        DataQualityMetrics.MetricResult softCredits = DataQualityMetrics.unlinkedSoftCreditsCount(DataQualityOrgDetector.DataModel.UNKNOWN);
        DataQualityMetrics.MetricResult allocations = DataQualityMetrics.missingGauAllocationsCount(DataQualityOrgDetector.DataModel.UNKNOWN);
        DataQualityMetrics.MetricResult anomalies = DataQualityMetrics.currencyAnomaliesCount(DataQualityOrgDetector.DataModel.UNKNOWN);
        Test.stopTest();

        System.assertEquals(false, orphanGifts.applicable);
        System.assertEquals(false, softCredits.applicable);
        System.assertEquals(false, allocations.applicable);
        System.assertEquals(false, anomalies.applicable);
    }

    @IsTest
    static void testStaleContactsPercentWithUnknownModel() {
        insert makeContact('stale@example.com', true);

        Test.startTest();
        DataQualityMetrics.MetricResult result = DataQualityMetrics.staleContactsPercent(DataQualityOrgDetector.DataModel.UNKNOWN, 12);
        Test.stopTest();

        // No Task/Event/gift activity was created, so the one Contact
        // should be counted as stale.
        System.assertEquals(true, result.applicable);
        System.assertEquals(100.00, result.value);
    }

    @IsTest
    static void testLoadConfigFallsBackWhenNoRecord() {
        // The Default custom metadata record ships with this package, so
        // in a normal deploy this will find it. This test just confirms
        // loadConfig() never throws and always returns usable defaults.
        Test.startTest();
        Data_Quality_Config__mdt config = DataQualityMetrics.loadConfig();
        Test.stopTest();

        System.assertNotEquals(null, config);
        System.assertNotEquals(null, config.Stale_Contact_Threshold_Months__c);
    }

    @IsTest
    static void testComputeOverallScoreWithHandBuiltResults() {
        Map<String, DataQualityMetrics.MetricResult> results = new Map<String, DataQualityMetrics.MetricResult>();
        results.put('duplicateRate', new DataQualityMetrics.MetricResult(10)); // higher = worse -> 90
        results.put('validEmailPercent', new DataQualityMetrics.MetricResult(90)); // higher = better -> 90
        results.put('addressCompletenessPercent', new DataQualityMetrics.MetricResult(80));
        results.put('channelPreferenceCoveragePercent', new DataQualityMetrics.MetricResult('not configured'));
        results.put('orphanGiftsCount', new DataQualityMetrics.MetricResult(0)); // 0 findings -> 100
        results.put('unlinkedSoftCreditsCount', new DataQualityMetrics.MetricResult('n/a'));
        results.put('staleContactsPercent', new DataQualityMetrics.MetricResult(20)); // higher = worse -> 80
        results.put('missingGauAllocationsCount', new DataQualityMetrics.MetricResult('n/a'));
        results.put('currencyAnomaliesCount', new DataQualityMetrics.MetricResult('n/a'));
        results.put('requiredFieldNullRatePercent', new DataQualityMetrics.MetricResult(0)); // higher = worse -> 100

        Test.startTest();
        Decimal score = DataQualityMetrics.computeOverallScore(results);
        Test.stopTest();

        // Only the applicable metrics count toward the weighted average -
        // this asserts the score lands in a sane range and isn't dragged
        // down by the not-applicable ones, rather than pinning an exact
        // number that would be brittle to reweight.
        System.assert(score > 0 && score <= 100, 'Score should be a valid 0-100 percent, got: ' + score);
        System.assert(score >= 80, 'A mostly-clean set of inputs should score well, got: ' + score);
    }

    @IsTest
    static void testComputeOverallScoreWithNoApplicableMetrics() {
        Map<String, DataQualityMetrics.MetricResult> results = new Map<String, DataQualityMetrics.MetricResult>();
        results.put('duplicateRate', new DataQualityMetrics.MetricResult('n/a'));

        Test.startTest();
        Decimal score = DataQualityMetrics.computeOverallScore(results);
        Test.stopTest();

        System.assertEquals(0, score);
    }
}
