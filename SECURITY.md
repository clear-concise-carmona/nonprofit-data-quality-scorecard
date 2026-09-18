# Security Policy

## Reporting a problem

Open an issue at
[github.com/clear-concise-carmona/nonprofit-data-quality-scorecard/issues](https://github.com/clear-concise-carmona/nonprofit-data-quality-scorecard/issues).

Do not include org IDs, usernames, session IDs, donor records, email addresses, or exported
snapshot data in a public issue. If the problem cannot be described without that detail, open an
issue saying only that you have a security report, and follow up through the
[contact page](https://www.clearconciseconsulting.com/contact).

There is no bug bounty and no committed response time. See the Maintenance Status section of
the [README](README.md#maintenance-status).

## Supported versions

Fixes go to the most recent tagged release.

| Version | Supported |
|---|---|
| 0.1.0 | Yes |

## What this package does to your org

**This package is not read-only.** It reads org data to calculate metrics, and it writes
records.

What it reads: Contact, Task, Event, and `DuplicateRecordItem`, plus Opportunity and NPSP
objects (`npsp__Allocation__c`, `npsp__Partial_Soft_Credit__c`, `npe01__OppPayment__c`) or
Nonprofit Cloud objects (`GiftCommitment`, `GiftTransaction`) depending on which data model
`DataQualityOrgDetector` finds in the org. Queries are aggregate counts and field-population
checks. It does not export, transmit, or persist donor field values.

What it writes: one `Data_Quality_Snapshot__c` record per run, at
[DataQualityScorecardService.cls:42](apex/classes/DataQualityScorecardService.cls). That object
ships with this repo's own metadata. The record holds aggregate metric values, the detected data
model, the threshold used, and a notes string. It holds no donor field values and no record IDs.

It does not modify, delete, or deduplicate any Contact, Opportunity, gift, or NPSP record. It
measures. It does not clean.

## Permissions and sharing

`DataQualityScorecardService`, `DataQualityMetrics`, and `DataQualityOrgDetector` are declared
`with sharing`, so queries run under the sharing rules of whoever runs them. A user without
visibility into part of your donor data will produce a score calculated over the subset they can
see. Run the scorecard as a user whose visibility matches the population you intend to measure,
and say which user it ran as when you report the number.

The scheduled job runs as the user who scheduled it. That user's visibility is what every future
snapshot is measured against until someone reschedules it.

## Handling snapshot records

`Data_Quality_Snapshot__c` holds aggregates, not donor data. Exports of it are still a
description of your data quality posture over time. Treat exports as internal material and
redact them before attaching them to a public issue.

Set field-level security and object permissions on `Data_Quality_Snapshot__c` and the dashboard
component to match who at your organization should see an org-wide data quality score.

## Credentials

This package contains no credentials and makes no callouts. It runs entirely inside your org.
Never commit auth files, org IDs, `.env` files, or exported record data to this repository.

## Sandbox first

Deploy to a sandbox and run at least one scorecard there before deploying to production. This
package writes records, its Apex tests have not been executed against a live org by this
project, and CI validates metadata statically rather than running Apex. A sandbox run is how you
find out that the deployment works in your org.

## What this package does not do

It does not certify, validate, or determine compliance with any standard, framework, or program,
including any privacy or data-protection regulation. It produces a measurement for a person to
review.
