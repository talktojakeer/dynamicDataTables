/**
 * QualRosterController.cls
 *
 * ── Object Map ────────────────────────────────────────────────────────────
 *
 *  Account (FAQP_Account RecordType)
 *    └── Contact_Member__c  (Recruit_Class__c MD → Account)
 *          └── Contact__c   (MD → Contact)
 *
 *  Contact
 *    └── FIR_Form__c        (Contact.FIR_Form__c  Lookup → FIR_Form__c)
 *
 *  FIR_Form__c
 *    ├── Test_Date__c            Date
 *    ├── Firearm_Instructor__c   Lookup → User
 *    ├── Location__c             Text(255)
 *    └── Weapon_Qualification__c (FIR_Form__c MD → FIR_Form__c)  ← children
 *
 *  Weapon_Qualification__c
 *    ├── Weapon__c               Picklist  (Pistol | Shot Gun | Riffle)
 *    ├── Attempt_Date__c         Date
 *    ├── Qualified__c            Checkbox
 *    └── Qualified_90__c         Checkbox
 *
 * ─────────────────────────────────────────────────────────────────────────
 * NO Case object is used anywhere in this controller.
 */
public with sharing class QualRosterController {
 
    // ─── 1. Load Contact_Member__c records for a Recruit Class ────────────
    @AuraEnabled(cacheable=true)
    public static List<Contact_Member__c> getRecruitClassMembers(Id recruitClassId) {
        if (recruitClassId == null) return new List<Contact_Member__c>();
 
        return [
            SELECT
                Id,
                Name 
            FROM Contact_Member__c
            WHERE Recruit_Class__c = :recruitClassId
            ORDER BY Contact__r.Name ASC
            LIMIT 500
        ];
    }
 
    // ─── 2. Add To Roster ─────────────────────────────────────────────────
    // For each selected Contact_Member__c:
    //   a. Create FIR_Form__c  (Test_Date__c, Location__c, Firearm_Instructor__c)
    //   b. Create 3 × Weapon_Qualification__c children  (Pistol / Shot Gun / Riffle)
    //   c. Update Contact.FIR_Form__c = new FIR Form Id
    @AuraEnabled
    public static Integer addToRoster(
        List<Id> contactMemberIds,
        Id       recruitClassId,
        Date     testDate,
        String   firearmInstructor,
        String   location
    ) {
        if (contactMemberIds == null || contactMemberIds.isEmpty()) return 0;
 
        // a. Fetch member + contact details
        List<Contact_Member__c> members = [
            SELECT Id, Contact__c, Contact__r.Name
            FROM Contact_Member__c
            WHERE Id IN :contactMemberIds
        ];
 
        // b. Resolve Firearm Instructor name → User Id (optional)
        Id instructorId = null;
        if (String.isNotBlank(firearmInstructor)) {
            List<User> users = [
                SELECT Id
                FROM User
                WHERE Name LIKE :('%' + firearmInstructor.trim() + '%')
                AND IsActive = true
                LIMIT 1
            ];
            if (!users.isEmpty()) instructorId = users[0].Id;
        }
 
        // c. Build and insert FIR_Form__c records (one per member)
        List<FIR_Form__c> firForms = new List<FIR_Form__c>();
        for (Contact_Member__c m : members) {
            FIR_Form__c fir = new FIR_Form__c(
                Name         = m.Contact__r.Name + ' – FIR',
                Test_Date__c = testDate,
                Location__c  = location
            );
            if (instructorId != null) {
                //fir.Firearm_Instructor__c = instructorId;
            }
            firForms.add(fir);
        }
        insert firForms;
 
        // d. Build member Id → FIR Form Id map
        Map<Id, Id> memberToFir = new Map<Id, Id>();
        for (Integer i = 0; i < members.size(); i++) {
            memberToFir.put(members[i].Id, firForms[i].Id);
        }
 
        // e. Build and insert Weapon_Qualification__c children
        //    3 rows per FIR Form: Pistol, Shot Gun, Riffle
        List<Weapon_Qualification__c> weapons = new List<Weapon_Qualification__c>();
        for (FIR_Form__c fir : firForms) {
            for (String weaponType : new List<String>{ 'Pistol', 'Shot Gun', 'Riffle' }) {
                weapons.add(new Weapon_Qualification__c(
                    FIR_Form__c     = fir.Id,
                    Weapon__c       = weaponType,
                    Attempt_Date__c = testDate
                ));
            }
        }
        insert weapons;
 
        // f. Update Contact.FIR_Form__c lookup → link contact to their FIR Form
        List<Contact> contactUpdates = new List<Contact>();
        for (Contact_Member__c m : members) {
            contactUpdates.add(new Contact(
                Id          = m.Contact__c,
                FIR_Form__c = memberToFir.get(m.Id)
            ));
        }
        update contactUpdates;
 
        return members.size();
    }
 
    // ─── 3. Remove From Roster ────────────────────────────────────────────
    // a. Null Contact.FIR_Form__c  (avoids delete constraint error)
    // b. Delete FIR_Form__c records
    //    → Weapon_Qualification__c cascade-deletes via Master-Detail
    @AuraEnabled
    public static void removeFromRoster(List<Id> contactMemberIds) {
        if (contactMemberIds == null || contactMemberIds.isEmpty()) return;
 
        List<Contact_Member__c> members = [
            SELECT Id, Contact__c, Contact__r.FIR_Form__c
            FROM Contact_Member__c
            WHERE Id IN :contactMemberIds
        ];
 
        Set<Id>       firFormIds = new Set<Id>();
        List<Contact> toNull     = new List<Contact>();
 
        for (Contact_Member__c m : members) {
            if (m.Contact__r.FIR_Form__c != null) {
                firFormIds.add(m.Contact__r.FIR_Form__c);
                toNull.add(new Contact(Id = m.Contact__c, FIR_Form__c = null));
            }
        }
 
        // Null the lookup first to release the constraint
        if (!toNull.isEmpty()) update toNull;
 
        // Delete FIR Forms → Weapon_Qualification__c auto-deleted (Master-Detail)
        if (!firFormIds.isEmpty()) {
            delete [SELECT Id FROM FIR_Form__c WHERE Id IN :firFormIds];
        }
    }
}