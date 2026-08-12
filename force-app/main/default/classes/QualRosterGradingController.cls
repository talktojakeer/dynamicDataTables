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
                row.testDate       = formatDate(f.Test_Date__c);
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
                   ContactName__r.Account.Is_Firearms_Instructor__pc,
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
        wrapper.testDate       = formatDate(first.Test_Date__c);
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
        Map<Id, String>  formToMember      = new Map<Id, String>();
        Map<Id, Boolean> formToInstructor  = new Map<Id, Boolean>();
        Map<Id, Boolean> formToRosterInstr = new Map<Id, Boolean>();
        for (FIR_Qualification_Form__c f : forms) {
            formIds.add(f.Id);
            String memberName = f.ContactName__r != null ? f.ContactName__r.Name : '';
            formToMember.put(f.Id, memberName);
            Boolean isInstr = f.ContactName__r != null
                              && f.ContactName__r.Account != null
                              && f.ContactName__r.Account.Is_Firearms_Instructor__pc == true;
            formToInstructor.put(f.Id, isInstr);

            // Witness required only when the roster's OWN certifying instructor
            // (Firearms_Instrutor__c) is one of the graded members - matched by name.
            String rosterInstrName = f.Firearms_Instrutor__r != null ? f.Firearms_Instrutor__r.Name : '';
            Boolean isRosterInstr = String.isNotBlank(memberName)
                                    && String.isNotBlank(rosterInstrName)
                                    && memberName.trim().equalsIgnoreCase(rosterInstrName.trim());
            formToRosterInstr.put(f.Id, isRosterInstr);
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
            'Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle', 'Other'
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
            row.isFirearmsInstructor = formToInstructor.get(d.FIR_Qualification_Form__c) == true;
            row.isRosterInstructor   = formToRosterInstr.get(d.FIR_Qualification_Form__c) == true;
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
            detail.Qualified__c             = String.isNotBlank(qualified) ? qualified : 'Yes';
            detail.Qualified_at_90__c       = String.isNotBlank(qualified90) ? qualified90 : 'No';
            update detail;
        } catch (Exception ex) {
            throw new AuraHandledException('Save failed: ' + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Format a Date as MM/DD/YYYY
    // -----------------------------------------------------------------------
    private static String formatDate(Date d) {
        if (d == null) return '';
        String mm = (d.month() < 10 ? '0' : '') + String.valueOf(d.month());
        String dd = (d.day()   < 10 ? '0' : '') + String.valueOf(d.day());
        String yyyy = String.valueOf(d.year());
        return mm + '/' + dd + '/' + yyyy;
    }

    // -----------------------------------------------------------------------
    // Save the firearm instructor signature (base64), and the witness
    // signature when one is required, to all FIR forms in a roster.
    // Stored in Firearms_Instructor_Signature__c / Witness_Signature__c
    // (both Rich Text / Html fields). The base64 data URL is wrapped in an
    // <img> tag so the field renders the signature inline on the record page.
    // A witness is only required when the FI themselves is one of the graded
    // members on this roster - the caller (LWC) decides that and only sends
    // witnessName/witnessSignature then.
    // @param rosterLabel        - the roster whose forms get the signatures
    // @param instructorSignature - base64 data URL string, always required
    // @param witnessName        - witness's typed full name, optional
    // @param witnessSignature   - base64 data URL string, optional
    // -----------------------------------------------------------------------
    private static final Integer RICH_TEXT_MAX = 131072;

    // Wrap a base64 data URL as an <img> so a Rich Text (Html) field renders
    // it inline. Returns null for blank input; passes through if already HTML.
    private static String toSignatureImg(String dataUrl, String altText) {
        if (String.isBlank(dataUrl)) return null;
        if (dataUrl.trim().startsWith('<img')) return dataUrl; // already wrapped
        return '<img src="' + dataUrl + '" alt="' + altText +
               '" style="max-width:100%;height:auto;" />';
    }

    @AuraEnabled
    public static void saveSignatures(
        String rosterLabel,
        String instructorSignature,
        String witnessName,
        String witnessSignature,
        String witnessSignatureDate
    ) {
        if (String.isBlank(rosterLabel)) {
            throw new AuraHandledException('Roster label is required.');
        }
        if (String.isBlank(instructorSignature)) {
            throw new AuraHandledException('Firearm instructor signature is required.');
        }

        // Wrap as inline <img> HTML for the Rich Text fields
        String instructorHtml = toSignatureImg(instructorSignature, 'Firearm Instructor Signature');
        if (instructorHtml != null && instructorHtml.length() > RICH_TEXT_MAX) {
            throw new AuraHandledException('Instructor signature image is too large to store. Please try a simpler signature.');
        }

        Boolean hasWitnessSignature = String.isNotBlank(witnessSignature);
        String  witnessHtml         = null;
        Date    witnessDate         = null;
        if (hasWitnessSignature) {
            witnessHtml = toSignatureImg(witnessSignature, 'Witness Signature');
            if (witnessHtml != null && witnessHtml.length() > RICH_TEXT_MAX) {
                throw new AuraHandledException('Witness signature image is too large to store. Please try a simpler signature.');
            }
            // Expect ISO 'yyyy-MM-dd' from the client; fall back to today.
            try {
                witnessDate = String.isNotBlank(witnessSignatureDate)
                              ? Date.valueOf(witnessSignatureDate) : Date.today();
            } catch (Exception e) {
                witnessDate = Date.today();
            }
        }

        try {
            List<FIR_Qualification_Form__c> forms = [
                SELECT Id
                FROM   FIR_Qualification_Form__c
                WHERE  Qual_Roster_Label__c = :rosterLabel
            ];
            if (forms.isEmpty()) {
                throw new AuraHandledException('No qualification forms found for this roster.');
            }
            for (FIR_Qualification_Form__c f : forms) {
                f.Firearms_Instructor_Signature__c = instructorHtml;
                if (hasWitnessSignature) {
                    f.Witness_Signature__c = witnessHtml;
                    f.Witness_Name__c      = witnessName;
                    f.Witness_Signature_Date__c = witnessDate;
                }
            }
            update forms;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to save signature: ' + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Get Weapon_Code__c picklist values from object metadata
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<String> getWeaponCodeOptions() {
        List<String> options = new List<String>();
        Schema.DescribeFieldResult dfr = FIR_Weapon_Qualification_Detail__c.Weapon_Code__c.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                options.add(pe.getValue());
            }
        }
        return options;
    }

    // Person Account record type used for employees.
    private static final String EMPLOYEE_RT = 'PersonAccount';

    // -----------------------------------------------------------------------
    // Return ALL Person Account employees for the "Add to Roster" picker,
    // each annotated with the weapon types they are ALREADY on for this
    // roster. Employees are NOT hidden when already on the roster, because
    // they may still be missing other weapon types (dedup happens per
    // weapon type at insert time, not per roster).
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static List<AvailableEmployee> getAvailableEmployees(String rosterLabel) {
        if (String.isBlank(rosterLabel)) {
            throw new AuraHandledException('Roster Label is required.');
        }

        // Map shadow Contact Id -> set of weapon types already on this roster
        Map<Id, Set<String>> contactToWeaponTypes = new Map<Id, Set<String>>();
        for (FIR_Weapon_Qualification_Detail__c d : [
            SELECT Weapon_Type__c, FIR_Qualification_Form__r.ContactName__c
            FROM   FIR_Weapon_Qualification_Detail__c
            WHERE  FIR_Qualification_Form__r.Qual_Roster_Label__c = :rosterLabel
            AND    FIR_Qualification_Form__r.ContactName__c != null
        ]) {
            Id cId = d.FIR_Qualification_Form__r.ContactName__c;
            if (!contactToWeaponTypes.containsKey(cId)) {
                contactToWeaponTypes.put(cId, new Set<String>());
            }
            if (String.isNotBlank(d.Weapon_Type__c)) {
                contactToWeaponTypes.get(cId).add(d.Weapon_Type__c);
            }
        }

        List<AvailableEmployee> result = new List<AvailableEmployee>();
        for (Account a : [
            SELECT Id, Name, PersonContactId, Is_Firearms_Instructor__pc
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    PersonContactId != null
            ORDER BY Name ASC
            LIMIT  2000
        ]) {
            AvailableEmployee e    = new AvailableEmployee();
            e.accountId            = a.Id;
            e.contactId            = a.PersonContactId;
            e.name                 = a.Name;
            e.isFirearmsInstructor = a.Is_Firearms_Instructor__pc == true;
            Set<String> existing   = contactToWeaponTypes.get(a.PersonContactId);
            e.existingWeaponTypes  = existing != null
                                     ? new List<String>(existing)
                                     : new List<String>();
            result.add(e);
        }
        return result;
    }

    // -----------------------------------------------------------------------
    // Add selected employees to a roster for selected weapon types.
    //  - An employee already on the roster reuses their existing form.
    //  - A weapon type the employee already has is skipped (no duplicate).
    //  - Missing weapon types are added as new detail rows, optionally
    //    pre-filled with manufacturer / model / sight type.
    // Returns { employeesAffected, rowsAdded, rowsSkipped }.
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static AddToRosterResult addToRoster(
        String rosterLabel,
        List<String> contactIds,
        List<String> weaponTypes,
        String manufacturer,
        String model,
        String sightType
    ) {
        if (String.isBlank(rosterLabel)) {
            throw new AuraHandledException('Roster Label is required.');
        }
        if (contactIds == null || contactIds.isEmpty()) {
            throw new AuraHandledException('Select at least one employee.');
        }
        if (weaponTypes == null || weaponTypes.isEmpty()) {
            throw new AuraHandledException('Select at least one weapon type.');
        }

        // Roster-level context copied onto any new form
        List<FIR_Qualification_Form__c> template = [
            SELECT Test_Date__c, Location__c, Light_Condition__c, Firearms_Instrutor__c
            FROM   FIR_Qualification_Form__c
            WHERE  Qual_Roster_Label__c = :rosterLabel
            LIMIT  1
        ];
        if (template.isEmpty()) {
            throw new AuraHandledException('No existing forms found for this roster.');
        }
        FIR_Qualification_Form__c ctx = template[0];

        Set<Id> selectedContacts = new Set<Id>();
        for (String cId : contactIds) {
            if (String.isNotBlank(cId)) selectedContacts.add((Id) cId);
        }

        // Existing forms on this roster for the selected employees
        Map<Id, Id> contactToFormId = new Map<Id, Id>();
        for (FIR_Qualification_Form__c f : [
            SELECT Id, ContactName__c
            FROM   FIR_Qualification_Form__c
            WHERE  Qual_Roster_Label__c = :rosterLabel
            AND    ContactName__c IN :selectedContacts
        ]) {
            contactToFormId.put(f.ContactName__c, f.Id);
        }

        // Existing (formId + weaponType) pairs so we never duplicate a row
        Set<String> existingPairs = new Set<String>();
        if (!contactToFormId.values().isEmpty()) {
            for (FIR_Weapon_Qualification_Detail__c d : [
                SELECT FIR_Qualification_Form__c, Weapon_Type__c
                FROM   FIR_Weapon_Qualification_Detail__c
                WHERE  FIR_Qualification_Form__c IN :contactToFormId.values()
            ]) {
                existingPairs.add(d.FIR_Qualification_Form__c + '|' + d.Weapon_Type__c);
            }
        }

        // Member names for the form's Name field ("<Member> - FIR")
        Map<Id, String> contactNames = new Map<Id, String>();
        for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :selectedContacts]) {
            contactNames.put(c.Id, c.Name);
        }

        try {
            // 1) Create forms for employees not yet on the roster
            List<FIR_Qualification_Form__c> newForms = new List<FIR_Qualification_Form__c>();
            List<Id> contactsNeedingForm = new List<Id>();
            for (Id cId : selectedContacts) {
                if (!contactToFormId.containsKey(cId)) {
                    contactsNeedingForm.add(cId);
                    String mName = contactNames.containsKey(cId) ? contactNames.get(cId) : 'Unknown';
                    newForms.add(new FIR_Qualification_Form__c(
                        Name                  = mName + ' - FIR',
                        ContactName__c        = cId,
                        Qual_Roster_Label__c  = rosterLabel,
                        Test_Date__c          = ctx.Test_Date__c,
                        Location__c           = ctx.Location__c,
                        Light_Condition__c    = ctx.Light_Condition__c,
                        Firearms_Instrutor__c = ctx.Firearms_Instrutor__c
                    ));
                }
            }
            if (!newForms.isEmpty()) {
                insert newForms;
                for (Integer i = 0; i < newForms.size(); i++) {
                    contactToFormId.put(contactsNeedingForm[i], newForms[i].Id);
                }
            }

            // 2) Add missing weapon rows only
            Integer rowsAdded   = 0;
            Integer rowsSkipped = 0;
            Set<Id> affected    = new Set<Id>();
            List<FIR_Weapon_Qualification_Detail__c> newDetails =
                new List<FIR_Weapon_Qualification_Detail__c>();

            for (Id cId : selectedContacts) {
                Id formId = contactToFormId.get(cId);
                if (formId == null) continue;
                for (String wt : weaponTypes) {
                    if (String.isBlank(wt)) continue;
                    String key = formId + '|' + wt;
                    if (existingPairs.contains(key)) {
                        rowsSkipped++;
                        continue;
                    }
                    existingPairs.add(key); // guard against dup weapon types in the same request
                    FIR_Weapon_Qualification_Detail__c det = new FIR_Weapon_Qualification_Detail__c(
                        FIR_Qualification_Form__c = formId,
                        Weapon_Type__c            = wt
                    );
                    if (String.isNotBlank(manufacturer)) det.Manufacturer__c = manufacturer;
                    if (String.isNotBlank(model))        det.Model__c        = model;
                    if (String.isNotBlank(sightType))    det.Sight_Type__c   = sightType;
                    newDetails.add(det);
                    affected.add(cId);
                    rowsAdded++;
                }
            }

            if (!newDetails.isEmpty()) {
                insert newDetails;
            }

            AddToRosterResult res = new AddToRosterResult();
            res.employeesAffected = affected.size();
            res.rowsAdded         = rowsAdded;
            res.rowsSkipped       = rowsSkipped;
            return res;

        } catch (Exception ex) {
            throw new AuraHandledException('Failed to add to roster: ' + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Create a brand-new employee Person Account (e.g. a retired officer not
    // yet in the system) and return it so the UI can select and add it.
    // isRetired maps to Active__c = 'No' when true, 'Yes' otherwise.
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static void trySet(SObject rec, String field, Object val) {
        if (val == null) return;
        try { rec.put(field, val); } catch (Exception e) { /* field absent - skip */ }
    }
    @AuraEnabled
    public static AvailableEmployee createEmployee(
        String firstName,
        String middleName,
        String lastName,
        String dateOfBirth,
        String yearRetired,
        String retiredType,
        Boolean isRetired
    ) {
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last name is required.');
        }

        Id rtId;
        try {
            rtId = Schema.SObjectType.Account
                       .getRecordTypeInfosByDeveloperName()
                       .get(EMPLOYEE_RT).getRecordTypeId();
        } catch (Exception e) {
            rtId = null;
        }
        if (rtId == null) {
            throw new AuraHandledException('Employee record type not found. Check the "' + EMPLOYEE_RT + '" record type.');
        }

        Account acc = new Account(
            RecordTypeId = rtId,
            FirstName    = String.isNotBlank(firstName) ? firstName.trim() : null,
            LastName     = lastName.trim(),
            Active__c    = (isRetired == true) ? 'No' : 'Yes'
        );

        trySet(acc, 'MiddleName', String.isNotBlank(middleName) ? (Object) middleName.trim() : null);
        if (String.isNotBlank(dateOfBirth)) {
            try { acc.put('PersonBirthdate', Date.valueOf(dateOfBirth)); } catch (Exception e) {}
        }
        if (String.isNotBlank(yearRetired)) {
            try { acc.put('Year_Retired__pc', Integer.valueOf(yearRetired)); }
            catch (Exception e) { trySet(acc, 'Year_Retired__pc', yearRetired); }
        }
        trySet(acc, 'FAQP_Retired_Peace_Officer_Type__c', String.isNotBlank(retiredType) ? (Object) retiredType.trim() : null);

        try {
            insert acc;
            Account created = [
                SELECT Id, Name, PersonContactId, Is_Firearms_Instructor__pc
                FROM   Account
                WHERE  Id = :acc.Id
                LIMIT  1
            ];
            AvailableEmployee e    = new AvailableEmployee();
            e.accountId            = created.Id;
            e.contactId            = created.PersonContactId;
            e.name                 = created.Name;
            e.isFirearmsInstructor = created.Is_Firearms_Instructor__pc == true;
            e.existingWeaponTypes  = new List<String>();
            return e;
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to create employee: ' + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Inner wrapper classes
    // -----------------------------------------------------------------------
    public class AddToRosterResult {
        @AuraEnabled public Integer employeesAffected = 0;
        @AuraEnabled public Integer rowsAdded         = 0;
        @AuraEnabled public Integer rowsSkipped       = 0;
    }

    public class AvailableEmployee {
        @AuraEnabled public String       accountId;
        @AuraEnabled public String       contactId;
        @AuraEnabled public String       name;
        @AuraEnabled public Boolean      isFirearmsInstructor;
        @AuraEnabled public List<String> existingWeaponTypes = new List<String>();
    }

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
        @AuraEnabled public Boolean isFirearmsInstructor;
        @AuraEnabled public Boolean isRosterInstructor;
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