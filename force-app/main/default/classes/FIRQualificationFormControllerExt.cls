public class FIRQualificationFormControllerExt {

    private final ApexPages.StandardController stdCtrl;

    private static final List<String> WEAPON_ORDER = new List<String>{
        'Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle'
    };

    public FIRQualificationFormControllerExt(ApexPages.StandardController controller) {
        this.stdCtrl = controller;
    }

    public String getCurrentCentralDateTime() {
        return DateTime.now().format('MMMM dd, yyyy hh:mm a', 'America/Chicago');
    }

    public String getInstructorSignatureUrl() {
        FIR_Qualification_Form__c formRecord = getSignatureRecord();
        if (formRecord == null || String.isBlank(formRecord.Firearms_Instructor_Signature__c)) {
            return '';
        }
        return extractImageUrl(formRecord.Firearms_Instructor_Signature__c);
    }

    public String getWitnessSignatureUrl() {
        FIR_Qualification_Form__c formRecord = getSignatureRecord();
        if (formRecord == null || String.isBlank(formRecord.Witness_Signature__c)) {
            return '';
        }
        return extractImageUrl(formRecord.Witness_Signature__c);
    }

    private FIR_Qualification_Form__c getSignatureRecord() {
        Id formId = stdCtrl.getId();
        if (formId == null) {
            return null;
        }
        List<FIR_Qualification_Form__c> records = [
            SELECT Id, Firearms_Instructor_Signature__c, Witness_Signature__c
            FROM FIR_Qualification_Form__c
            WHERE Id = :formId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private String extractImageUrl(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        String marker = 'src="';
        Integer startPosition = html.indexOf(marker);
        if (startPosition >= 0) {
            startPosition = startPosition + marker.length();
            Integer endPosition = html.indexOf('"', startPosition);
            if (endPosition > startPosition) {
                return html.substring(startPosition, endPosition).replace('&amp;', '&');
            }
        }

        marker = 'src=\'';
        startPosition = html.indexOf(marker);
        if (startPosition >= 0) {
            startPosition = startPosition + marker.length();
            Integer endPosition = html.indexOf('\'', startPosition);
            if (endPosition > startPosition) {
                return html.substring(startPosition, endPosition).replace('&amp;', '&');
            }
        }

        return '';
    }

    public class WeaponRow {
        public String weaponLabel       { get; set; }
        public String sightType         { get; set; }
        public String manufacturerModel { get; set; }
        public String weaponCode        { get; set; }
        public String qualified         { get; set; }
        public String qualifiedAt90     { get; set; }
        public String attemptDate       { get; set; }
    }

    public List<WeaponRow> getWeaponRows() {
        List<WeaponRow> rows = new List<WeaponRow>();

        Id formId = stdCtrl.getId();
        if (formId == null) {
            return rows;
        }

        List<FIR_Weapon_Qualification_Detail__c> details = [
            SELECT Id, Weapon_Type__c, Other_Weapon_Type__c, Sight_Type__c, Manufacturer__c,
                   Model__c, Weapon_Code__c, Qualified__c, Qualified_at_90__c,
                   Qualification_Attempt__c, Attempt_Date__c
            FROM FIR_Weapon_Qualification_Detail__c
            WHERE FIR_Qualification_Form__c = :formId
        ];

        if (details.isEmpty()) {
            return rows;
        }

        Map<String, FIR_Weapon_Qualification_Detail__c> detailByType =
            new Map<String, FIR_Weapon_Qualification_Detail__c>();

        for (FIR_Weapon_Qualification_Detail__c detail : details) {
            if (String.isBlank(detail.Weapon_Type__c)) {
                continue;
            }
            if (!detailByType.containsKey(detail.Weapon_Type__c)) {
                detailByType.put(detail.Weapon_Type__c, detail);
            }
        }

        for (String weaponType : WEAPON_ORDER) {
            if (detailByType.containsKey(weaponType)) {
                rows.add(buildWeaponRow(detailByType.get(weaponType)));
            }
        }

        for (String weaponType : detailByType.keySet()) {
            if (!WEAPON_ORDER.contains(weaponType)) {
                rows.add(buildWeaponRow(detailByType.get(weaponType)));
            }
        }

        return rows;
    }

    private WeaponRow buildWeaponRow(FIR_Weapon_Qualification_Detail__c detail) {
        WeaponRow row = new WeaponRow();

        row.weaponLabel = (detail.Weapon_Type__c == 'Other' && String.isNotBlank(detail.Other_Weapon_Type__c))
            ? detail.Other_Weapon_Type__c
            : detail.Weapon_Type__c;

        row.sightType = detail.Sight_Type__c;

        String manufacturer = detail.Manufacturer__c == null ? '' : detail.Manufacturer__c;
        String model        = detail.Model__c == null ? '' : detail.Model__c;
        row.manufacturerModel = (manufacturer + ' ' + model).trim();

        row.weaponCode    = detail.Weapon_Code__c;
        row.qualified     = detail.Qualified__c;
        row.qualifiedAt90 = detail.Qualified_at_90__c;
        row.attemptDate   = (detail.Attempt_Date__c != null) ? detail.Attempt_Date__c.format() : '';

        return row;
    }
}