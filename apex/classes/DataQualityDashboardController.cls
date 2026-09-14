/**
 * DataQualityDashboardController
 *
 * Read-only @AuraEnabled methods behind the dataQualityDashboard LWC.
 * No write methods here on purpose - the dashboard displays snapshots,
 * it doesn't create them. Trigger new runs via
 * DataQualityScorecardService.runScorecard() (anonymous Apex, a scheduled
 * job, or your own Flow/button), not from this controller.
 */
public with sharing class DataQualityDashboardController {

    @AuraEnabled(cacheable=true)
    public static Data_Quality_Snapshot__c getLatestSnapshot() {
        List<Data_Quality_Snapshot__c> snapshots = [
            SELECT Id, Name, Run_Date__c, Overall_Score__c, Data_Model_Detected__c,
                   Duplicate_Rate__c, Valid_Email_Percent__c, Address_Completeness_Percent__c,
                   Channel_Preference_Coverage_Percent__c, Orphan_Gifts_Count__c,
                   Unlinked_Soft_Credits_Count__c, Stale_Contacts_Percent__c,
                   Missing_Gau_Allocations_Count__c, Currency_Anomalies_Count__c,
                   Required_Field_Null_Rate_Percent__c, Stale_Contact_Threshold_Months_Used__c,
                   Notes__c
            FROM Data_Quality_Snapshot__c
            WITH SECURITY_ENFORCED
            ORDER BY Run_Date__c DESC
            LIMIT 1
        ];
        return snapshots.isEmpty() ? null : snapshots[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Data_Quality_Snapshot__c> getTrend(Integer numRuns) {
        Integer limitSize = (numRuns == null || numRuns <= 0) ? 12 : numRuns;
        return [
            SELECT Id, Run_Date__c, Overall_Score__c
            FROM Data_Quality_Snapshot__c
            WITH SECURITY_ENFORCED
            ORDER BY Run_Date__c DESC
            LIMIT :limitSize
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Data_Quality_Config__mdt getConfig() {
        return DataQualityMetrics.loadConfig();
    }
}
