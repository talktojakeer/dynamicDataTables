public with sharing class QualRosterGradingController {

    // -----------------------------------------------------------------------
    // Get roster labels as structured rows for ListView display.
    // Returns label, test date, location, instructor, member count, created date.
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static List<RosterLabelRow> getRosterLabelDetails() {
        Id userId = UserInfo.getUserId();

        // Query all forms for this instructor, grouped info per label
        List<FIR_Qualification_Form__c> forms = [
            SELECT Id,
                   Qual_Roster_Label__c,
                   Test_Date__c,
                   Location__c,
                   Firearms_Instrutor__r.Name,
                   CreatedDate
            FROM   FIR_Qualification_Form__c
            WHERE  Firearms_Instrutor__c = :userId
            AND    Qual_Roster_Label__c != null
            ORDER BY CreatedDate DESC
        ];

        // Group by label — take first form's details, count members
        Map<String, RosterLabelRow> labelMap = new Map<String, RosterLabelRow>();
        Map<String, Integer>        countMap = new Map<String, Integer>();
        List<String> orderedLabels = new List<String>();

        for (FIR_Qualification_Form__c f : forms) {
            String lbl = f.Qual_Roster_Label__c;
            if (!labelMap.containsKey(lbl)) {
                RosterLabelRow row = new RosterLabelRow();
                row.rosterLabel    = lbl;
                row.testDate       = f.Test_Date__c != null ? String.valueOf(f.Test_Date__c) : '';
                row.location       = f.Location__c != null ? f.Location__c : '';
                row.instructorName = f.Firearms_Instrutor__r != null
                                     ? f.Firearms_Instrutor__r.Name : '';
                row.createdDate    = f.CreatedDate != null
                                     ? f.CreatedDate.format('MM/dd/yyyy hh:mm a') : '';
                labelMap.put(lbl, row);
                countMap.put(lbl, 0);
                orderedLabels.add(lbl);
            }
            countMap.put(lbl, countMap.get(lbl) + 1);
        }

        List<RosterLabelRow> result = new List<RosterLabelRow>();
        for (String lbl : orderedLabels) {
            RosterLabelRow row = labelMap.get(lbl);
            row.memberCount    = countMap.get(lbl);
            result.add(row);
        }
        return result;
    }

    // -----------------------------------------------------------------------
    // Get distinct Qual Roster Labels (simple string list — kept for backward compat)
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static List<String> getRosterLabels() {
        Id userId = UserInfo.getUserId();
        List<String> labels = new List<String>();
        Set<String> seen    = new Set<String>();

        for (FIR_Qualification_Form__c f : [
            SELECT Qual_Roster_Label__c
            FROM   FIR_Qualification_Form__c
            WHERE  Firearms_Instrutor__c = :userId
            AND    Qual_Roster_Label__c != null
            ORDER BY Qual_Roster_Label__c ASC
        ]) {
            if (!seen.contains(f.Qual_Roster_Label__c)) {
                seen.add(f.Qual_Roster_Label__c);
                labels.add(f.Qual_Roster_Label__c);
            }
        }
        return labels;
    }

    // -----------------------------------------------------------------------
    // Get full grading data for a selected Roster Label.
    // Returns session header + members grouped by weapon type.
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static RosterGradingWrapper getRosterGradingData(String rosterLabel) {
        if (String.isBlank(rosterLabel)) {
            throw new AuraHandledException('Roster Label is required.');
        }

        RosterGradingWrapper wrapper = new RosterGradingWrapper();

        List<FIR_Qualification_Form__c> forms = [
            SELECT Id,
                   Name,
                   ContactName__c,
                   ContactName__r.Name,
                   Test_Date__c,
                   Location__c,
                   Light_Condition__c,
                   Firearms_Instrutor__c,
                   Firearms_Instrutor__r.Name,
                   Qual_Roster_Label__c
            FROM   FIR_Qualification_Form__c
            WHERE  Qual_Roster_Label__c = :rosterLabel
            ORDER BY ContactName__r.Name ASC
        ];

        if (forms.isEmpty()) return wrapper;

        FIR_Qualification_Form__c first = forms[0];
        wrapper.rosterLabel    = rosterLabel;
        wrapper.testDate       = first.Test_Date__c != null
                                 ? String.valueOf(first.Test_Date__c) : '';
        wrapper.location       = first.Location__c != null ? first.Location__c : '';
        wrapper.lightCondition = first.Light_Condition__c != null ? first.Light_Condition__c : '';
        wrapper.instructorName = first.Firearms_Instrutor__r != null
                                 ? first.Firearms_Instrutor__r.Name : '';

        // Derive recruit class name from first Contact's ACR
        if (first.ContactName__c != null) {
            List<AccountContactRelation> acrs = [
                SELECT Account.Name
                FROM   AccountContactRelation
                WHERE  ContactId = :first.ContactName__c
                AND    Account.IsPersonAccount = false
                AND    IsActive = true
                LIMIT  1
            ];
            if (!acrs.isEmpty()) {
                wrapper.recruitClassName = acrs[0].Account.Name;
            }
        }

        Set<Id> formIds = new Set<Id>();
        Map<Id, String> formToMember = new Map<Id, String>();
        for (FIR_Qualification_Form__c f : forms) {
            formIds.add(f.Id);
            String memberName = f.ContactName__r != null ? f.ContactName__r.Name : '';
            formToMember.put(f.Id, memberName);
        }

        List<FIR_Weapon_Qualification_Detail__c> details = [
            SELECT Id,
                   FIR_Qualification_Form__c,
                   Weapon_Type__c,
                   Manufacturer__c,
                   Model__c,
                   Sight_Type__c,
                   Weapon_Code__c,
                   Qualification_Attempt__c,
                   Qualified__c,
                   Qualified_at_90__c
            FROM   FIR_Weapon_Qualification_Detail__c
            WHERE  FIR_Qualification_Form__c IN :formIds
            ORDER BY Weapon_Type__c ASC
        ];

        List<String> weaponOrder = new List<String>{
            'Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle'
        };
        Map<String, List<GradingRow>> weaponGroups = new Map<String, List<GradingRow>>();

        for (FIR_Weapon_Qualification_Detail__c d : details) {
            String weaponType = d.Weapon_Type__c;
            if (!weaponGroups.containsKey(weaponType)) {
                weaponGroups.put(weaponType, new List<GradingRow>());
            }
            GradingRow row          = new GradingRow();
            row.detailId            = d.Id;
            row.firFormId           = d.FIR_Qualification_Form__c;
            row.memberName          = formToMember.get(d.FIR_Qualification_Form__c);
            row.weaponType          = weaponType;
            row.manufacturer        = d.Manufacturer__c;
            row.model               = d.Model__c;
            row.sightType           = d.Sight_Type__c;
            row.weaponCode          = d.Weapon_Code__c;
            row.qualificationAttempt = d.Qualification_Attempt__c;
            row.qualified           = d.Qualified__c;
            row.qualified90         = d.Qualified_at_90__c;
            weaponGroups.get(weaponType).add(row);
        }

        for (String w : weaponOrder) {
            List<GradingRow> rows = weaponGroups.get(w);
            if (rows != null && !rows.isEmpty()) {
                WeaponSection section = new WeaponSection();
                section.weaponType   = w;
                section.rows         = rows;
                wrapper.weaponSections.add(section);
            }
        }

        return wrapper;
    }

    // -----------------------------------------------------------------------
    // Save a single grading row inline edit
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static void saveGradingRow(
        Id     detailId,
        String manufacturer,
        String model,
        String sightType,
        String weaponCode,
        String qualificationAttempt,
        String qualified,
        String qualified90
    ) {
        try {
            FIR_Weapon_Qualification_Detail__c detail =
                new FIR_Weapon_Qualification_Detail__c(Id = detailId);
            detail.Manufacturer__c          = manufacturer;
            detail.Model__c                 = model;
            detail.Sight_Type__c            = sightType;
            detail.Weapon_Code__c           = weaponCode;
            detail.Qualification_Attempt__c = qualificationAttempt;
            detail.Qualified__c             = qualified != null ? qualified : 'No';
            detail.Qualified_at_90__c       = qualified90 != null ? qualified90 : 'No';
            update detail;
        } catch (Exception ex) {
            throw new AuraHandledException('Save failed: ' + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Inner wrapper classes
    // -----------------------------------------------------------------------
    public class RosterLabelRow {
        @AuraEnabled public String  rosterLabel    = '';
        @AuraEnabled public String  testDate       = '';
        @AuraEnabled public String  location       = '';
        @AuraEnabled public String  instructorName = '';
        @AuraEnabled public Integer memberCount    = 0;
        @AuraEnabled public String  createdDate    = '';
    }

    public class RosterGradingWrapper {
        @AuraEnabled public String              rosterLabel      = '';
        @AuraEnabled public String              testDate         = '';
        @AuraEnabled public String              location         = '';
        @AuraEnabled public String              lightCondition   = '';
        @AuraEnabled public String              instructorName   = '';
        @AuraEnabled public String              recruitClassName = '';
        @AuraEnabled public List<WeaponSection> weaponSections   = new List<WeaponSection>();
    }

    public class WeaponSection {
        @AuraEnabled public String           weaponType = '';
        @AuraEnabled public List<GradingRow> rows       = new List<GradingRow>();
    }

    public class GradingRow {
        @AuraEnabled public String detailId;
        @AuraEnabled public String firFormId;
        @AuraEnabled public String memberName;
        @AuraEnabled public String weaponType;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String sightType;
        @AuraEnabled public String weaponCode;
        @AuraEnabled public String qualificationAttempt;
        @AuraEnabled public String qualified;
        @AuraEnabled public String qualified90;
    }
}