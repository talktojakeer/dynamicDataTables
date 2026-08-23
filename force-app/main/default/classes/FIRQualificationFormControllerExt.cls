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
    public Map<String, FIR_Weapon_Qualification_Detail__c> getWeaponByType() {
        Map<String, FIR_Weapon_Qualification_Detail__c> m =
            new Map<String, FIR_Weapon_Qualification_Detail__c>();

        for (String w : WEAPON_ROWS) {
            m.put(w, new FIR_Weapon_Qualification_Detail__c(Weapon_Type__c = w));
        }

        Id recId = stdCtrl.getId();
        if (recId == null) return m;

        for (FIR_Weapon_Qualification_Detail__c d : [
            SELECT Weapon_Type__c, Sight_Type__c, Manufacturer__c, Model__c,
                   Weapon_Code__c, Qualified__c, Qualified_at_90__c,
                   Qualification_Attempt__c, Attempt_Date__c
            FROM   FIR_Weapon_Qualification_Detail__c
            WHERE  FIR_Qualification_Form__c = :recId
        ]) {
            if (String.isNotBlank(d.Weapon_Type__c)) {
                m.put(d.Weapon_Type__c, d);
            }
        }
        return m;
    }
}