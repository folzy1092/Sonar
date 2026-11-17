import SwiftUI
import UIKit

/// Аккаунт → «Статистика» (TZ photo_7, 8 без друзей; как Windows `Stats.svelte`): по журналу
/// прослушиваний на телефоне (`PlayLog`) — время, прослушивания, треки, артисты, «к прошлому периоду»,
/// столбики по дням / месяцам, кольцо по часам суток, дни недели, серия дней, топ артистов и треков.
/// Периоды — неделя / месяц / год / всё время (`stats.period`). Тап по треку — играть топ с него,
/// по артисту — его страница.
struct StatsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var log = PlayLog.shared
    @State private var stats: ListeningStats?
    @State private var selectedBucket: Date?

    private var period: StatsPeriod {
        StatsPeriod(rawValue: settings.string("stats.period")) ?? .month
    }

    private var periodBinding: Binding<StatsPeriod> {
        Binding(get: { period }, set: { settings.set("stats.period", .string($0.rawValue)) })
    }

    var body: some View {
        SystemScreen(title: t("Статистика")) {
            SystemSegments(options: StatsPeriod.allCases.map { SystemSegments<StatsPeriod>.Option(id: $0, title: Self.title($0)) }, selection: periodBinding)
                .cascade(0)

            if let stats {
                if stats.isEmpty {
                    empty
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    content(stats)
                }
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.card)
                    .frame(height: 260)
                    .redacted(reason: .placeholder)
            }
        }
        .animation(Motion.spring, value: stats)
        .task(id: "\(period.rawValue)-\(log.revision)") {
            let rows = log.rows
            let tracks = log.tracks
            let chosen = period
            let next = await Task.detached(priority: .userInitiated) {
                StatsEngine.compute(rows: rows, tracks: tracks, period: chosen, now: Date())
            }.value
            selectedBucket = nil
            stats = next
        }
    }

    static func title(_ period: StatsPeriod) -> String {
        switch period {
        case .week: t("Неделя")
        case .month: t("Месяц")
        case .year: t("Год")
        case .all: t("Всё время")
        }
    }

    // MARK: - Пусто

    private var empty: some View {
        VStack(spacing: 14) {
            SystemBadgeIcon(icon: .headphone, size: 64)
            Text(t("Пока пусто"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(t("Слушай музыку — засчитывается трек, прослушанный хотя бы наполовину (или 30 секунд)."))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if period != .all, !log.rows.isEmpty {
                Button {
                    periodBinding.wrappedValue = .all
                } label: {
                    Text(t("Показать за всё время"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Данные

    @ViewBuilder
    private func content(_ s: ListeningStats) -> some View {
        hero(s)
            .cascade(1)
        chart(s)
            .cascade(2)
        HStack(alignment: .top, spacing: 12) {
            hoursRing(s)
            weekdays(s)
        }
        .cascade(3)
        minor(s)
            .cascade(4)
        if !s.artists.isEmpty {
            artists(s.artists)
                .cascade(5)
        }
        if !s.tracks.isEmpty {
            tracks(s.tracks)
                .cascade(6)
        }
    }

    /// Главные числа: время крупно, под ним прослушивания, треки, артисты, «к прошлому периоду».
    private func hero(_ s: ListeningStats) -> some View {
        let hours = s.totalHours >= 1
        let value = hours ? s.totalHours : s.totalMinutes
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CountUpText(value: value, size: 56, weight: .heavy)
                    .foregroundStyle(Theme.text)
                Text(hours ? tn(value, "час", "часа", "часов") : tn(value, "минута", "минуты", "минут"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if let delta = s.deltaPct {
                    deltaChip(delta)
                }
            }
            HStack(spacing: 0) {
                heroCell(s.plays, tn(s.plays, "Прослушивание", "Прослушивания", "Прослушиваний"))
                heroCell(s.trackCount, tn(s.trackCount, "Трек", "Трека", "Треков"))
                heroCell(s.artistCount, tn(s.artistCount, "Артист", "Артиста", "Артистов"))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
    }

    private func heroCell(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CountUpText(value: value, size: 22, weight: .bold)
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaChip(_ delta: Int) -> some View {
        let up = delta >= 0
        return HStack(spacing: 4) {
            SonarIcon(up ? .arrowUp : .arrowDown, size: 13)
            Text(verbatim: "\(abs(delta))%")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(delta)))
        }
        .foregroundStyle(up ? Theme.success : Theme.danger)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background((up ? Theme.success : Theme.danger).opacity(0.14), in: Capsule())
        .accessibilityLabel("\(delta > 0 ? "+" : "")\(delta)% \(t("к прошлому периоду"))")
    }

    /// Столбики по дням / месяцам. Тап — время этого дня.
    private func chart(_ s: ListeningStats) -> some View {
        let top = max(1, s.buckets.map(\.ms).max() ?? 1)
        let selected = s.buckets.first { $0.start == selectedBucket }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selected.map { bucketTitle($0) } ?? t("Время прослушивания"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Spacer()
                Text(durationText(selected?.ms ?? s.totalMs))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
            }
            HStack(alignment: .bottom, spacing: s.buckets.count > 14 ? 3 : 7) {
                ForEach(Array(s.buckets.enumerated()), id: \.element.id) { index, bucket in
                    Bar(fraction: Double(bucket.ms) / Double(top), index: index,
                        highlighted: selectedBucket == nil ? index == s.buckets.count - 1 : bucket.start == selectedBucket)
                        .onTapGesture {
                            withAnimation(Motion.spring) { selectedBucket = selectedBucket == bucket.start ? nil : bucket.start }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                }
            }
            .frame(height: 130)
            .id(s.period)
            HStack(spacing: 0) {
                ForEach(Array(s.buckets.enumerated()), id: \.element.id) { index, bucket in
                    Text(axisLabel(bucket, index: index, count: s.buckets.count))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Подпись под столбиком: неделя — день недели, месяц — число через 5, год — месяц.
    private func axisLabel(_ bucket: StatsBucket, index: Int, count: Int) -> String {
        switch bucket.unit {
        case .day where count <= 7:
            return t(Self.weekdayKeys[StatsEngine.mondayIndex(Calendar.current.component(.weekday, from: bucket.start))])
        case .day:
            return (count - 1 - index) % 5 == 0 ? String(Calendar.current.component(.day, from: bucket.start)) : ""
        case .month:
            let label = t(Self.monthKeys[Calendar.current.component(.month, from: bucket.start) - 1])
            return count > 12 && (count - 1 - index) % 3 != 0 ? "" : label
        }
    }

    private func bucketTitle(_ bucket: StatsBucket) -> String {
        let style: Date.FormatStyle = bucket.unit == .day
            ? .dateTime.day().month(.wide).locale(currentLang().locale)
            : .dateTime.month(.wide).year().locale(currentLang().locale)
        return bucket.start.formatted(style)
    }

    /// Кольцо часов суток: 24 лепестка, длина — сколько слушал в этот час; в центре — пик.
    private func hoursRing(_ s: ListeningStats) -> some View {
        VStack(spacing: 10) {
            HoursRing(hours: s.hours, peak: s.peakHour)
                .frame(width: 128, height: 128)
                .overlay {
                    VStack(spacing: 0) {
                        Text(verbatim: s.peakHour.map { String(format: "%02d:00", $0) } ?? "—")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                        Text(t("пик"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            Text(t("По часам"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Дни недели: семь столбиков, любимый — акцентом.
    private func weekdays(_ s: ListeningStats) -> some View {
        let top = max(1, s.weekdays.max() ?? 1)
        return VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0 ..< 7, id: \.self) { day in
                    VStack(spacing: 6) {
                        Bar(fraction: Double(s.weekdays[day]) / Double(top), index: day, highlighted: day == s.favWeekday)
                        Text(t(Self.weekdayKeys[day]))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(day == s.favWeekday ? Theme.text : Theme.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .frame(height: 128)
            Text(t("По дням недели"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Мелкие итоги: серия, треков в день, любимый день.
    private func minor(_ s: ListeningStats) -> some View {
        HStack(spacing: 10) {
            minorCell(icon: .fire, value: s.streakDays, label: tn(s.streakDays, "день подряд", "дня подряд", "дней подряд"),
                      tint: s.streakDays > 1 ? Color.orange : nil)
            minorCell(icon: .music, value: s.perDay, label: tn(s.perDay, "трек в день", "трека в день", "треков в день"))
            VStack(alignment: .leading, spacing: 6) {
                SonarIcon(.calendar, size: 20).foregroundStyle(Theme.textSecondary)
                Text(s.favWeekday.map { t(Self.weekdayKeys[$0]) } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(t("любимый день недели"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func minorCell(icon: IconName, value: Int, label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SonarIcon(icon, filled: tint != nil, size: 20).foregroundStyle(tint ?? Theme.textSecondary)
            CountUpText(value: value, size: 22, weight: .bold)
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func artists(_ list: [ArtistStat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Любимые артисты"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.text)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, artist in
                        Button {
                            if let ref = artist.ref { router.push(.artist(ref: ref, name: artist.name), on: .profile, chrome: chrome) }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    CoverImage(url: artist.avatarURL, cornerRadius: 50)
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                    if index < 3 {
                                        Text(verbatim: "\(index + 1)")
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(Theme.accentInk)
                                            .frame(width: 26, height: 26)
                                            .background(Theme.accent, in: Circle())
                                            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                                    }
                                }
                                Text(artist.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(durationText(artist.ms))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(verbatim: "\(artist.plays) \(tn(artist.plays, "раз", "раза", "раз"))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .frame(width: 104)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .disabled(artist.ref == nil)
                        .cascade(index)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.gutter)
        }
    }

    private func tracks(_ list: [TrackStat]) -> some View {
        let top = max(1, list.map(\.plays).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(t("Любимые треки"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.text)
            VStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    Button {
                        engine.play(list.map(\.track), at: index, context: "stats")
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: "\(index + 1)")
                                .font(.system(size: 14, weight: .bold).monospacedDigit())
                                .foregroundStyle(index < 3 ? Theme.accent : Theme.textTertiary)
                                .frame(width: 22)
                            CoverImage(url: item.track.coverURL, cornerRadius: 8)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.track.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(engine.current?.ref == item.track.ref ? Theme.accent : Theme.text)
                                    .lineLimit(1)
                                Text(item.track.artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.55))
                                        .frame(width: max(4, proxy.size.width * Double(item.plays) / Double(top)))
                                }
                                .frame(height: 3)
                            }
                            Spacer(minLength: 6)
                            Text(verbatim: "\(item.plays)")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .cascade(index)
                }
            }
        }
    }

    // MARK: - Текст

    private func durationText(_ ms: Int) -> String {
        let hours = ms / 3_600_000
        if hours > 0 { return "\(hours) \(tn(hours, "час", "часа", "часов"))" }
        let minutes = Int((Double(ms) / 60_000).rounded())
        return "\(minutes) \(tn(minutes, "минута", "минуты", "минут"))"
    }

    static let weekdayKeys = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    static let monthKeys = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
}

/// Столбик: растёт снизу при появлении (каскадом), выбранный — акцентом.
private struct Bar: View {
    let fraction: Double
    let index: Int
    var highlighted = false
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(highlighted ? Theme.accent : Theme.accent.opacity(fraction > 0 ? 0.38 : 0.12))
                    .frame(height: max(4, proxy.size.height * (grown || reduceMotion ? min(1, max(0, fraction)) : 0)))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(Motion.spring, value: fraction)
        .animation(Motion.spring, value: highlighted)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(min(index, 30)) * 0.018)) { grown = true }
        }
    }
}

/// Кольцо из 24 лепестков (час суток): длина — доля от пика, пик — акцентом. Вырастает при появлении.
private struct HoursRing: View {
    let hours: [Int]
    let peak: Int?
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let inner = radius * 0.62
            let top = Double(max(1, hours.max() ?? 1))
            ZStack {
                ForEach(0 ..< 24, id: \.self) { hour in
                    let value = Double(hours[hour]) / top
                    let length = (radius - inner) * (0.14 + 0.86 * (grown || reduceMotion ? value : 0))
                    Capsule()
                        .fill(hour == peak ? Theme.accent : Theme.accent.opacity(value > 0 ? 0.28 + 0.4 * value : 0.1))
                        .frame(width: 4.5, height: length)
                        .offset(y: -(inner + length / 2))
                        .rotationEffect(.degrees(Double(hour) / 24 * 360))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(hour) * 0.015), value: grown)
                        .animation(Motion.spring, value: value)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { grown = true }
        .accessibilityElement()
        .accessibilityLabel(peak.map { "\(t("пик прослушивания")) \($0):00" } ?? "")
    }
}
