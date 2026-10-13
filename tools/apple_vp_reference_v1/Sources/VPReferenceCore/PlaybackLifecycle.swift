public enum PlaybackLifecycle {
    /// All closures run on the control path. Failed validation never reaches playback or scoring.
    public static func run(
        startAndValidate: () throws -> Void, play: () -> Void,
        score: () -> Void, stop: () -> Void
    ) throws {
        defer { stop() }
        try startAndValidate()
        play()
        score()
    }
}
