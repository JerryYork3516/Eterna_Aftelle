public enum DiagnosticLifecycle {
    public static func finishWindow(
        durationSeconds: Double, elapsedSeconds: () -> Double,
        observe: () throws -> Void, onFailure: (Error) -> Void, wait: (Double) -> Void
    ) {
        do {
            try observe()
        } catch {
            onFailure(error)
        }
        wait(max(0, durationSeconds - elapsedSeconds()))
    }
}
