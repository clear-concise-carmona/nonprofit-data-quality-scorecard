/**
 * DataQualityScorecardService
 *
 * The orchestrator: detect the data model, load config, run every metric,
 * compute the overall score, and insert one Data_Quality_Snapshot__c
 * record. Call runScorecard() from anonymous Apex (scripts/run-scorecard.apex),
 * from DataQualityScorecardScheduler on a schedule, or from a Flow/button
 * via a future/queueable wrapper if you want one - this class itself is
 * synchronous because none of the queries here are large enough to need
 * async governor limit relief in a normal-sized org. If your org has
 * millions of Contacts and this starts timing out, that's a sign to
 * convert the per-metric queries to a real Batchable - see CONTRIBUTING.md.
 */
public with sharing class DataQualityScorecardService {

    public static Data_Quality_Snapshot__c runScorecard() {
        DataQualityOrgDetector.DataModel model = DataQualityOrgDetector.detect();
        Data_Quality_Config__mdt config = DataQualityMetrics.loadConfig();
        Map<String, DataQualityMetrics.MetricResult> results = DataQualityMetrics.runAll(config, model);
        Decimal overallScore = DataQualityMetrics.computeOverallScore(results);

        Data_Quality_Snapshot__c snapshot = new Data_Quality_Snapshot__c();
        snapshot.Run_Date__c = DateTime.now();
        snapshot.Data_Model_Detected__c = DataQualityOrgDetector.toLabel(model);
        snapshot.Stale_Contact_Threshold_Months_Used__c = (Integer) config.Stale_Contact_Threshold_Months__c;
        snapshot.Overall_Score__c = overallScore;

        applyPercent(snapshot, 'Duplicate_Rate__c', results.get('duplicateRate'));
        applyPercent(snapshot, 'Valid_Email_Percent__c', results.get('validEmailPercent'));
        applyPercent(snapshot, 'Address_Completeness_Percent__c', results.get('addressCompletenessPercent'));
        applyPercent(snapshot, 'Channel_Preference_Coverage_Percent__c', results.get('channelPreferenceCoveragePercent'));
        applyPercent(snapshot, 'Stale_Contacts_Percent__c', results.get('staleContactsPercent'));
        applyPercent(snapshot, 'Required_Field_Null_Rate_Percent__c', results.get('requiredFieldNullRatePercent'));

        applyCount(snapshot, 'Orphan_Gifts_Count__c', results.get('orphanGiftsCount'));
        applyCount(snapshot, 'Unlinked_Soft_Credits_Count__c', results.get('unlinkedSoftCreditsCount'));
        applyCount(snapshot, 'Missing_Gau_Allocations_Count__c', results.get('missingGauAllocationsCount'));
        applyCount(snapshot, 'Currency_Anomalies_Count__c', results.get('currencyAnomaliesCount'));

        snapshot.Notes__c = buildNotes(results);

        insert snapshot;
        return snapshot;
    }

    private static void applyPercent(Data_Quality_Snapshot__c snapshot, String fieldName, DataQualityMetrics.MetricResult result) {
        if (result != null && result.applicable) {
            snapshot.put(fieldName, result.value);
        }
    }

    private static void applyCount(Data_Quality_Snapshot__c snapshot, String fieldName, DataQualityMetrics.MetricResult result) {
        if (result != null && result.applicable) {
            snapshot.put(fieldName, result.value);
        }
    }

    private static String buildNotes(Map<String, DataQualityMetrics.MetricResult> results) {
        List<String> lines = new List<String>();
        for (String metricName : results.keySet()) {
            DataQualityMetrics.MetricResult result = results.get(metricName);
            if (!result.applicable) {
                lines.add(metricName + ': ' + result.note);
            }
        }
        if (lines.isEmpty()) {
            return null;
        }
        String combined = String.join(lines, '\n');
        return combined.length() > 2000 ? combined.substring(0, 2000) : combined;
    }
}
