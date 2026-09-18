# Changelog

## 0.1.0 - 2026-09-18

First tagged public release. No version existed in repository metadata before this tag.

### Added

- Ten data quality metrics in `DataQualityMetrics.cls`: duplicate contact rate, valid email
  percent, address completeness, channel preference coverage, orphan gifts, unlinked soft
  credits, stale contacts, missing GAU allocations, currency anomalies, and required field null
  rate.
- `DataQualityOrgDetector.cls`, runtime data model detection via `Schema.getGlobalDescribe()`,
  branching dynamic SOQL between NPSP and Nonprofit Cloud so the package deploys to either.
- `DataQualityScorecardService.cls`, the orchestrator. It computes a weighted overall score and
  inserts one `Data_Quality_Snapshot__c` record per run.
- `Data_Quality_Snapshot__c` custom object with 15 fields, giving the dashboard a trend history
  that builds itself over time.
- `Data_Quality_Config__mdt` custom metadata type for the four settings that cannot be guessed:
  channel preference field API name, required field list, stale contact threshold in months, and
  target score.
- `DataQualityScorecardScheduler.cls` for recurring snapshots.
- `dataQualityDashboard` Lightning Web Component and its controller.
- Paired Apex test class for every class.
- `scripts/validate_metadata.py`, a static metadata check, run by CI.
- `SECURITY.md` covering reporting, read and write scope, sharing behavior, and snapshot
  handling.

### Known at release

- **This package is not read-only.** It reads org data to calculate metrics and writes one
  `Data_Quality_Snapshot__c` record per run.
- Metrics 6 and 8, unlinked soft credits and missing GAU allocations, score NPSP orgs only. The
  Nonprofit Cloud equivalents have not been confirmed against the Fundraising standard objects
  documentation, so they report as not applicable rather than guessing.
- Apex tests have not been executed against a live org by this project. CI runs a static
  metadata validation, not Apex tests, because this repo has no Dev Hub attached.
- Metrics that branch on NPSP or Nonprofit Cloud objects are unit tested only against
  `DataModel.UNKNOWN`, proving they degrade to not applicable instead of throwing. The NPSP and
  Nonprofit Cloud branches need a real org with that package installed to exercise.
- The scorecard is synchronous. An org large enough to hit governor limits needs the per-metric
  queries converted to a Batchable. See `CONTRIBUTING.md`.
