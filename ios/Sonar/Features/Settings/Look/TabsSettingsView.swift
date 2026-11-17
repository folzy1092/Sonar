import SwiftUI
import UIKit

/// Профиль → Интерфейс → Вкладки (ПК `pages/settings/TabsView.svelte`, скрин владельца «Стиль вкладок»):
/// стиль нижней панели — плитки Стандартный / Закруглённый / Плавающий / Компактный (`appearance.tab_style`,
/// применяется к `BottomChrome` сразу), подстройка цвета панели под тему (`tabs.adapt`) и сворачивание
/// панели с мини-плеером при прокрутке (`tabs.collapse`, только iPhone). Позиции вкладок на телефоне нет —
/// панель всегда снизу.
struct TabsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private var style: TabBarStyle { TabBarStyle(rawValue: settings.string(LookKey.tabStyle)) ?? .floating }

    var body: some View {
        LookScreen(title: "Вкладки") {
            LookCaption(text: "Стиль вкладок").cascade(0)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TabBarStyle.allCases) { item in
                    LookTile(icon: icon(item), title: item.title, subtitle: item.subtitle, selected: style == item) {
                        settings.set(LookKey.tabStyle, .string(item.rawValue))
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }
            .cascade(1)

            TabBarPreview(style: style)
                .cascade(2)

            LookCard {
                LookToggle(title: "Подстраивать вкладки",
                           value: settings.bool(LookKey.tabsAdapt) ? "Панель в цвет темы" : "Панель цвета поверхности",
                           isOn: binding(LookKey.tabsAdapt))
                LookToggle(title: "Сворачивать при прокрутке",
                           value: settings.bool(LookKey.tabsCollapse) ? "Вкладки и мини-плеер — в одну строку" : "Панель всегда развёрнута",
                           isOn: binding(LookKey.tabsCollapse))
            }
            .cascade(3)
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { settings.bool(key) }, set: { settings.set(key, $0) })
    }

    private func icon(_ style: TabBarStyle) -> IconName {
        switch style {
        case .standard: .tabStandard
        case .rounded: .tabRounded
        case .floating: .capsule
        case .compact: .dash
        }
    }
}

/// Маленькая схема экрана с панелью выбранного стиля — перетекает при смене.
private struct TabBarPreview: View {
    let style: TabBarStyle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let k: CGFloat = 0.5
            let barH = CGFloat(style.barHeight) * k
            // та же раскладка, что у настоящей панели, в половинном масштабе
            let barW = CGFloat(style.barWidth(screen: Double(w / k), gutter: Double(Theme.gutter), tabs: Tab.allCases.count)) * k
            let corners = style.radii(height: Double(barH))
            let bottomGap: CGFloat = style.fullWidth ? 0 : 8
            let shape = UnevenRoundedRectangle(topLeadingRadius: CGFloat(corners.top), bottomLeadingRadius: CGFloat(corners.bottom),
                                               bottomTrailingRadius: CGFloat(corners.bottom), topTrailingRadius: CGFloat(corners.top),
                                               style: .continuous)
            ZStack {
                // строки «контента»
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0 ..< 4, id: \.self) { i in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raisedHigh).frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Capsule().fill(Theme.text.opacity(0.22)).frame(width: CGFloat(110 - i * 14), height: 7)
                                Capsule().fill(Theme.text.opacity(0.12)).frame(width: CGFloat(70 + i * 9), height: 6)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 0) {
                    ForEach(Tab.allCases) { tab in
                        VStack(spacing: 2) {
                            SonarIcon(tab.icon, filled: tab == .home, size: 14)
                            if style.showsTitles {
                                Capsule().frame(width: 18, height: 3).opacity(0.6)
                            }
                        }
                        .foregroundStyle(tab == .home ? Theme.text : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: barW, height: barH)
                .background(GlassFill(shape: shape))
                .overlay(shape.stroke(Theme.line, lineWidth: 1))
                .position(x: w / 2, y: h - bottomGap - barH / 2)
            }
        }
        .frame(height: 190)
        .background(Theme.surface0, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.line))
        .animation(Motion.spring, value: style)
        .accessibilityHidden(true)
    }
}
