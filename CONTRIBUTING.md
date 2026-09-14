# Contributing

## Known gaps that need a real org to fix

This package's biggest honest gap: metrics 6 (unlinked soft credits) and 8 (missing GAU allocations) only score NPSP orgs. Nonprofit Cloud equivalents weren't confirmed against a live org or current docs at the time this was written, so they return "not applicable" for `DataModel.NONPROFIT_CLOUD` and `DataModel.MIXED` rather than guessing at object/field names that might not exist.

If you run Nonprofit Cloud and can confirm:

- The object and field that plays the role of NPSP's `npsp__Partial_Soft_Credit__c` (soft credit tracking)
- The object and field that plays the role of NPSP's `npsp__Allocation__c` (GAU-style fund allocation on a gift)

...open a PR against `DataQualityMetrics.unlinkedSoftCreditsCount()` and `DataQualityMetrics.missingGauAllocationsCount()`. Use `Database.query(String)` for anything object/field-specific to Nonprofit Cloud, matching the pattern already used for `orphanGiftsCount()` and `currencyAnomaliesCount()` in the same class - a typed SOQL reference to a Nonprofit Cloud-only field would break compilation for every NPSP-only org running this package.

## Adding a metric

1. Add the field to `apex/objects/Data_Quality_Snapshot__c/fields/` (percent metrics as `Percent(5,2)`, counts as `Number(18,0)`).
2. Add the method to `DataQualityMetrics.cls`, returning a `MetricResult`. Use `new MetricResult(decimalValue)` when applicable, `new MetricResult(String note)` when it isn't - never fabricate a number when the org's schema doesn't support the check.
3. Wire it into `runAll()` and `DataQualityScorecardService.runScorecard()`.
4. Add it to the `WEIGHTS` map and the appropriate scoring set (`higherIsWorsePercent`, `higherIsBetterPercent`, or `countMetrics`) in `computeOverallScore()`.
5. Add a row to the LWC (`dataQualityDashboard.js` / `.html`) and a row to the README's metrics table.
6. Write a test. If the metric touches an NPSP or Nonprofit Cloud object, at minimum test that it degrades cleanly (`applicable = false`, no exception) when that object isn't present - see `DataQualityMetricsTest.testUnknownModelMetricsAreNotApplicable()` for the pattern.

## Style

- No em-dashes. Use a period, comma, or parentheses instead.
- No "leverage," "synergy," "robust," "delve," "embark," "journey," "game changer," or other motivational-poster language, in code, comments, commit messages, or docs.
- Comments should explain *why*, not restate the line above them. If a design choice looks odd at a glance (dynamic SOQL instead of typed SOQL, a metric returning "not applicable" instead of a number), say why in a comment near the code, not just in this file.

## Running the checks locally

```bash
python3 scripts/validate_metadata.py
```

This is a static check (XML well-formedness, field naming, unresolved-token warnings) - it does not deploy anything or run Apex tests, because there's no Dev Hub wired up for this repo. If you have a scratch org or sandbox, running the real test suite before opening a PR is on you:

```bash
sf project deploy start --source-dir apex --target-org your-alias
sf apex run test --test-level RunLocalTests --target-org your-alias --result-format human
```

## Pull requests

Keep PRs scoped to one metric, one bug fix, or one doc change. Explain what you tested it against (which data model, real org or scratch org) in the PR description.
