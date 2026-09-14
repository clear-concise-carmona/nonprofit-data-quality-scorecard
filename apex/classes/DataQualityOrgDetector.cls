/**
 * DataQualityOrgDetector
 *
 * Every metric in this package needs to know whether it's running against an
 * NPSP org, a Nonprofit Cloud org, or both (some orgs run NPSP fields
 * alongside early Nonprofit Cloud adoption during a migration). This class is
 * the single place that answers that question, so a metric never has to
 * guess.
 *
 * Detection is done entirely through Schema.getGlobalDescribe() - a runtime
 * check, not a compile-time field reference. That distinction matters: if
 * this class (or any metric class) referenced an npsp__ or GiftCommitment
 * field directly in a static SOQL statement, the whole package would fail to
 * deploy to an org that doesn't have that package/feature installed, because
 * Apex validates field references at compile time. Every metric in
 * DataQualityMetrics.cls that touches a model-specific object builds its
 * SOQL as a string and runs it through Database.query() for exactly this
 * reason - see the comments there.
 *
 * NPSP detection uses npsp__Allocation__c (the GAU Allocation object) rather
 * than an account/household object, because NPSP has changed its household
 * model twice (npo02__Household__c in old orgs, the Household Account model
 * in current ones) and Allocation has been stable the whole time:
 * https://help.salesforce.com/s/articleView?id=sfdo.npsp_gau_overview.htm
 *
 * Nonprofit Cloud detection uses the GiftCommitment and GiftTransaction
 * standard objects, documented as available from API v59.0 onward:
 * https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_standard_objects.htm
 */
public with sharing class DataQualityOrgDetector {

    public enum DataModel { NPSP, NONPROFIT_CLOUD, MIXED, UNKNOWN }

    public static DataModel detect() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        Boolean hasNonprofitCloud = globalDescribe.containsKey('GiftCommitment')
            && globalDescribe.containsKey('GiftTransaction');
        Boolean hasNpsp = globalDescribe.containsKey('npsp__Allocation__c');

        if (hasNonprofitCloud && hasNpsp) {
            return DataModel.MIXED;
        }
        if (hasNonprofitCloud) {
            return DataModel.NONPROFIT_CLOUD;
        }
        if (hasNpsp) {
            return DataModel.NPSP;
        }
        return DataModel.UNKNOWN;
    }

    public static String toLabel(DataModel model) {
        if (model == DataModel.NPSP) {
            return 'NPSP';
        }
        if (model == DataModel.NONPROFIT_CLOUD) {
            return 'Nonprofit Cloud';
        }
        if (model == DataModel.MIXED) {
            return 'Mixed (NPSP + Nonprofit Cloud)';
        }
        return 'Unknown';
    }

    /** True if this run should score NPSP-shaped gift data (Opportunity/npe01__OppPayment__c/npsp__Allocation__c). */
    public static Boolean scoresNpsp(DataModel model) {
        return model == DataModel.NPSP || model == DataModel.MIXED;
    }

    /** True if this run should score Nonprofit Cloud fundraising objects (GiftCommitment/GiftTransaction). */
    public static Boolean scoresNonprofitCloud(DataModel model) {
        return model == DataModel.NONPROFIT_CLOUD || model == DataModel.MIXED;
    }
}
