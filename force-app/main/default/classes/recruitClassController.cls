/**
 * @description Controller for Recruit Class LWC components.
 *              Handles employee search, recruit class creation,
 *              duplicate validation, and member linking.
 *
 * Naming: PascalCase class, camelCase methods, UPPER_SNAKE_CASE constants.
 * Security: with sharing enforces record-level access.
 */
public with sharing class recruitClassController {

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    private static final String FAQP_ACCOUNT_RT   = 'FAQP_Account';
    private static final String PERSON_ACCOUNT_RT  = 'PersonAccount';
    private static final Integer SEARCH_LIMIT      = 50;

    // -----------------------------------------------------------------------
    // Search Person Account employees
    // @param searchKey   - name or TINS fragment to search
    // @param filterByKey - true = apply search filter, false = return all
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<Account> searchEmployees(String searchKey, Boolean filterByKey) {
        try {
            if (filterByKey == true && String.isNotBlank(searchKey)) {
                String key = searchKey.trim() + '%';
                return [
                    SELECT Id, FirstName, LastName, TINS_NUMBER__c
                    FROM   Account
                    WHERE  IsPersonAccount = true
                    AND    RecordType.DeveloperName = :PERSON_ACCOUNT_RT
                    AND    FirstName LIKE :key
                    ORDER BY LastName ASC
                    LIMIT  :SEARCH_LIMIT
                ];
            }
            return [
                SELECT Id, FirstName, LastName, TINS_NUMBER__c
                FROM   Account
                WHERE  IsPersonAccount = true
                AND    RecordType.DeveloperName = :PERSON_ACCOUNT_RT
                ORDER BY LastName ASC
                LIMIT  :SEARCH_LIMIT
            ];
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Failed to search employees: ' + ex.getMessage()
            );
        }
    }

    // -----------------------------------------------------------------------
    // Link selected Person Account employees to a Recruit Class
    // Creates AccountContactRelation (standard many-to-many)
    // @param recruitClassId  - Id of the Recruit Class (Business Account)
    // @param employeeIds     - List of Person Account Ids to link
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static void linkEmployeesToRecruitClass(Id recruitClassId, List<Id> employeeIds) {
        if (recruitClassId == null || employeeIds == null || employeeIds.isEmpty()) {
            throw new AuraHandledException('Recruit Class Id and at least one employee are required.');
        }
        try {
            List<Account> employees = [
                SELECT Id, PersonContactId, FirstName, LastName
                FROM   Account
                WHERE  Id IN :employeeIds
                AND    IsPersonAccount = true
            ];

            // Fetch existing ACR to avoid duplicate inserts
            Set<Id> existingContactIds = new Set<Id>();
            for (AccountContactRelation acr : [
                SELECT ContactId
                FROM   AccountContactRelation
                WHERE  AccountId = :recruitClassId
            ]) {
                existingContactIds.add(acr.ContactId);
            }

            List<AccountContactRelation> newRelations = new List<AccountContactRelation>();

            for (Account emp : employees) {
                if (emp.PersonContactId == null) continue;
                if (existingContactIds.contains(emp.PersonContactId)) continue;

                newRelations.add(new AccountContactRelation(
                    AccountId = recruitClassId,
                    ContactId = emp.PersonContactId,
                    IsActive  = true
                ));
            }

            if (!newRelations.isEmpty()) {
                insert newRelations;
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Failed to link employees: ' + ex.getMessage()
            );
        }
    }

    // -----------------------------------------------------------------------
    // Find Person Account employees by TINS numbers (CSV upload flow)
    // @param employeesData - List of maps containing 'tins' key from CSV rows
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static List<Account> findEmployeesByTins(List<Map<String, String>> employeesData) {
        if (employeesData == null || employeesData.isEmpty()) {
            throw new AuraHandledException('No employee data received.');
        }

        Set<String> tinsNumbers = new Set<String>();
        for (Map<String, String> row : employeesData) {
            String tins = row.get('tins');
            if (String.isNotBlank(tins)) {
                tinsNumbers.add(tins.trim());
            }
        }

        if (tinsNumbers.isEmpty()) {
            return new List<Account>();
        }

        return [
            SELECT Id, FirstName, LastName, TINS_NUMBER__c
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    TINS_NUMBER__c IN :tinsNumbers
            ORDER BY LastName ASC
        ];
    }

    // -----------------------------------------------------------------------
    // Get all Recruit Classes ordered by most recently created
    // -----------------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<Account> getRecruitClasses() {
        return [
            SELECT Id, Name, FAQP_Recruit_model__c
            FROM   Account
            WHERE  RecordType.DeveloperName = :FAQP_ACCOUNT_RT
            ORDER BY CreatedDate DESC
        ];
    }

    // -----------------------------------------------------------------------
    // Check if a Recruit Class name already exists (duplicate validation)
    // Returns true if a duplicate is found
    // @param recruitClassName - formatted name to check (e.g. A-2026)
    // -----------------------------------------------------------------------
    @AuraEnabled
    public static Boolean checkRecruitClassDuplicate(String recruitClassName) {
        if (String.isBlank(recruitClassName)) {
            return false;
        }
        try {
            List<Account> existing = [
                SELECT Id
                FROM   Account
                WHERE  Name = :recruitClassName
                AND    RecordType.DeveloperName = :FAQP_ACCOUNT_RT
                LIMIT  1
            ];
            return !existing.isEmpty();
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Duplicate check failed: ' + ex.getMessage()
            );
        }
    }
}