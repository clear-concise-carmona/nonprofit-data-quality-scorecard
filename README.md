# Nonprofit Data Quality Scorecard

A free Apex + Lightning Web Component package that scores your Salesforce nonprofit org on 10 data quality metrics, works across both NPSP and Nonprofit Cloud, and gives you one number to track over time.

Data quality is not a side issue for nonprofits on Salesforce. [Salesforce Ben's 2025 review of nonprofits on Salesforce](https://www.salesforceben.com/the-state-of-nonprofits-on-salesforce-in-2025-challenges-and-the-road-ahead/) and its [2026 follow-up](https://www.salesforceben.com/the-state-of-salesforce-nonprofit-offerings-in-2026/) both flag messy donor data as a recurring blocker to reporting and automation. Salesforce's own [2025 Nonprofit Trends Report](https://trailhead.salesforce.com/trailblazer-community/feed/0D5KX00000gR93J) found 55% of nonprofits are piloting or using AI while 63% cite data-privacy concerns - AI and automation amplify whatever is already in your data, good or bad. If your donor records are full of duplicates and orphaned gifts, an AI layer on top just gets you wrong answers faster.

This package doesn't fix your data. It tells you, in one number, whether it needs fixing, and where.

## The 10 metrics

| # | Metric | What it measures | Applies to |
|---|--------|-------------------|------------|
| 1 | Duplicate contact rate | Percent of Contacts flagged by Salesforce's standard Duplicate Management rules | Both |
| 2 | Valid email percent | Percent of Contacts with an email address that at least matches a basic `x@y.z` shape | Both |
| 3 | Address completeness | Percent of Contacts with all five standard Mailing fields populated | Both |
| 4 | Channel preference coverage | Percent of Contacts with your org's configured contact-preference field populated | Both (requires configuration - see below) |
| 5 | Orphan gifts | Count of closed-won gifts with no donor attached | Both |
| 6 | Unlinked soft credits | Count of soft credit records missing a Contact or amount | NPSP only in this release |
| 7 | Stale contacts | Percent of Contacts with no activity or gift within a configurable window | Both |
| 8 | Missing GAU allocations | Count of closed-won gifts never assigned to a General Accounting Unit | NPSP only in this release |
| 9 | Currency anomalies | Count of negative, zero, or off-currency-list amounts on closed-won gifts | Both |
| 10 | Required field null rate | Average null rate across the object.field pairs you tell it matter | Both (requires configuration - see below) |

Metrics 5, 6, 8, and 9 branch on your org's data model automatically - see [How data model detection works](#how-data-model-detection-works). Metrics 6 and 8 currently only score NPSP orgs; the Nonprofit Cloud equivalents (GAU-style fund allocation on GiftCommitment, a soft-credit object) haven't been confirmed against the [Nonprofit Cloud Fundraising standard objects docs](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_standard_objects.htm) yet. If you run Nonprofit Cloud and can confirm the right objects, see [CONTRIBUTING.md](CONTRIBUTING.md).

A metric that isn't applicable to your org (unconfigured, or no matching gift object detected) is excluded from the overall score entirely - it isn't counted as a failure. See [Interpreting your score](#interpreting-your-score).

## Installation

This ships as source-format metadata under `apex/`, the same pattern as [npsp-migration-readiness-scanner](https://github.com/clear-concise-carmona/npsp-migration-readiness-scanner) - copy-paste deployable, no managed package, no Dev Hub required.

```bash
git clone https://github.com/clear-concise-carmona/nonprofit-data-quality-scorecard.git
cd nonprofit-data-quality-scorecard
sf project deploy start --source-dir apex --target-org your-alias
```

## Quick start

Run one scorecard snapshot right now:

```bash
sf apex run --file scripts/run-scorecard.apex --target-org your-alias
```

Then add the **Data Quality Dashboard** Lightning component to a Home page or App page (Setup → Lightning App Builder) to see the result.

## Configuration

Two things about your org can't be guessed and have to be told to the scorecard, via the `Data_Quality_Config__mdt` custom metadata type (Setup → Custom Metadata Types → Data Quality Config → Manage Records → Default):

- **Channel_Preference_Field_Api_Name__c** - the field your org uses to record a Contact's preferred communication channel. There's no Salesforce-standard field for this. Leave blank and metric 4 reports "not configured" instead of a made-up number.
- **Required_Fields_To_Check__c** - comma-separated `Object.Field` pairs your org treats as required for a usable donor record, e.g. `Contact.MobilePhone,Contact.Description`. Defaults to `Contact.MobilePhone`.

One more setting controls the stale-contact window:

- **Stale_Contact_Threshold_Months__c** - months of no activity/gift before a Contact counts as stale. Defaults to 12. Every organization's normal donor cadence is different, so this is deliberately not hardcoded in Apex.

- **Target_Score_Percent__c** - the score you're treating as acceptable, on a 0-100 scale. Defaults to 70, matching this README's "7 out of 10" framing below.

## Scheduling recurring snapshots

Run once from anonymous Apex to get a weekly snapshot on Mondays at 6am:

```apex
String cronExpression = '0 0 6 ? * MON';
System.schedule('Weekly Data Quality Scorecard', cronExpression, new DataQualityScorecardScheduler());
```

Each run inserts one `Data_Quality_Snapshot__c` record, so the dashboard's trend view builds itself over time - no extra setup needed.

## Interpreting your score

`Overall_Score__c` is a weighted average across whichever metrics are applicable to your org, stored as 0-100. Divide by 10 to compare against a familiar "out of 10" framing - a score of 70 is a 7/10.

- **70 or above**: your core donor data is in reasonable shape. Worth spot-checking the metrics that scored lowest.
- **50 to 69**: data quality is actively costing you time - reporting is probably unreliable and automation (dedupe rules, journeys, AI features) will misfire on bad records.
- **Below 50**: treat this as a data cleanup project, not a backlog item.

Not-applicable metrics are excluded from the score, not counted against you - an org that hasn't configured channel-preference tracking is scored on the 9 metrics it can measure, not penalized for the 1 it can't.

Score below 7/10? [Book CCC's full data-quality remediation audit](https://www.clearconciseconsulting.com/services/salesforce-nonprofit-consulting).

## How data model detection works

`DataQualityOrgDetector` checks `Schema.getGlobalDescribe()` at runtime for `GiftCommitment`/`GiftTransaction` (Nonprofit Cloud, available from API [v59.0 onward](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_standard_objects.htm), see also the [GiftCommitment](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_api_objects_giftcommitment.htm) and [GiftTransaction](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_api_objects_gifttransaction.htm) object references) and `npsp__Allocation__c` (NPSP). Every metric that touches a model-specific object builds its query as a string and runs it through `Database.query()` rather than a typed SOQL literal - a static reference to a package field that doesn't exist in the target org is a compile-time error in Apex, which would break deployability for whichever model you don't run.

## Testing

Every class ships with a paired test class (`apex/classes/*Test.cls`). Metrics that only touch standard objects (Contact, Task, Event, DuplicateRecordItem) are fully covered against any org. Metrics that branch on NPSP or Nonprofit Cloud objects are only tested against `DataModel.UNKNOWN` here, proving they degrade to "not applicable" instead of throwing - the NPSP and Nonprofit Cloud branches themselves need a real org with that package installed to exercise for real. CI (see `.github/workflows/ci.yml`) runs `scripts/validate_metadata.py`, a static metadata check - it does not run live Apex tests, because this repo has no Dev Hub to deploy against.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## About

Built by [Clear Concise Consulting](https://www.clearconciseconsulting.com), a Salesforce consultancy for nonprofit, healthcare, enterprise, and government orgs. If your donor data needs more than a scorecard, [book a data-quality remediation audit](https://www.clearconciseconsulting.com/services/salesforce-nonprofit-consulting).

## References

- [Salesforce Ben - The State of Nonprofits on Salesforce in 2025](https://www.salesforceben.com/the-state-of-nonprofits-on-salesforce-in-2025-challenges-and-the-road-ahead/)
- [Salesforce Ben - The State of Salesforce Nonprofit Offerings in 2026](https://www.salesforceben.com/the-state-of-salesforce-nonprofit-offerings-in-2026/)
- [Salesforce 2025 Nonprofit Trends Report, via Trailblazer Community](https://trailhead.salesforce.com/trailblazer-community/feed/0D5KX00000gR93J)
- [Salesforce Developer Docs - GiftCommitment object](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_api_objects_giftcommitment.htm)
- [Salesforce Developer Docs - GiftTransaction object](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_api_objects_gifttransaction.htm)
- [Salesforce Developer Docs - Fundraising Standard Objects](https://developer.salesforce.com/docs/atlas.en-us.nonprofit_cloud.meta/nonprofit_cloud/npc_fundraising_standard_objects.htm)

## License

MIT - see [LICENSE](LICENSE).
