import { LightningElement, wire } from 'lwc';
import getLatestSnapshot from '@salesforce/apex/DataQualityDashboardController.getLatestSnapshot';

// Percent-style fields render as a 0-100 bar. Count-style fields render as
// a plain number - there's no natural "full bar" scale for a raw count, so
// forcing one would be more misleading than just showing the number.
const PERCENT_FIELDS = [
    { field: 'Duplicate_Rate__c', label: 'Duplicate contact rate', lowerIsBetter: true },
    { field: 'Valid_Email_Percent__c', label: 'Valid email percent', lowerIsBetter: false },
    { field: 'Address_Completeness_Percent__c', label: 'Address completeness', lowerIsBetter: false },
    { field: 'Channel_Preference_Coverage_Percent__c', label: 'Channel preference coverage', lowerIsBetter: false },
    { field: 'Stale_Contacts_Percent__c', label: 'Stale contacts', lowerIsBetter: true },
    { field: 'Required_Field_Null_Rate_Percent__c', label: 'Required field null rate', lowerIsBetter: true }
];

const COUNT_FIELDS = [
    { field: 'Orphan_Gifts_Count__c', label: 'Orphan gifts' },
    { field: 'Unlinked_Soft_Credits_Count__c', label: 'Unlinked soft credits' },
    { field: 'Missing_Gau_Allocations_Count__c', label: 'Missing GAU allocations' },
    { field: 'Currency_Anomalies_Count__c', label: 'Currency anomalies' }
];

export default class DataQualityDashboard extends LightningElement {
    snapshot;
    isLoading = true;
    loadError;

    @wire(getLatestSnapshot)
    wiredSnapshot({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.snapshot = data;
            this.loadError = undefined;
        } else if (error) {
            this.loadError = 'Could not load the latest scorecard: ' + this.extractErrorMessage(error);
        }
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Unknown error';
    }

    get hasSnapshot() {
        return !!this.snapshot;
    }

    get formattedScore() {
        if (!this.snapshot || this.snapshot.Overall_Score__c === undefined || this.snapshot.Overall_Score__c === null) {
            return '--';
        }
        return Math.round(this.snapshot.Overall_Score__c * 10) / 10;
    }

    get scoreVerdict() {
        const score = this.snapshot ? this.snapshot.Overall_Score__c : null;
        if (score === undefined || score === null) {
            return '';
        }
        // 70 matches Data_Quality_Config__mdt's default Target_Score_Percent__c
        // and CCC's published "7 out of 10" audit threshold.
        return score >= 70 ? 'At or above target' : 'Below target';
    }

    get scoreBoxStyle() {
        const score = this.snapshot ? this.snapshot.Overall_Score__c : null;
        if (score === undefined || score === null) {
            return '';
        }
        const color = score >= 70 ? '#2e844a' : score >= 50 ? '#dd7a01' : '#ba0517';
        return `border-color: ${color}; color: ${color};`;
    }

    get metricRows() {
        if (!this.snapshot) {
            return [];
        }
        const percentRows = PERCENT_FIELDS.map((def) => this.buildPercentRow(def));
        const countRows = COUNT_FIELDS.map((def) => this.buildCountRow(def));
        return [...percentRows, ...countRows];
    }

    buildPercentRow(def) {
        const rawValue = this.snapshot[def.field];
        const applicable = rawValue !== undefined && rawValue !== null;
        if (!applicable) {
            return { key: def.field, label: def.label, applicable: false };
        }
        const barPercent = def.lowerIsBetter ? 100 - rawValue : rawValue;
        return {
            key: def.field,
            label: def.label,
            applicable: true,
            displayValue: `${rawValue}%`,
            barStyle: `width: ${Math.max(0, Math.min(100, barPercent))}%;`
        };
    }

    buildCountRow(def) {
        const rawValue = this.snapshot[def.field];
        const applicable = rawValue !== undefined && rawValue !== null;
        if (!applicable) {
            return { key: def.field, label: def.label, applicable: false };
        }
        const barPercent = rawValue === 0 ? 100 : Math.max(0, 100 - Math.min(rawValue, 50) * 2);
        return {
            key: def.field,
            label: def.label,
            applicable: true,
            displayValue: `${rawValue}`,
            barStyle: `width: ${barPercent}%;`
        };
    }
}
