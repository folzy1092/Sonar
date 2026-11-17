import SwiftUI
import UIKit

/// Лист «выйди на рабочий стол» (`HomeScreenHint`) — поверх всего (просьба владельца 2026-11-17): над
/// всплывашкой, мини-плеером, таб-баром, листами и полным плеером. Поэтому он живёт не в экране
/// «Обновление», а в своём прозрачном окне над окном приложения. Касания мимо листа проходят насквозь.
@MainActor
final class HomeHintWindow {
    static let shared = HomeHintWindow()

    private var window: PassthroughWindow?

    /// Вызывается при каждой смене стадии обновления: окно создаётся при первой подсказке и дальше
    /// просто показывает или прячет лист с анимацией.
    func update(for stage: SelfUpdateStage) {
        guard HomeScreenHint.text(for: stage) != nil || window != nil else { return }
        if window == nil { attach() }
    }

    private func attach() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let window = PassthroughWindow(windowScene: scene)
        // выше алертов приложения; системное окно «Установить?» всё равно рисует iOS поверх всех окон
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: HomeHintOverlay())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // не makeKeyAndVisible: ключевым остаётся окно приложения (от него показывается страница установки)
        window.isHidden = false
        self.window = window
    }
}

/// Окно, которое ловит касания только на своих видимых элементах.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === rootViewController?.view ? nil : view
    }
}

/// Содержимое окна: лист снизу, пока стадия обновления просит выйти на рабочий стол.
private struct HomeHintOverlay: View {
    private let updater = SelfUpdater.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let hint = HomeScreenHint.text(for: updater.stage) {
                HomeScreenHint(title: hint.title, text: hint.text)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(Motion.spring, value: updater.stage)
        .preferredColorScheme(ThemeStore.shared.colorScheme)
    }
}
