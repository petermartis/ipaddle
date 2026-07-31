import Foundation

enum HighScoreStore {
    private static let key = "ipaddle.highScore"

    static var highScore: Int {
        UserDefaults.standard.integer(forKey: key)
    }

    /// Records the score if it beats the stored high score. Returns true for a new record.
    @discardableResult
    static func submit(_ score: Int) -> Bool {
        guard score > highScore else { return false }
        UserDefaults.standard.set(score, forKey: key)
        return true
    }
}
