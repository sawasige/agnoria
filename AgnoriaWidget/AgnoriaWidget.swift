import WidgetKit
import SwiftUI

/// ホーム画面のウィジェット（§4.6 [v1.6]）。small: 今日の状態と連続日数、medium: それに加えてスコア帯の進み。
/// 読むのはアプリが App Group に書いた WidgetSnapshot だけ。タップでアプリが開く
struct AgnoriaWidget: Widget {
    static let kind = "AgnoriaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            AgnoriaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("学習の状況")
        .description("今日の学習と連続日数、スコア帯の進みを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    /// 今と、日付が変わる 0 時の 2 エントリ。0 時を過ぎると「今日はまだ」に戻る。アプリ側の更新は reloadAllTimelines で来る
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let entries = [Entry(date: now, snapshot: snapshot), Entry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct AgnoriaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: MediumView(snapshot: snapshot, now: entry.date)
            default: SmallView(snapshot: snapshot, now: entry.date)
            }
        } else {
            EmptyStateView()
        }
    }
}

/// 連続日数と今日の状態
private struct StreakBlock: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let done = snapshot.isDoneToday(now: now)
        let days = snapshot.displayStreak(now: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(done ? Color.orange : Color.secondary)
                    .widgetAccentable()
                Text("\(days)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    .widgetAccentable()
                Text("日連続")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(done ? "今日も学習済み" : "今日はまだ")
                .font(.subheadline)
                .fontWeight(done ? .regular : .semibold)
                .foregroundStyle(done ? Color.secondary : Color.orange)
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agnoria")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            StreakBlock(snapshot: snapshot, now: now)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agnoria")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                StreakBlock(snapshot: snapshot, now: now)
            }
            Divider()
            StageBlock(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 今の帯の習得率と、4 帯の並び（ホームの StageChips と同じ記号）
private struct StageBlock: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let current = snapshot.current
        let ratio = current?.masteredRatio ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("\(snapshot.currentLevel) 点帯")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((ratio * 100).rounded()))")
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                    .widgetAccentable()
                Text("% 習得")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: ratio)
                .tint(.accentColor)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(snapshot.levels, id: \.level) { level in
                    VStack(spacing: 2) {
                        Image(systemName: symbol(level))
                            .font(.caption2)
                            .foregroundStyle(color(level))
                        Text("\(level.level)")
                            .font(.caption2.monospacedDigit())
                            .fontWeight(level.level == snapshot.currentLevel ? .bold : .regular)
                            .foregroundStyle(level.level == snapshot.currentLevel ? Color.primary : Color.secondary)
                    }
                }
            }
            .accessibilityLabel(snapshot.levels.map { "\($0.level) 点帯 \(label($0))" }.joined(separator: "、"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func state(_ l: WidgetSnapshot.LevelProgress) -> String {
        if l.level > snapshot.unlockedLevel { return "locked" }
        if l.cleared { return "cleared" }
        return l.level == snapshot.currentLevel ? "current" : "open"
    }

    private func symbol(_ l: WidgetSnapshot.LevelProgress) -> String {
        switch state(l) {
        case "locked": "lock.fill"
        case "cleared": "checkmark.circle.fill"
        case "current": "record.circle"
        default: "circle"
        }
    }

    private func color(_ l: WidgetSnapshot.LevelProgress) -> Color {
        switch state(l) {
        case "locked": Color.secondary.opacity(0.5)
        case "cleared": .green
        default: .accentColor
        }
    }

    private func label(_ l: WidgetSnapshot.LevelProgress) -> String {
        switch state(l) {
        case "locked": "未到達"
        case "cleared": "クリア"
        case "current": "今ここ"
        default: "学習中"
        }
    }
}

/// まだ一度も起動していない（写しが無い）とき
private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agnoria")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "flame")
                .foregroundStyle(.secondary)
            Text("アプリを開いて、今日の 10 問から")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension WidgetSnapshot {
    /// プレースホルダとウィジェットギャラリー用
    static let sample = WidgetSnapshot(
        lastStudyDay: Calendar.current.startOfDay(for: .now), streakDays: 12, unlockedLevel: 500, currentLevel: 500,
        levels: [
            .init(level: 450, masteredRatio: 0.85, cleared: true),
            .init(level: 500, masteredRatio: 0.42, cleared: false),
            .init(level: 550, masteredRatio: 0, cleared: false),
            .init(level: 600, masteredRatio: 0, cleared: false),
        ],
        updatedAt: .now)
}

#Preview("small", as: .systemSmall) {
    AgnoriaWidget()
} timeline: {
    Entry(date: .now, snapshot: .sample)
    Entry(date: .now, snapshot: nil)
}

#Preview("medium", as: .systemMedium) {
    AgnoriaWidget()
} timeline: {
    Entry(date: .now, snapshot: .sample)
}
