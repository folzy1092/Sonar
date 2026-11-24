import SwiftUI
import UIKit

/// Обложки и аватары итогов, загруженные заранее (ссылка → картинка): `ImageRenderer` не ждёт `AsyncImage`.
typealias RecapImages = [String: UIImage]

/// Одна карточка итогов — и на экране (`RecapView`), и на картинке (`RecapShare`). На экране числа
/// бегут (`CountUpText`) и строки появляются каскадом («Меньше движения» — только прозрачность); на
/// картинке всё сразу. Цвета — из обложки первого трека топа (`RecapColors`).
struct RecapCardView: View {
    let card: RecapCard
    let ref: RecapRef
    let colors: RecapColors
    let images: RecapImages
    /// false — для картинки: без анимаций.
    var live = true

    private static let hourChartHeight: CGFloat = 84

    private var ink: Color { Color(colors.ink) }
    private var accent: Color { Color(colors.accent) }

    var body: some View {
        let text = RecapText.card(card, ref: ref)
        VStack(alignment: .leading, spacing: 0) {
            visual
                .appear(0, live: live)
            Text(text.eyebrow)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 18)
                .appear(1, live: live)
            if !text.title.isEmpty {
                Text(text.title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)
                    .appear(2, live: live)
            }
            if let value = text.value {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    number(value)
                        .foregroundStyle(ink)
                    Text(text.unit)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 4)
                .appear(3, live: live)
            }
            ForEach(Array(text.lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ink.opacity(0.74))
                    .lineLimit(2)
                    .padding(.top, 6)
                    .appear(4 + index, live: live)
            }
            detail
                .padding(.top, 18)
                .appear(6, live: live)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(ink.opacity(0.12)))
    }

    // MARK: - Верх карточки

    @ViewBuilder
    private var visual: some View {
        switch card {
        case .intro: badge(.chart)
        case .minutes: badge(.headphone)
        case .tracks: badge(.music)
        case .artists: badge(.trophy)
        case let .newArtist(artist, _): art(artist.avatarURL, size: 112, circle: true)
        case .hour: badge(.clock)
        case .day: badge(.calendar)
        case let .onRepeat(item, _, _): art(item.track.coverURL, size: 132, circle: false)
        case .services: badge(.pie)
        }
    }

    private func badge(_ icon: IconName) -> some View {
        SonarIcon(icon, filled: true, size: 28)
            .foregroundStyle(Color(colors.accentInk))
            .frame(width: 60, height: 60)
            .background(accent, in: Circle())
    }

    // MARK: - Списки и столбики

    @ViewBuilder
    private var detail: some View {
        switch card {
        case let .tracks(list):
            VStack(spacing: 10) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    row(rank: index + 1, url: item.track.coverURL, circle: false, title: item.track.title,
                        subtitle: item.track.artist, trailing: RecapText.number(item.plays))
                }
            }
        case let .artists(list):
            VStack(spacing: 10) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, artist in
                    row(rank: index + 1, url: artist.avatarURL, circle: true, title: artist.name,
                        subtitle: RecapText.duration(artist.ms), trailing: nil)
                }
            }
        case let .hour(peak, hours):
            hourChart(peak: peak, hours: hours)
        case let .services(list):
            services(list)
        default:
            EmptyView()
        }
    }

    private func row(rank: Int, url: String?, circle: Bool, title: String, subtitle: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(rank)")
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank == 1 ? accent : ink.opacity(0.55))
                .frame(width: 18)
            art(url, size: 44, circle: circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(verbatim: trailing)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.62))
            }
        }
    }

    private func hourChart(peak: Int, hours: [Int]) -> some View {
        let top = Double(max(1, hours.max() ?? 1))
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0 ..< min(24, hours.count), id: \.self) { hour in
                    Capsule()
                        .fill(hour == peak ? accent : ink.opacity(hours[hour] > 0 ? 0.3 : 0.1))
                        .frame(height: max(4, Self.hourChartHeight * Double(hours[hour]) / top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.hourChartHeight, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(verbatim: String(format: "%02d", hour))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(ink.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func services(_ list: [RecapServiceShare]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(list, id: \.service) { share in
                        Capsule()
                            .fill(serviceColor(share.service))
                            .frame(width: max(6, (proxy.size.width - 3 * Double(list.count - 1)) * Double(share.pct) / 100))
                    }
                }
            }
            .frame(height: 12)
            ForEach(list, id: \.service) { share in
                HStack(spacing: 10) {
                    Circle().fill(serviceColor(share.service)).frame(width: 10, height: 10)
                    Text(RecapText.serviceTitle(share.service))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                    Spacer(minLength: 6)
                    Text(verbatim: "\(share.pct)%")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ink.opacity(0.7))
                }
            }
        }
    }

    private func serviceColor(_ id: ServiceID) -> Color {
        Color(RGB(hex: ServiceRegistry.info(id).color) ?? colors.accent)
    }

    // MARK: - Мелочи

    @ViewBuilder
    private func number(_ value: Int) -> some View {
        if live {
            CountUpText(value: value, size: 64, weight: .heavy)
        } else {
            Text(verbatim: RecapText.number(value))
                .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
        }
    }

    /// Обложка или аватар из заранее загруженных; нет картинки — нота.
    private func art(_ url: String?, size: CGFloat, circle: Bool) -> some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        return ZStack {
            ink.opacity(0.1)
            if let url, let image = images[url] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                SonarIcon(.music, size: size * 0.4).foregroundStyle(ink.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

private extension View {
    /// На экране — каскад (`Motion.swift`), на картинке — как есть.
    @ViewBuilder
    func appear(_ index: Int, live: Bool) -> some View {
        if live { cascade(index) } else { self }
    }
}
