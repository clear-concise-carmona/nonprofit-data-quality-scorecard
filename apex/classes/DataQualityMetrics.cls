/**
 * DataQualityMetrics
 *
 * The 10 metrics, one method each. DataQualityScorecardBatch calls
 * runAll() and writes the result to a Data_Quality_Snapshot__c record -
 * this class itself never writes anything, only reads.
 *
 * Two design choices worth knowing about before you read the code:
 *
 * 1. Anything that touches an npsp__ or Nonprofit Cloud fundraising field
 *    goes through Database.query(String) instead of a typed SOQL literal.
 *    A typed reference to npsp__Allocation__c or GiftCommitment would fail
 *    to compile in an org that doesn't have that package/feature - see
 *    DataQualityOrgDetector.cls for the full explanation. Standard fields
 *    that exist in every org (Contact.Email, Task, DuplicateRecordItem)
 *    are queried normally.
 * 2. Three metrics need information this class can't discover on its own:
 *    which field holds a donor's channel preference, which fields count as
 *    "required" for a usable record, and how many months of inactivity
 *    counts as stale. All three are read from Data_Quality_Config__mdt
 *    instead of hardcoded - see that object's field descriptions. A metric
 *    that isn't configured comes back with applicable = false and a note
 *    explaining why, not a fabricated number.
 *
 * Nonprofit Cloud coverage is intentionally partial as of this build.
 * GiftCommitment/GiftTransaction field names are confirmed to exist per
 * Salesforce's developer docs, but this package hasn't been validated
 * against a live Nonprofit Cloud org for every metric yet - metrics 6 and 8
 * return not-applicable on the Nonprofit Cloud side rather than guess at a
 * schema. If you're running Nonprofit Cloud and want to fill that gap,
 * see CONTRIBUTING.md.
 */
