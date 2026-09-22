    /**
 * Invocable entry point for the "Random Drug Test Selection" screen flow.
 * Thin wrapper - all logic lives in RandomDrugTestSelectionService.
 * Errors are returned in Result (not thrown) so the flow can show a friendly message.
 */
public with sharing class MSA_RandomDrugTestSelectionAction {

    public class Request {
        @InvocableVariable(label='Number of Employees to Select' required=true)
        public Integer numberOfEmployees;
        @InvocableVariable(label='Selection Date' required=true)
        public Date selectionDate;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Requested Count')
        public Integer requestedCount;
        @InvocableVariable(label='Eligible Count')
        public Integer eligibleCount;
        @InvocableVariable(label='Selected Count')
        public Integer selectedCount;
        @InvocableVariable(label='Created Case Ids')
        public List<String> caseIds;
    }

    @InvocableMethod(
        label='Generate Random Drug Test Selection'
        description='Randomly selects eligible employees and creates Random drug test Cases.'
        category='MSA Drug Test'
    )
    public static List<Result> generate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            RandomDrugTestSelectionService.SelectionResult s =
                RandomDrugTestSelectionService.generate(r.numberOfEmployees, r.selectionDate);
            Result out = new Result();
            out.success        = s.success;
            out.message        = s.message;
            out.requestedCount = s.requestedCount;
            out.eligibleCount  = s.eligibleCount;
            out.selectedCount  = s.selectedCount;
            out.caseIds        = s.caseIds;
            results.add(out);
        }
        return results;
    }
}