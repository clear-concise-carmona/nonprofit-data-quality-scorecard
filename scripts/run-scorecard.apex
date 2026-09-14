// Anonymous Apex - run this from Developer Console or `sf apex run` to
// trigger one scorecard run right now, without waiting for a schedule.
//
//   sf apex run --file scripts/run-scorecard.apex --target-org your-alias
//
Data_Quality_Snapshot__c snapshot = DataQualityScorecardService.runScorecard();
System.debug('Data model detected: ' + snapshot.Data_Model_Detected__c);
System.debug('Overall score: ' + snapshot.Overall_Score__c);
System.debug('Snapshot Id: ' + snapshot.Id);
if (String.isNotBlank(snapshot.Notes__c)) {
    System.debug('Notes (metrics that were not applicable):');
    System.debug(snapshot.Notes__c);
}

// To run this on a recurring schedule instead of manually, run once:
//
//   String cronExpression = '0 0 6 ? * MON'; // 6am every Monday
//   System.schedule('Weekly Data Quality Scorecard', cronExpression, new DataQualityScorecardScheduler());
