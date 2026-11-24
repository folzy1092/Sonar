import UIKit
import XCTest
@testable import Sonar

/// Значки приложения («Значок приложения» в настройках): список, имена наборов, переводы и то, что сборка
/// правда положила их в Info.plist и каталог. Те же id и порядок — на ПК (`windows/src/lib/app-icons.ts`).
final class AppIconTests: XCTestCase {
    func testSameIconsAsWindowsInTheSameOrder() {
        XCTAssertEqual(AppIcon.allCases.map(\.rawValue),
                       ["glass", "flat", "bevel", "puff", "block", "echo", "well", "chrome", "carved", "light", "black", "white"])
    }

    func testPrimaryIsTheOnlyOneWithoutAlternateName() {
        XCTAssertEqual(AppIcon.primary, .glass)
        XCTAssertEqual(AppIcon.allCases.first, .glass)
        XCTAssertNil(AppIcon.primary.alternateName)
        XCTAssertEqual(AppIcon.allCases.filter { $0.alternateName == nil }, [.glass])
    }

    func testSetNamesFollowTheCatalogNaming() {
        XCTAssertEqual(AppIcon.glass.setName, "AppIcon")
        XCTAssertEqual(AppIcon.flat.setName, "AppIcon-Flat")
        XCTAssertEqual(AppIcon.carved.alternateName, "AppIcon-Carved")
        XCTAssertEqual(Set(AppIcon.allCases.map(\.setName)).count, AppIcon.allCases.count)
    }

    func testCurrentIconFromTheSystemName() {
        XCTAssertEqual(AppIcon.current(alternateName: nil), .glass)
        XCTAssertEqual(AppIcon.current(alternateName: "AppIcon-Echo"), .echo)
        for icon in AppIcon.allCases {
            XCTAssertEqual(AppIcon.current(alternateName: icon.alternateName), icon)
        }
        // значок из другой сборки — основной, а не сбой
        XCTAssertEqual(AppIcon.current(alternateName: "AppIcon-Нет-такого"), .glass)
    }

    func testTitlesAreTranslatedEverywhere() {
        for lang in [Lang.en, .uk, .es, .de, .pl] {
            let dict = I18n.dictionaries[lang] ?? [:]
            for icon in AppIcon.allCases {
                XCTAssertNotNil(dict[icon.title], "\(lang): \(icon.title)")
            }
            XCTAssertNotNil(dict["Значок приложения"], "\(lang): заголовок")
        }
    }

    func testEveryPreviewIsInTheBundle() {
        for icon in AppIcon.allCases {
            XCTAssertNotNil(UIImage(named: icon.preview), icon.preview)
        }
    }

    /// Тесты идут внутри приложения: `Bundle.main` — собранный Sonar.app. Без CFBundleAlternateIcons
    /// `setAlternateIconName` ничего не делает, и пользователь просто не увидит смены.
    func testInfoPlistListsEveryAlternateIcon() {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        XCTAssertEqual(Set(alternates?.keys.map { String($0) } ?? []), Set(AppIcon.allCases.compactMap(\.alternateName)),
                       "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES в project.yml и список AppIcon разошлись")
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(primary?["CFBundleIconName"] as? String, "AppIcon")
    }
}
