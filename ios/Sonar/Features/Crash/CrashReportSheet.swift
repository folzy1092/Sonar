import SwiftUI
import UIKit

// Окно после сбоя (решение владельца 2026-11-17, как плашка ПК `windows/src/app/CrashNotice.svelte`):
// «Sonar закрылся с ошибкой», причина человеческим языком, «Отправить лог» (белая, главная) и
// «Закрыть» (серая). Отправка — ботом отчётов (`ReportBot`); бота нет в сборке — системное
// «Поделиться» с файлом. Закрывается только кнопкой, не смахиванием.

extension View {
    /// Подключить окно отчёта о сбое (один раз, к корню интерфейса).
    func crashReportSheet() -> some View {
        modifier(CrashReportPresenter())
    }
}

private struct CrashReportPresenter: ViewModifier {
    @State private var center = CrashReportCenter.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { center.report }, set: { if $0 == nil { center.close() } })) { _ in
                CrashReportSheet(center: center)
            }
            .task {
                // чуть позже первого кадра — окно не должно прыгать на загрузке
                try? await Task.sleep(for: .milliseconds(900))
                center.observe()
            }
    }
}

struct CrashReportSheet: View {
    @Bindable var center: CrashReportCenter
    @State private var showsDetails = false

    private var done: Bool { center.phase == .sent }
    private var sending: Bool { center.phase == .sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let report = center.report, !done {
                details(report)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .animation(Motion.spring, value: center.phase)
        .presentationDetents([.height(failed ? 430 : 370)])
        .presentationCornerRadius(30)
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled()
        .sheet(isPresented: Binding(get: { center.shareFile != nil }, set: { if !$0, center.shareFile != nil { center.shareFinished(completed: false) } })) {
            if let file = center.shareFile {
                ActivitySheet(items: [file]) { completed in center.shareFinished(completed: completed) }
                    .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: center.phase) { _, phase in
            guard phase == .sent else { return }
            Haptics.tap()
            Task {
                try? await Task.sleep(for: .milliseconds(2200))
                if center.phase == .sent { center.close() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                SonarIcon(done ? .check : .bolt, size: 22)
                    .foregroundStyle(done ? Color.black : Theme.text)
                    .id(done)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .frame(width: 44, height: 44)
            .background(done ? Color.white : Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(done ? t("Отправлено, спасибо") : t("Sonar закрылся с ошибкой"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(failed ? Theme.danger : Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
    }

    private var failed: Bool {
        if case .failed = center.phase { true } else { false }
    }

    private var subtitle: String {
        switch center.phase {
        case .sent: return t("Разберёмся и починим")
        case let .failed(message): return t("Не вышло отправить: {reason}", ["reason": t(message)])
        case .idle, .sending: return t("Отправь лог — так быстрее найдём причину")
        }
    }

    /// Причина: человеческая строка и мелко — техническая (выделяется и копируется).
    private func details(_ report: CrashReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t(report.summary))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.cause.technical)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    @ViewBuilder
    private var buttons: some View {
        if !done {
            VStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    Task { await center.send() }
                } label: {
                    HStack(spacing: 8) {
                        if sending {
                            ProgressView().tint(.black)
                        }
                        Text(primaryTitle)
                            .contentTransition(.opacity)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(sending)

                if failed {
                    Button {
                        center.share()
                    } label: {
                        HStack(spacing: 8) {
                            SonarIcon(.share, size: 18)
                            Text(t("Поделиться"))
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.raised, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Button {
                    center.close()
                } label: {
                    Text(t("Закрыть"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(sending)
            }
            .transition(.opacity)
        }
    }

    private var primaryTitle: String {
        switch center.phase {
        case .sending: t("Отправляю…")
        case .failed: t("Ещё раз")
        default: t("Отправить лог")
        }
    }
}

/// Системное «Поделиться»; `completed` — пользователь куда-то отправил файл.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let finished: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in finished(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