public with sharing class DataQualityMetrics {

    public class MetricResult {
        public Decimal value;
        public Boolean applicable;
        public String note;

        public MetricResult(Decimal value) {
            this.value = value;
            this.applicable = true;
            this.note = null;
        }

        public MetricResult(String notApplicableNote) {
            this.value = null;
            this.applicable = false;
            this.note = notApplicableNote;
        }
    }

    // Metric name -> weight, used by computeOverallScore(). Weights only
    // apply to metrics that came back applicable; see that method for why.
    private static final Map<String, Decimal> WEIGHTS = new Map<String, Decimal>{
        'duplicateRate' => 15,
        'validEmailPercent' => 10,
        'addressCompletenessPercent' => 10,
        'channelPreferenceCoveragePercent' => 10,
        'orphanGiftsCount' => 10,
        'unlinkedSoftCreditsCount' => 10,
        'staleContactsPercent' => 15,
        'missingGauAllocationsCount' => 10,
        'currencyAnomaliesCount' => 10,
        'requiredFieldNullRatePercent' => 10
    };

    // ---- Config -------------------------------------------------------

    public static Data_Quality_Config__mdt loadConfig() {
        List<Data_Quality_Config__mdt> configs = [
            SELECT Stale_Contact_Threshold_Months__c, Target_Score_Percent__c,
                   Channel_Preference_Field_Api_Name__c, Required_Fields_To_Check__c
            FROM Data_Quality_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!configs.isEmpty()) {
            return configs[0];
        }
        // Falls back to the same defaults shipped in the Default record, in
        // case someone deletes it. Metrics should never hard-fail just
        // because a custom metadata record is missing.
        Data_Quality_Config__mdt fallback = new Data_Quality_Config__mdt();
        fallback.Stale_Contact_Threshold_Months__c = 12;
        fallback.Target_Score_Percent__c = 70;
        fallback.Required_Fields_To_Check__c = 'Contact.MobilePhone';
        return fallback;
    }

    // ---- Runner ---------------------------------------------------------

    public static Map<String, MetricResult> runAll(Data_Quality_Config__mdt config, DataQualityOrgDetector.DataModel model) {
        Map<String, MetricResult> results = new Map<String, MetricResult>();
        results.put('duplicateRate', duplicateRate());
        results.put('validEmailPercent', validEmailPercent());
        results.put('addressCompletenessPercent', addressCompletenessPercent());
        results.put('channelPreferenceCoveragePercent', channelPreferenceCoveragePercent(config));
        results.put('orphanGiftsCount', orphanGiftsCount(model));
        results.put('unlinkedSoftCreditsCount', unlinkedSoftCreditsCount(model));
        results.put('staleContactsPercent', staleContactsPercent(model, (Integer) config.Stale_Contact_Threshold_Months__c));
        results.put('missingGauAllocationsCount', missingGauAllocationsCount(model));
        results.put('currencyAnomaliesCount', currencyAnomaliesCount(model));
        results.put('requiredFieldNullRatePercent', requiredFieldNullRatePercent(config));
        return results;
    }

    // ---- 1. Duplicate rate ----------------------------------------------
    // Uses Salesforce's standard Duplicate Management objects
    // (DuplicateRecordSet / DuplicateRecordItem), available in every org
    // since Spring '15 - no NPSP or Nonprofit Cloud dependency at all. If
    // this org has no active duplicate rules for Contact, this correctly
    // reports 0%, not an error - a rule has to exist for this metric to see
    // anything, and that's worth knowing about too (see README).
    public static MetricResult duplicateRate() {
        Integer totalContacts = [SELECT COUNT() FROM Contact];
        if (totalContacts == 0) {
            return new MetricResult(0);
        }
        Set<Id> flaggedContactIds = new Set<Id>();
        for (DuplicateRecordItem item : [SELECT RecordId FROM DuplicateRecordItem LIMIT 50000]) {
            if (item.RecordId != null && item.RecordId.getSObjectType() == Contact.SObjectType) {
                flaggedContactIds.add(item.RecordId);
            }
        }
        Decimal rate = (flaggedContactIds.size() * 100.0) / totalContacts;
        return new MetricResult(rate.setScale(2));
    }

    // ---- 2. Valid email percent ------------------------------------------
    // Format check only (contains "@" and a "." after it) - this is not
    // full RFC 5322 validation and isn't trying to be. It catches the
    // common real-world junk (blank, "n/a", "none@none", missing domain)
    // without a callout to an external verification service.
    public static MetricResult validEmailPercent() {
        Integer total = [SELECT COUNT() FROM Contact];
        if (total == 0) {
            return new MetricResult(0);
        }
        Integer valid = [
            SELECT COUNT()
            FROM Contact
            WHERE Email != null
              AND Email LIKE '%@%.%'
        ];
        Decimal pct = (valid * 100.0) / total;
        return new MetricResult(pct.setScale(2));
    }

    // ---- 3. Address completeness percent --------------------------------
    // Reads Contact's standard Mailing* fields rather than NPSP's
    // npsp__Address__c object. NPSP's Address Management feature copies a
    // household's default address down to every member Contact's Mailing
    // fields, so this works the same way whether or not NPSP is installed -
    // no branching needed for this one.
    public static MetricResult addressCompletenessPercent() {
        Integer total = [SELECT COUNT() FROM Contact];
        if (total == 0) {
            return new MetricResult(0);
        }
        Integer complete = [
            SELECT COUNT()
            FROM Contact
            WHERE MailingStreet != null
              AND MailingCity != null
              AND MailingState != null
              AND MailingPostalCode != null
              AND MailingCountry != null
        ];
        Decimal pct = (complete * 100.0) / total;
        return new MetricResult(pct.setScale(2));
    }

    // ---- 4. Channel preference coverage percent --------------------------
    // There is no Salesforce-standard "preferred contact channel" field -
    // every org that tracks this uses its own custom field. Rather than
    // guess a field name and silently report a meaningless number, this
    // reads the field name from Data_Quality_Config__mdt and only runs if
    // it's configured.
    public static MetricResult channelPreferenceCoveragePercent(Data_Quality_Config__mdt config) {
        String fieldApiName = config.Channel_Preference_Field_Api_Name__c;
        if (String.isBlank(fieldApiName)) {
            return new MetricResult('Not configured. Set Channel_Preference_Field_Api_Name__c on the Data_Quality_Config__mdt Default record to the field your org uses for preferred contact channel.');
        }
        if (!Schema.SObjectType.Contact.fields.getMap().containsKey(fieldApiName.toLowerCase())) {
            return new MetricResult('Configured field "' + fieldApiName + '" was not found on Contact. Check Channel_Preference_Field_Api_Name__c for a typo.');
        }
        Integer total = [SELECT COUNT() FROM Contact];
        if (total == 0) {
            return new MetricResult(0);
        }
        Integer populated = Database.countQuery(
            'SELECT COUNT() FROM Contact WHERE ' + String.escapeSingleQuotes(fieldApiName) + ' != null'
        );
        Decimal pct = (populated * 100.0) / total;
        return new MetricResult(pct.setScale(2));
    }

    // ---- 5. Orphan gifts count --------------------------------------------
    // NPSP: a closed-won Opportunity with no Account and no primary
    // Contact Role is "orphaned" - there's no donor to attribute the gift
    // to, even though the gift itself is recorded.
    // Nonprofit Cloud: GiftTransaction/GiftCommitment with neither AccountId
    // nor a related donor populated, checked dynamically since this package
    // hasn't confirmed the exact field set against a live org yet.
    public static MetricResult orphanGiftsCount(DataQualityOrgDetector.DataModel model) {
        Integer count = 0;
        Boolean anyChecked = false;

        if (DataQualityOrgDetector.scoresNpsp(model)) {
            anyChecked = true;
            Set<Id> oppsWithContactRole = new Set<Id>();
            for (OpportunityContactRole ocr : [SELECT OpportunityId FROM OpportunityContactRole WHERE IsPrimary = true]) {
                oppsWithContactRole.add(ocr.OpportunityId);
            }
            for (Opportunity opp : [SELECT Id FROM Opportunity WHERE IsWon = true AND AccountId = null]) {
                if (!oppsWithContactRole.contains(opp.Id)) {
                    count++;
                }
            }
        }

        if (DataQualityOrgDetector.scoresNonprofitCloud(model)) {
            Map<String, Schema.SObjectField> gtFields = Schema.getGlobalDescribe().get('GiftTransaction') != null
                ? Schema.getGlobalDescribe().get('GiftTransaction').getDescribe().fields.getMap()
                : null;
            if (gtFields != null && gtFields.containsKey('accountid') && gtFields.containsKey('contactid')) {
                anyChecked = true;
                count += Database.countQuery(
                    'SELECT COUNT() FROM GiftTransaction WHERE AccountId = null AND ContactId = null'
                );
            }
        }

        if (!anyChecked) {
            return new MetricResult('Not applicable - no supported gift object detected for this org\'s data model (' + DataQualityOrgDetector.toLabel(model) + ').');
        }
        return new MetricResult(count);
    }

    // ---- 6. Unlinked soft credits count -----------------------------------
    // NPSP: npsp__Partial_Soft_Credit__c records missing their Contact
    // link or amount - a soft credit that doesn't actually credit anyone.
    // Nonprofit Cloud: not yet implemented. This package hasn't confirmed a
    // Nonprofit Cloud soft-credit equivalent object against live docs or an
    // org, so this comes back not-applicable there rather than guessing.
    // See CONTRIBUTING.md if you can confirm the right object.
    public static MetricResult unlinkedSoftCreditsCount(DataQualityOrgDetector.DataModel model) {
        if (!DataQualityOrgDetector.scoresNpsp(model)) {
            return new MetricResult('Not applicable - Nonprofit Cloud soft-credit equivalent not yet confirmed for this package. See CONTRIBUTING.md.');
        }
        Integer count = Database.countQuery(
            'SELECT COUNT() FROM npsp__Partial_Soft_Credit__c WHERE npsp__Contact__c = null OR npsp__Amount__c = null'
        );
        return new MetricResult(count);
    }

    // ---- 7. Stale contacts percent -----------------------------------------
    // A Contact is "stale" if it has no logged Task/Event and no gift
    // (closed-won Opportunity, or GiftTransaction) within the configured
    // window. The window is org-specific by design - see
    // Data_Quality_Config__mdt.Stale_Contact_Threshold_Months__c.
    public static MetricResult staleContactsPercent(DataQualityOrgDetector.DataModel model, Integer thresholdMonths) {
        Integer total = [SELECT COUNT() FROM Contact];
        if (total == 0) {
            return new MetricResult(0);
        }
        DateTime cutoff = DateTime.now().addMonths(-thresholdMonths);

        Set<Id> recentlyActiveIds = new Set<Id>();
        for (Task t : [SELECT WhoId FROM Task WHERE WhoId != null AND ActivityDate >= :cutoff.date()]) {
            recentlyActiveIds.add(t.WhoId);
        }
        for (Event e : [SELECT WhoId FROM Event WHERE WhoId != null AND ActivityDateTime >= :cutoff]) {
            recentlyActiveIds.add(e.WhoId);
        }

        if (DataQualityOrgDetector.scoresNpsp(model)) {
            for (OpportunityContactRole ocr : [
                SELECT ContactId
                FROM OpportunityContactRole
                WHERE IsPrimary = true
                  AND Opportunity.IsWon = true
                  AND Opportunity.CloseDate >= :cutoff.date()
            ]) {
                recentlyActiveIds.add(ocr.ContactId);
            }
        }

        if (DataQualityOrgDetector.scoresNonprofitCloud(model)) {
            Map<String, Schema.SObjectField> gtFields = Schema.getGlobalDescribe().get('GiftTransaction') != null
                ? Schema.getGlobalDescribe().get('GiftTransaction').getDescribe().fields.getMap()
                : null;
            if (gtFields != null && gtFields.containsKey('contactid')) {
                for (SObject gt : Database.query(
                    'SELECT ContactId FROM GiftTransaction WHERE ContactId != null AND CreatedDate >= :cutoff'
                )) {
                    Object contactId = gt.get('ContactId');
                    if (contactId != null) {
                        recentlyActiveIds.add((Id) contactId);
                    }
                }
            }
        }

        Integer staleCount = total - recentlyActiveIds.size();
        if (staleCount < 0) {
            staleCount = 0;
        }
        Decimal pct = (staleCount * 100.0) / total;
        return new MetricResult(pct.setScale(2));
    }

    // ---- 8. Missing GAU allocations count ----------------------------------
    // NPSP: closed-won Opportunities with no npsp__Allocation__c record at
    // all - a gift that was never assigned to a General Accounting Unit,
    // which breaks fund-level reporting even though the gift itself posted
    // fine.
    // Nonprofit Cloud: not yet implemented - GAU Allocation's Nonprofit
    // Cloud equivalent (Designation/Fund allocation on GiftCommitment) is
    // still confirming its schema per this build's research pass, so this
    // returns not-applicable there. See CONTRIBUTING.md.
    public static MetricResult missingGauAllocationsCount(DataQualityOrgDetector.DataModel model) {
        if (!DataQualityOrgDetector.scoresNpsp(model)) {
            return new MetricResult('Not applicable - Nonprofit Cloud GAU allocation equivalent not yet confirmed for this package. See CONTRIBUTING.md.');
        }
        Set<Id> allocatedOppIds = new Set<Id>();
        for (SObject alloc : Database.query('SELECT npsp__Opportunity__c FROM npsp__Allocation__c WHERE npsp__Opportunity__c != null')) {
            Object oppId = alloc.get('npsp__Opportunity__c');
            if (oppId != null) {
                allocatedOppIds.add((Id) oppId);
            }
        }
        Integer missing = 0;
        for (Opportunity opp : [SELECT Id FROM Opportunity WHERE IsWon = true]) {
            if (!allocatedOppIds.contains(opp.Id)) {
                missing++;
            }
        }
        return new MetricResult(missing);
    }

    // ---- 9. Currency anomalies count -----------------------------------------
    // Standard Opportunity fields only (Amount, StageName, CurrencyIsoCode
    // when multi-currency is enabled) - flags negative amounts, zero-dollar
    // closed-won gifts, and (in multi-currency orgs) currency codes that
    // aren't in the org's active currency list.
    public static MetricResult currencyAnomaliesCount(DataQualityOrgDetector.DataModel model) {
        Integer count = 0;
        Boolean anyChecked = false;

        if (DataQualityOrgDetector.scoresNpsp(model)) {
            anyChecked = true;
            count += [SELECT COUNT() FROM Opportunity WHERE Amount < 0];
            count += [SELECT COUNT() FROM Opportunity WHERE IsWon = true AND Amount = 0];

            if (UserInfo.isMultiCurrencyOrganization()) {
                Set<String> activeCodes = new Set<String>();
                for (SObject currencyType : Database.query('SELECT IsoCode FROM CurrencyType WHERE IsActive = true')) {
                    activeCodes.add((String) currencyType.get('IsoCode'));
                }
                for (SObject opp : Database.query('SELECT CurrencyIsoCode FROM Opportunity')) {
                    String code = (String) opp.get('CurrencyIsoCode');
                    if (code != null && !activeCodes.contains(code)) {
                        count++;
                    }
                }
            }
        }

        if (DataQualityOrgDetector.scoresNonprofitCloud(model)) {
            Map<String, Schema.SObjectField> gtFields = Schema.getGlobalDescribe().get('GiftTransaction') != null
                ? Schema.getGlobalDescribe().get('GiftTransaction').getDescribe().fields.getMap()
                : null;
            if (gtFields != null && gtFields.containsKey('amount')) {
                anyChecked = true;
                count += Database.countQuery('SELECT COUNT() FROM GiftTransaction WHERE Amount < 0');
            }
        }

        if (!anyChecked) {
            return new MetricResult('Not applicable - no supported gift object detected for this org\'s data model (' + DataQualityOrgDetector.toLabel(model) + ').');
        }
        return new MetricResult(count);
    }

    // ---- 10. Required field null rate percent --------------------------------
    // "Required" is org-specific - see Data_Quality_Config__mdt.
    // Required_Fields_To_Check__c. Each configured "Object.Field" pair gets
    // its own null rate against that object's full record count, then this
    // returns the average across every configured pair.
    public static MetricResult requiredFieldNullRatePercent(Data_Quality_Config__mdt config) {
        String raw = config.Required_Fields_To_Check__c;
        if (String.isBlank(raw)) {
            return new MetricResult('Not configured. Set Required_Fields_To_Check__c on the Data_Quality_Config__mdt Default record, e.g. "Contact.MobilePhone,Contact.Description".');
        }

        List<Decimal> nullRates = new List<Decimal>();
        List<String> badPairs = new List<String>();

        for (String pair : raw.split(',')) {
            String trimmedPair = pair.trim();
            if (String.isBlank(trimmedPair) || !trimmedPair.contains('.')) {
                badPairs.add(trimmedPair);
                continue;
            }
            List<String> parts = trimmedPair.split('\\.');
            String objectName = parts[0].trim();
            String fieldName = parts.size() > 1 ? parts[1].trim() : '';

            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
            if (sObjType == null || !sObjType.getDescribe().fields.getMap().containsKey(fieldName.toLowerCase())) {
                badPairs.add(trimmedPair);
                continue;
            }

            Integer total = Database.countQuery('SELECT COUNT() FROM ' + objectName);
            if (total == 0) {
                continue;
            }
            Integer nulls = Database.countQuery(
                'SELECT COUNT() FROM ' + objectName + ' WHERE ' + fieldName + ' = null'
            );
            nullRates.add((nulls * 100.0) / total);
        }

        if (nullRates.isEmpty()) {
            String note = 'None of the configured Required_Fields_To_Check__c pairs resolved to a real field.';
            if (!badPairs.isEmpty()) {
                note += ' Unresolved: ' + String.join(badPairs, ', ');
            }
            return new MetricResult(note);
        }

        Decimal sum = 0;
        for (Decimal rate : nullRates) {
            sum += rate;
        }
        Decimal average = sum / nullRates.size();
        return new MetricResult(average.setScale(2));
    }

    // ---- Overall score -----------------------------------------------------
    // Weighted average of every applicable "percent-style" metric, on a
    // 0-100 scale where 100 is best. Count-style metrics (orphan gifts,
    // unlinked soft credits, missing allocations, currency anomalies) are
    // folded in as "0 findings = 100, else scaled down" per the
    // COUNT_METRIC_SCALE below - a handful of findings shouldn't crater the
    // score the way a raw percent would.
    //
    // Not-applicable metrics are excluded from both the numerator and the
    // weight total, not counted as failures - an org that hasn't configured
    // channel-preference tracking gets scored on the 9 metrics it can
    // measure, not penalized for the 1 it can't. This is a deliberate
    // choice: silently treating "unmeasured" as "bad" would make the score
    // punish honesty about gaps. See README's "Interpreting your score"
    // section.
    private static final Integer COUNT_METRIC_SCALE = 50; // 50+ findings on a count metric maxes out its penalty

    public static Decimal computeOverallScore(Map<String, MetricResult> results) {
        Set<String> higherIsWorsePercent = new Set<String>{ 'duplicateRate', 'staleContactsPercent', 'requiredFieldNullRatePercent' };
        Set<String> higherIsBetterPercent = new Set<String>{ 'validEmailPercent', 'addressCompletenessPercent', 'channelPreferenceCoveragePercent' };
        Set<String> countMetrics = new Set<String>{ 'orphanGiftsCount', 'unlinkedSoftCreditsCount', 'missingGauAllocationsCount', 'currencyAnomaliesCount' };

        Decimal weightedSum = 0;
        Decimal totalWeight = 0;

        for (String metricName : WEIGHTS.keySet()) {
            MetricResult result = results.get(metricName);
            if (result == null || !result.applicable) {
                continue;
            }
            Decimal weight = WEIGHTS.get(metricName);
            Decimal score0to100;

            if (higherIsWorsePercent.contains(metricName)) {
                score0to100 = 100 - result.value;
            } else if (higherIsBetterPercent.contains(metricName)) {
                score0to100 = result.value;
            } else if (countMetrics.contains(metricName)) {
                Decimal capped = result.value > COUNT_METRIC_SCALE ? COUNT_METRIC_SCALE : result.value;
                score0to100 = 100 - ((capped / COUNT_METRIC_SCALE) * 100);
            } else {
                continue;
            }

            if (score0to100 < 0) {
                score0to100 = 0;
            }
            weightedSum += score0to100 * weight;
            totalWeight += weight;
        }

        if (totalWeight == 0) {
            return 0;
        }
        return (weightedSum / totalWeight).setScale(2);
    }
}
