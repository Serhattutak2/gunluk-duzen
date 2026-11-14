// Ana ekran / kilit ekranı widget'ları ve odak sayacı için canlı etkinlik (Live Activity).
import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

// MARK: - Veri

struct BahceEntry: TimelineEntry {
    let date: Date
    let s: BahceSnapshot
    let empty: Bool
}

struct BahceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BahceEntry {
        BahceEntry(date: Date(), s: .sample, empty: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BahceEntry) -> Void) {
        if let s = Bahce.loadSnapshot() {
            completion(BahceEntry(date: Date(), s: s.forToday(), empty: false))
        } else {
            completion(BahceEntry(date: Date(), s: .sample, empty: !context.isPreview))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BahceEntry>) -> Void) {
        let now = Date()
        let snap = Bahce.loadSnapshot()
        let entry = BahceEntry(date: now, s: snap?.forToday() ?? .sample, empty: snap == nil)
        // Gece yarısı yeni güne geçsin.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let next = BahceEntry(date: midnight, s: snap?.forToday() ?? .sample, empty: snap == nil)
        completion(Timeline(entries: [entry, next], policy: .after(midnight.addingTimeInterval(60))))
    }
}

// MARK: - Ortak parçalar

let skyTop = Color(hex: "#4FB2EC")
let skyBottom = Color(hex: "#CBEEFC")
let leafGreen = Color(hex: "#2F7D3C")
let night = Color(hex: "#0F2419")
let gold = Color(hex: "#F2B21B")

struct SkyBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color(hex: "#93D18E")).frame(height: 70).offset(y: 40).scaleEffect(x: 1.6)
            Ellipse().fill(Color(hex: "#52A257")).frame(height: 50).offset(y: 34).scaleEffect(x: 1.8)
        }
    }
}

struct TreeImage: View {
    let level: Int
    var body: some View {
        Image("tree\(min(max(level, 1), 10))")
            .resizable()
            .scaledToFit()
    }
}

struct WaterButton: View {
    let s: BahceSnapshot
    var compact = false
    var body: some View {
        Button(intent: AddWaterIntent()) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                Text(compact ? "+1" : "\(s.water)/\(s.waterTarget)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if !compact { Image(systemName: "plus").font(.system(size: 11, weight: .heavy)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(hex: "#2F7FD8")))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bahçe widget'ı

struct BahceWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BahceEntry

    var s: BahceSnapshot { entry.s }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    var small: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                TreeImage(level: s.level).frame(maxHeight: 92)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sv \(s.level)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.75)))
                    .foregroundStyle(night)
                Text(entry.empty ? "Başla" : "\(s.done)/\(s.total)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(night)
                    .monospacedDigit()
                Text(entry.empty ? "Uygulamayı aç" : "hedef tamam")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(night.opacity(0.7))
            }
            if s.waterId != nil && !entry.empty {
                VStack { Spacer(); HStack { Spacer(); WaterButton(s: s, compact: true) } }
            }
        }
        .containerBackground(for: .widget) { SkyBackground() }
    }

    var medium: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                TreeImage(level: s.level).frame(maxHeight: 96)
                Text(s.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(night)
                    .lineLimit(1)
                ProgressView(value: s.levelProgress).tint(gold).frame(width: 80)
            }
            .frame(width: 104)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.empty ? "Uygulamayı aç" : "\(s.done)/\(s.total) hedef")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    if s.streak > 0 {
                        Label("\(s.streak)", systemImage: "flame.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#E07B1F"))
                    }
                }
                .foregroundStyle(night)
                ForEach(Array(s.habits.prefix(3).enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(h.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer()
                            if h.pct >= 1 { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color(hex: h.color)) }
                        }
                        .foregroundStyle(night)
                        ProgressView(value: h.pct).tint(Color(hex: h.color))
                    }
                }
                if s.waterId != nil && !entry.empty {
                    HStack { Spacer(); WaterButton(s: s) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.82)))
        }
        .containerBackground(for: .widget) { SkyBackground() }
    }

    var circular: some View {
        Gauge(value: Double(s.done), in: 0...Double(max(s.total, 1))) {
            Image(systemName: "leaf.fill")
        } currentValueLabel: {
            Text("\(s.done)/\(s.total)").font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }

    var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(s.title) · Sv \(s.level)", systemImage: "leaf.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("\(s.done)/\(s.total) hedef tamam" + (s.streak > 0 ? " · \(s.streak) gün" : ""))
                .font(.system(size: 12))
            ProgressView(value: Double(s.done), total: Double(max(s.total, 1)))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    var inline: some View {
        Label("\(s.done)/\(s.total) hedef · Sv \(s.level)", systemImage: "leaf.fill")
            .containerBackground(for: .widget) { Color.clear }
    }
}

struct BahceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BahceWidget", provider: BahceProvider()) { entry in
            BahceWidgetView(entry: entry)
        }
        .configurationDisplayName("Ağacın")
        .description("Ağacını, bugünkü hedeflerini gör ve tek dokunuşla su ekle.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Odak sayacı (kilit ekranı ve Dynamic Island)

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { ctx in
            let c = Color(hex: ctx.attributes.color)
            HStack(spacing: 12) {
                TreeImage(level: ctx.attributes.level).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Odak · \(ctx.attributes.name)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    ProgressView(timerInterval: ctx.state.start...ctx.state.end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(c)
                }
                Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
            }
            .foregroundStyle(.white)
            .padding(16)
            .activityBackgroundTint(night)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let c = Color(hex: ctx.attributes.color)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.attributes.name, systemImage: "leaf.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(c)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 76)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: ctx.state.start...ctx.state.end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(c)
                }
            } compactLeading: {
                Image(systemName: "leaf.fill").foregroundStyle(c)
            } compactTrailing: {
                Text(timerInterval: ctx.state.start...ctx.state.end, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 46)
            } minimal: {
                Image(systemName: "leaf.fill").foregroundStyle(c)
            }
        }
    }
}

@main
struct GunlukWidgets: WidgetBundle {
    var body: some Widget {
        BahceWidget()
        FocusLiveActivity()
    }
}
