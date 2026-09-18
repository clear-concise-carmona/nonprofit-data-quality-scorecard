# Nonprofit Data Quality Scorecard

A free Apex + Lightning Web Component package that scores your Salesforce nonprofit org on 10 data quality metrics, works across both NPSP and Nonprofit Cloud, and gives you one number to track over time.

Data quality is not a side issue for nonprofits on Salesforce. [Salesforce Ben's 2025 review of nonprofits on Salesforce](https://www.salesforceben.com/the-state-of-nonprofits-on-salesforce-in-2025-challenges-and-the-road-ahead/) and its [2026 follow-up](https://www.salesforceben.com/the-state-of-salesforce-nonprofit-offerings-in-2026/) both flag messy donor data as a recurring blocker to reporting and automation. Salesforce's own [2025 Nonprofit Trends Report](https://trailhead.salesforce.com/trailblazer-community/feed/0D5KX00000gR93J) found 55% of nonprofits are piloting or using AI while 63% cite data-privacy concerns - AI and automation amplify whatever is already in your data, good or bad. If your donor records are full of duplicates and orphaned gifts, an AI layer on top just gets you wrong answers faster.

This package doesn't fix your data. It tells you, in one number, whether it needs fixing, and where.

## What this reads and writes

**This package is not read-only.** Two sentences worth reading before you deploy it anywhere:

- **It reads** Contact, Task, Event, and `DuplicateRecordItem`, plus Opportunity and the NPSP
  objects (`npsp__Allocation__c`, `npsp__Partial_Soft_Credit__c`, `npe01__OppPayment__c`) or the
  Nonprofit Cloud objects (`GiftCommitment`, `GiftTransaction`), depending on which data model it
  detects. The queries are aggregate counts and field-population checks.
- **It writes** one `Data_Quality_Snapshot__c` record per run
  ([DataQualityScorecardService.cls](apex/classes/DataQualityScorecardService.cls)). That object
  ships with this repo. The record holds aggregate metric values, the detected data model, the
  threshold used, and a notes string. No donor field values, no record IDs.

It never modifies, deletes, or deduplicates a Contact, Opportunity, gift, or NPSP record. It
measures. It does not clean. Every class runs `with sharing`, so the score reflects the data
visible to whoever runs it. See [SECURITY.md](SECURITY.md) for what that means for scheduled runs.

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

## Expected output

This package cannot produce output without a Salesforce org, so this repo ships no sample
dashboard and no sample numbers. Nothing here was generated from a real or simulated org. What
follows describes the output categories the code actually produces, so you know what you are
looking at after your first run.

**One `Data_Quality_Snapshot__c` record per run**, with these fields populated:

| Field | Type | Populated when |
|---|---|---|
| `Run_Date__c` | DateTime | Always |
| `Overall_Score__c` | 0-100 | Always. Weighted average across applicable metrics only |
| `Data_Model_Detected__c` | Text | Always. NPSP, Nonprofit Cloud, or Unknown |
| `Stale_Contact_Threshold_Months_Used__c` | Number | Always. Echoes the config value the run used |
| `Duplicate_Rate__c` | Percent | Always |
| `Valid_Email_Percent__c` | Percent | Always |
| `Address_Completeness_Percent__c` | Percent | Always |
| `Channel_Preference_Coverage_Percent__c` | Percent | Only when `Channel_Preference_Field_Api_Name__c` is configured |
| `Stale_Contacts_Percent__c` | Percent | Always |
| `Required_Field_Null_Rate_Percent__c` | Percent | Only when `Required_Fields_To_Check__c` resolves to real fields |
| `Orphan_Gifts_Count__c` | Number | When a gift object is detected |
| `Unlinked_Soft_Credits_Count__c` | Number | NPSP orgs only in this release |
| `Missing_Gau_Allocations_Count__c` | Number | NPSP orgs only in this release |
| `Currency_Anomalies_Count__c` | Number | When a gift object is detected |
| `Notes__c` | Long text | Always. Carries the per-metric applicability notes |

**A field left null means the metric was not applicable**, not that the metric scored zero. A
not-applicable metric is excluded from `Overall_Score__c` entirely rather than counted as a
failure. `Notes__c` is where the run tells you which metrics it skipped and why. Read it before
you read the score.

**The Data Quality Dashboard component** renders the most recent snapshot as ten labeled rows
(Duplicate contact rate, Valid email percent, Address completeness, Channel preference coverage,
Stale contacts, Required field null rate, Orphan gifts, Unlinked soft credits, Missing GAU
allocations, Currency anomalies) plus the overall score against your configured target. With more
than one snapshot in the org it also shows the trend across runs.

## Validating your first run in a sandbox

Work down this list in a sandbox before you deploy to production or quote a number to anyone.

- [ ] Deploy to a sandbox: `sf project deploy start --source-dir apex --target-org your-sandbox`.
      Confirm the deploy succeeds and reports both custom objects and all six classes.
- [ ] Run the Apex tests in that sandbox: `sf apex run test --target-org your-sandbox --wait 10`.
      This project has never executed them against a live org. You are the first check.
- [ ] Configure `Data_Quality_Config__mdt` before the first scorecard run. Set the channel
      preference field and the required field list, or accept that metrics 4 and 10 report as not
      applicable.
- [ ] Run one scorecard: `sf apex run --file scripts/run-scorecard.apex --target-org your-sandbox`.
- [ ] Open the resulting `Data_Quality_Snapshot__c` record and read `Notes__c` first. Confirm the
      list of skipped metrics matches what you expect for your data model and configuration.
- [ ] Confirm `Data_Model_Detected__c` says what you expect. A sandbox missing the NPSP package
      reports Unknown, and most metrics will skip.
- [ ] Spot-check two metrics by hand. Run your own report or SOQL for, say, Contacts with no
      email, and confirm the percentage is in the right range. A metric that disagrees with a
      hand count is a bug worth an issue.
- [ ] Confirm the run wrote exactly one snapshot record and changed nothing else. Check your
      Setup Audit Trail and a couple of recently modified Contacts.
- [ ] Add the Data Quality Dashboard component to a Lightning page and confirm it renders the
      snapshot you just created.
- [ ] Decide who should see this object, then set field-level security and object permissions
      accordingly before deploying to production.
- [ ] Schedule the job as a user whose data visibility matches the population you intend to
      measure. Every future snapshot is measured against that user's access.

## How to validate results

A score is a measurement, and measurements need a second read before anyone acts on them.

1. **Read `Notes__c` before the score.** An org with four skipped metrics is scored on six. The
   number is not comparable to an org scored on ten, and neither is comparable to another
   organization's.
2. **Hand-check any metric that drives a decision.** Every metric is a query you can reproduce.
   If "orphan gifts" is about to become a cleanup project, run the query yourself first.
3. **Check who ran it.** Classes run `with sharing`. A scorecard run by a user with partial
   visibility measures a partial org. The snapshot does not record which user ran it, so track
   that yourself.
4. **Treat the first snapshot as a baseline, not a verdict.** The value is the trend. One
   snapshot tells you where you are, three tell you whether anything is improving.
5. **Confirm the threshold matches your program.** `Stale_Contact_Threshold_Months__c` defaults
   to 12. A donor base that gives every other year is not stale at 13 months. Set it to your
   reality before quoting the stale-contact number.
6. **Do not read the duplicate rate as a duplicate count.** It reflects what your org's standard
   Duplicate Management rules flag. Weak rules produce a flattering number.

## Limitations

This package supports technical assessment and review. It does not replace architecture review,
security review, legal advice, compliance determination, or organization-specific implementation
decisions. Review the source, the configuration, and the output before relying on a result.

- **It is not read-only.** See [What this reads and writes](#what-this-reads-and-writes).
- **The Apex tests have never been executed against a live org by this project.** CI runs a
  static metadata check. Metrics that branch on NPSP or Nonprofit Cloud objects are unit tested
  only against `DataModel.UNKNOWN`, proving they degrade to not applicable rather than throwing.
- **Metrics 6 and 8 score NPSP orgs only in this release.** The Nonprofit Cloud equivalents have
  not been confirmed against the Fundraising standard objects documentation.
- **The weighting is documented judgment, not a validated model.** No dataset of nonprofit orgs
  backs the relative weight of a duplicate against a missing address.
- **The score bands are a framing device.** 70 and 50 are there to make the number actionable in
  a conversation, not calibrated against outcome data.
- **Ten metrics are not a full data quality assessment.** Referential integrity across custom
  objects, campaign attribution, pledge schedules, and household rollup accuracy are all out of
  scope for this release.
- **It is synchronous.** A large enough org will hit governor limits. See `CONTRIBUTING.md` for
  the Batchable conversion that fixes it.
- **It measures. It does not clean.** Nothing here deduplicates, merges, or corrects a record.
- **It is not a compliance or privacy tool** and makes no claim about any regulation.

## Maintenance Status

This is an independently maintained open-source project by Clear Concise Consulting. Issues and
pull requests are welcome. Maintenance is prioritized around correctness, documentation, security
concerns, and compatibility with supported Salesforce tooling. No response-time or
feature-delivery commitment is implied.

Current release: **v0.1.0**, the first tagged release. Its metadata validates in CI. Its Apex
tests have not been executed against a live org by this project, and the Nonprofit Cloud branches
of four metrics have not been exercised against a real Nonprofit Cloud org. Confirmations from
anyone running either data model are the most valuable contribution here.

Security reports: see [SECURITY.md](SECURITY.md).

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
