// Uygulama ile widget arasında paylaşılan veri, Siri/widget komutu ve canlı etkinlik tanımı.
import Foundation
import SwiftUI
import WidgetKit
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

struct BahceHabit: Codable, Hashable {
    var name: String
    var pct: Double
    var color: String
    var isWater: Bool = false

    enum CodingKeys: String, CodingKey { case name, pct, color, isWater }
    init(name: String, pct: Double, color: String, isWater: Bool = false) {
        self.name = name; self.pct = pct; self.color = color; self.isWater = isWater
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        pct = (try? c.decode(Double.self, forKey: .pct)) ?? 0
        color = (try? c.decode(String.self, forKey: .color)) ?? "#3F9A52"
        isWater = (try? c.decode(Bool.self, forKey: .isWater)) ?? false
    }
}

struct BahceSnapshot: Codable {
    var date: String
    var name: String
    var level: Int
    var title: String
    var xp: Int
    var xpFrom: Int
    var xpTo: Int
    var streak: Int
    var done: Int
    var total: Int
    var waterId: String?
    var water: Int
    var waterTarget: Int
    var habits: [BahceHabit]

    /// Kayıt eski bir güne aitse bugünün boş hâlini döndürür.
    func forToday() -> BahceSnapshot {
        let today = Bahce.todayKey()
        if date == today { return self }
        var s = self
        s.date = today
        s.water = 0
        s.done = 0
        s.habits = habits.map { BahceHabit(name: $0.name, pct: 0, color: $0.color, isWater: $0.isWater) }
        return s
    }

    var levelProgress: Double {
        let span = max(1, xpTo - xpFrom)
        return min(1, max(0, Double(xp - xpFrom) / Double(span)))
    }

    static let sample = BahceSnapshot(
        date: Bahce.todayKey(), name: "", level: 4, title: "Genç Ağaç", xp: 1450, xpFrom: 1200, xpTo: 2000,
        streak: 5, done: 2, total: 3, waterId: "water", water: 5, waterTarget: 8,
        habits: [BahceHabit(name: "Su", pct: 0.62, color: "#2F7FD8", isWater: true),
                 BahceHabit(name: "Kitap", pct: 1, color: "#E07B1F"),
                 BahceHabit(name: "Ders", pct: 1, color: "#1F9C63")])
}

enum Bahce {
    static let group = "group.com.serhattutak.gunlukduzen"
    static let snapKey = "snapshot"
    static let pendingKey = "pendingWater"

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func todayKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func loadSnapshot() -> BahceSnapshot? {
        guard let d = defaults.data(forKey: snapKey) else { return nil }
        return try? JSONDecoder().decode(BahceSnapshot.self, from: d)
    }

    static func saveSnapshot(_ s: BahceSnapshot) {
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: snapKey) }
    }

    static func pending() -> [String: Int] {
        (defaults.dictionary(forKey: pendingKey) as? [String: Int]) ?? [:]
    }

    static func clearPending() { defaults.removeObject(forKey: pendingKey) }

    /// Widget ya da Siri'den bir bardak su ekler. Uygulama açıldığında kayda işlenir.
    @discardableResult
    static func addWater() -> BahceSnapshot? {
        let day = todayKey()
        var p = pending()
        p[day, default: 0] += 1
        defaults.set(p, forKey: pendingKey)
        guard var s = loadSnapshot()?.forToday() else { return nil }
        if s.waterId != nil {
            let wasDone = s.waterTarget > 0 && s.water >= s.waterTarget
            s.water += 1
            if let idx = s.habits.firstIndex(where: { $0.isWater }), s.waterTarget > 0 {
                s.habits[idx].pct = min(1, Double(s.water) / Double(s.waterTarget))
            }
            if !wasDone && s.waterTarget > 0 && s.water >= s.waterTarget { s.done += 1 }
        }
        saveSnapshot(s)
        WidgetCenter.shared.reloadAllTimelines()
        return s
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Bir bardak su ekle"
    static var description = IntentDescription("Günlük Düzen'deki su hedefine bir bardak ekler.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let s = Bahce.addWater(), s.waterId != nil, s.waterTarget > 0 {
            return .result(dialog: "Bir bardak eklendi: \(s.water) / \(s.waterTarget)")
        }
        return .result(dialog: "Bir bardak su eklendi")
    }
}
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct FocusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
    }
    var name: String
    var color: String
    var targetMin: Int
    var level: Int
}
#endif
