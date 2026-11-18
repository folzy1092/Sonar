import Foundation
import Network

/// Ищет Sonar на ПК в локальной сети: Bonjour `_sonar._tcp` (ПК объявляет себя, когда включён
/// «Система → Пульт»). Первый поиск iOS сопровождает вопросом «Разрешить доступ к локальной сети»
/// (`NSLocalNetworkUsageDescription` в project.yml). Колбэки — на главной очереди.
@MainActor
final class RemoteBrowser {
    private var browser: NWBrowser?
    private let onChange: @MainActor ([RemotePC]) -> Void
    private let onFail: @MainActor (String) -> Void

    init(onChange: @escaping @MainActor ([RemotePC]) -> Void, onFail: @escaping @MainActor (String) -> Void) {
        self.onChange = onChange
        self.onFail = onFail
    }

    var isRunning: Bool { browser != nil }

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: RemoteProtocol.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let pcs = Self.pcs(from: results)
            MainActor.assumeIsolated { self?.onChange(pcs) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let failure: String? = switch state {
            // нет разрешения на локальную сеть — NWError.dns(kDNSServiceErr_PolicyDenied)
            case let .failed(error), let .waiting(error): "\(error)"
            default: nil
            }
            guard let failure else { return }
            MainActor.assumeIsolated { self?.onFail(failure) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Результаты → ПК (без повторов по id: один ПК может прийти по Wi-Fi и по кабелю).
    nonisolated private static func pcs(from results: Set<NWBrowser.Result>) -> [RemotePC] {
        var seen = Set<String>()
        return results.compactMap { result -> RemotePC? in
            guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
            var txt: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                for (key, entry) in record {
                    if case let .string(value) = entry { txt[key] = value }
                }
            }
            return RemotePC.fromService(name: name, type: type, domain: domain, txt: txt)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .filter { seen.insert($0.id).inserted }
    }
}
