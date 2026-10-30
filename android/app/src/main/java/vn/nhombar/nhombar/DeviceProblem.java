package vn.nhombar.nhombar;

public class DeviceProblem extends RuntimeException {
    public final boolean sessionExpired;

    public DeviceProblem(String message) {
        this(message, false);
    }

    public DeviceProblem(String message, boolean sessionExpired) {
        super(message);
        this.sessionExpired = sessionExpired;
    }
}
