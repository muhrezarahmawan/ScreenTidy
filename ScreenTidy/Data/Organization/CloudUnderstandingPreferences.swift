import Foundation

enum CloudUnderstandingConsent: String, Sendable {
    case notDetermined
    case accepted
    case declined
}

enum CloudUnderstandingPreferences {
    private static let key = "screentidy.cloudUnderstanding.consent"

    static var consent: CloudUnderstandingConsent {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = CloudUnderstandingConsent(rawValue: raw)
            else { return .notDetermined }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static var hasDecided: Bool {
        consent != .notDetermined
    }
}
