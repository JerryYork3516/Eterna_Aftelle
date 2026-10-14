public protocol PlaybackConfigurationObserving: AnyObject {
    func register() throws
    func check() throws
    func remove()
}

public enum PlaybackLifecycle {
    /// All closures run on the control path. Failed validation never reaches playback or scoring.
    public static func run(
        observer: (any PlaybackConfigurationObserving)? = nil,
        startAndValidate: () throws -> Void, play: () -> Void,
        score: () -> Void, stop: () -> Void
    ) throws {
        defer {
            observer?.remove()
            stop()
        }
        try observer?.register()
        try observer?.check()
        try startAndValidate()
        try observer?.check()
        play()
        score()
    }
}
