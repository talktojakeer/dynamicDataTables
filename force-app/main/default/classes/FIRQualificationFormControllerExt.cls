public class FIRQualificationFormControllerExt {

    private final ApexPages.StandardController stdCtrl;

    public FIRQualificationFormControllerExt(ApexPages.StandardController controller) {
        this.stdCtrl = controller;
    }

    // Current date/time in Central Time (America/Chicago)
    public String getCurrentCentralDateTime() {
        return DateTime.now().format('MMMM dd, yyyy hh:mm a', 'America/Chicago');
    }
}