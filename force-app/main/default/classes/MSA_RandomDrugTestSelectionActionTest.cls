/**
 * MSA_RandomDrugTestSelectionActionTest
 * ---------------------------------------------------------------------------
 * Covers the invocable wrapper MSA_RandomDrugTestSelectionAction.generate,
 * confirming the service SelectionResult is mapped onto the flow Result.
 * ---------------------------------------------------------------------------
 */
@isTest
private class MSA_RandomDrugTestSelectionActionTest {

    @isTest
    static void testInvocableGenerate() {
        TestDataFactory.createPersonAccounts(2, false);

        MSA_RandomDrugTestSelectionAction.Request req =
            new MSA_RandomDrugTestSelectionAction.Request();
        req.numberOfEmployees = 1;
        req.selectionDate     = Date.today();

        Test.startTest();
        List<MSA_RandomDrugTestSelectionAction.Result> results =
            MSA_RandomDrugTestSelectionAction.generate(
                new List<MSA_RandomDrugTestSelectionAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        MSA_RandomDrugTestSelectionAction.Result out = results[0];
        System.assertNotEquals(null, out.success, 'Success flag should be populated');
        System.assertEquals(1, out.requestedCount, 'Requested count mapped through from the service');
        System.assert(String.isNotBlank(out.message), 'A message should always be returned');
    }

    @isTest
    static void testInvocableValidationFailure() {
        // Invalid count -> service returns a graceful failure, mapped to Result.
        MSA_RandomDrugTestSelectionAction.Request req =
            new MSA_RandomDrugTestSelectionAction.Request();
        req.numberOfEmployees = 0;
        req.selectionDate     = Date.today();

        Test.startTest();
        List<MSA_RandomDrugTestSelectionAction.Result> results =
            MSA_RandomDrugTestSelectionAction.generate(
                new List<MSA_RandomDrugTestSelectionAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        System.assertEquals(false, results[0].success, 'Zero requested should fail');
        System.assert(String.isNotBlank(results[0].message), 'Failure message should be returned');
    }
}