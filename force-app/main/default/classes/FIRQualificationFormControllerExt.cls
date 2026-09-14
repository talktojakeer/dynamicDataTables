public class FIRQualificationFormControllerExt {

    private final ApexPages.StandardController stdCtrl;

    // Fixed weapon rows shown on the official form, in order.
    public static final List<String> WEAPON_ROWS = new List<String>{
        'Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle'
    };

    public FIRQualificationFormControllerExt(ApexPages.StandardController controller) {
        this.stdCtrl = controller;
    }

    // Current date/time in Central Time (America/Chicago)
    public String getCurrentCentralDateTime() {
        return DateTime.now().format('MMMM dd, yyyy hh:mm a', 'America/Chicago');
    }

    // Map of Weapon_Type__c -> detail, PRE-SEEDED with an empty record for every
    // fixed row so the page can safely bind {!weaponByType['Pistol 1'].Qualified__c}
    // even when a weapon has no detail (renders blank instead of erroring).
    // Pre-computed row for the PDF grid: only weapons that have data, with all
    // display values + checkmark strings resolved in Apex (avoids the fragile
    // apex:variable-in-repeat pattern that throws "tmpVar1" in Visualforce).
    public class WeaponRow {
        public String weaponLabel      { get; set; }
        public String sightIron        { get; set; }
        public String sightOptic       { get; set; }
        public String sightMagnified   { get; set; }
        public String sightThirdLabel  { get; set; }
        public String manufacturerModel{ get; set; }
        public String weaponCode       { get; set; }
        public String qualifiedYes     { get; set; }
        public String qualifiedNo      { get; set; }
        public String qualified90Yes   { get; set; }
        public String qualified90No    { get; set; }
        public String attemptDate      { get; set; }
    }

    private static final String CK = '\u2713'; // check mark

    public List<WeaponRow> getWeaponRows() {
        List<WeaponRow> rows = new List<WeaponRow>();
        Id recId = stdCtrl.getId();
        if (recId == null) return rows;

        // Load real details, keyed by weapon type.
        Map<String, FIR_Weapon_Qualification_Detail__c> byType =
            new Map<String, FIR_Weapon_Qualification_Detail__c>();
        for (FIR_Weapon_Qualification_Detail__c d : [
            SELECT Weapon_Type__c, Other_Weapon_Type__c, Sight_Type__c, Manufacturer__c,
                   Model__c, Weapon_Code__c, Qualified__c, Qualified_at_90__c,
                   Qualification_Attempt__c, Attempt_Date__c
            FROM   FIR_Weapon_Qualification_Detail__c
            WHERE  FIR_Qualification_Form__c = :recId
        ]) {
            if (String.isNotBlank(d.Weapon_Type__c)) byType.put(d.Weapon_Type__c, d);
        }

        // Official order first, then any extras (e.g. Other).
        List<String> order = new List<String>();
        for (String w : WEAPON_ROWS) if (byType.containsKey(w)) order.add(w);
        for (String k : byType.keySet()) if (!order.contains(k)) order.add(k);

        for (String w : order) {
            FIR_Weapon_Qualification_Detail__c d = byType.get(w);
            WeaponRow r = new WeaponRow();
            r.weaponLabel = (w == 'Other' && String.isNotBlank(d.Other_Weapon_Type__c))
                            ? d.Other_Weapon_Type__c : w;
            r.sightIron       = (d.Sight_Type__c == 'Iron Sight') ? CK : '';
            r.sightOptic      = (d.Sight_Type__c == 'Optic') ? CK : '';
            r.sightMagnified  = (d.Sight_Type__c == 'Magnified Optic' || d.Sight_Type__c == 'Scope') ? CK : '';
            r.sightThirdLabel = (w == 'Precision Rifle') ? 'Scope**' : 'Magnified Optic*';
            r.manufacturerModel = ((d.Manufacturer__c == null ? '' : d.Manufacturer__c) + ' ' +
                                   (d.Model__c == null ? '' : d.Model__c)).trim();
            r.weaponCode      = d.Weapon_Code__c;
            r.qualifiedYes    = (d.Qualified__c == 'Yes') ? CK : '';
            r.qualifiedNo     = (d.Qualified__c == 'No') ? CK : '';
            r.qualified90Yes  = (d.Qualified_at_90__c == 'Yes') ? CK : '';
            r.qualified90No   = (d.Qualified_at_90__c == 'No') ? CK : '';
            r.attemptDate     = (d.Attempt_Date__c != null) ? d.Attempt_Date__c.format() : '';
            rows.add(r);
        }
        return rows;
    }
}