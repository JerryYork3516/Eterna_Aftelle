enum ResidentVisualIntent: String, CaseIterable, Equatable, Identifiable {
    case idle
    case thinking
    case speaking
    case loading
    case error
    case exit

    var id: String {
        rawValue
    }

    var debugLocalizedKey: String {
        "particleDebug.transition.state.\(rawValue)"
    }
}
