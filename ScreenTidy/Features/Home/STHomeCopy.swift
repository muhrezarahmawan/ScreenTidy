import Foundation

/// Approved Home greeting subtitle pool. Do not invent copy at runtime.
enum STHomeCopy {
    static let subtitles: [String] = [
        "Your screenshots, organized and easy to find",
        "Everything you screenshot, neatly organized",
        "Your screenshots, sorted into the right places",
        "Keeping your screenshots organized for you",
        "A cleaner way to keep your screenshots organized",
        "Your screenshots, organized by what they’re about",
        "Your screenshots, right where they belong",
        "Less clutter. More organized screenshots",
        "Keeping your screenshot library tidy",
        "Find what you screenshot, faster",
        "Your screenshots, neatly grouped and ready"
    ]

    private static let lastSubtitleKey = "screentidy.home.lastGreetingSubtitle"

    /// Picks a subtitle for a new Home visit, avoiding the previous one when possible.
    static func nextSubtitle() -> String {
        let previous = UserDefaults.standard.string(forKey: lastSubtitleKey)
        var pool = subtitles
        if let previous, pool.count > 1 {
            pool.removeAll { $0 == previous }
        }
        let chosen = pool.randomElement() ?? subtitles[0]
        UserDefaults.standard.set(chosen, forKey: lastSubtitleKey)
        return chosen
    }
}
