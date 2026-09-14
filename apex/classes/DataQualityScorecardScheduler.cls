/**
 * DataQualityScorecardScheduler
 *
 * Schedulable wrapper so the scorecard can run on a recurring cadence
 * instead of only manually. Schedule it once from anonymous Apex, e.g.
 * weekly at 6am Monday:
 *
 *   String cron = '0 0 6 ? * MON';
 *   System.schedule('Weekly Data Quality Scorecard', cron, new DataQualityScorecardScheduler());
 *
 * See scripts/run-scorecard.apex for a ready-to-paste version of that
 * snippet (and for a one-off manual run without scheduling anything).
 */
public with sharing class DataQualityScorecardScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        DataQualityScorecardService.runScorecard();
    }
}
