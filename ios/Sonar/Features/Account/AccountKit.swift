import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// Общие куски экранов аккаунта: поле ввода, строка ошибки, QR, значок платформы, «сколько осталось».

/// Поле формы входа: подпись сверху, стеклянная капсула, без автозамены.
struct AccountField: View {
    let title: String
    @Binding var text: String
    var secure = false
    var contentType: UITextContentType?
    var problem: String?
    var submit: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { submit?() }
            .font(.system(size: 16))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(problem == nil ? Theme.line : Theme.danger.opacity(0.7)))
            .accessibilityLabel(title)
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: problem)
    }
}

/// Ошибка под формой — со значком, без обвинений.
struct AccountError: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SonarIcon(.info, size: 16)
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}

/// QR-код ссылки (быстрый вход с другого устройства).
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(t("QR-код ссылки"))
        }
    }

    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension DevicePlatform {
    var icon: IconName {
        switch self {
        case .ios: .cellphone
        case .windows: .computer
        case .android: .android
        case .other: .server
        }
    }
}

enum AccountFormat {
    /// «4:12» до момента `until` (мс).
    static func remaining(until: Int64, now: Date) -> String {
        let left = max(0, Int((Double(until) / 1000 - now.timeIntervalSince1970).rounded(.up)))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    /// «5 минут назад» на языке интерфейса.
    @MainActor
    static func ago(_ ms: Int64, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        if now.timeIntervalSince(date) < 60 { return t("только что") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = currentLang().locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// «13:15».
    @MainActor
    static func clock(_ ms: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = currentLang().locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
