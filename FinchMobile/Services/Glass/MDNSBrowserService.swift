import Foundation
import Network

final class MDNSBrowserService {
    static let serviceTypes = [
        "_http._tcp",
        "_hap._tcp",
        "_mqtt._tcp",
        "_rtsp._tcp",
        "_companion-link._tcp",
        "_printer._tcp",
        "_scanner._tcp",
        "_dacp._tcp",
        "_raop._tcp"
    ]

    private var browsers: [NWBrowser] = []
    private var results: [String: MDNSServiceRecord] = [:]
    private let lock = NSLock()
    var onUpdate: (([MDNSServiceRecord]) -> Void)?

    func start() {
        stop()
        for type in Self.serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: .tcp)
            browser.stateUpdateHandler = { _ in }
            browser.browseResultsChangedHandler = { [weak self] _, _ in
                self?.ingest(browser: browser, type: type)
            }
            browser.start(queue: .global(qos: .utility))
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }

    func snapshot() -> [MDNSServiceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(results.values)
    }

    private func ingest(browser: NWBrowser, type: String) {
        for result in browser.browseResults {
            switch result.endpoint {
            case .service(let name, let typeName, let domain, _):
                resolve(name: name, type: typeName.isEmpty ? type : typeName, domain: domain)
            default:
                break
            }
        }
    }

    private func resolve(name: String, type: String, domain: String) {
        let params = NWParameters.tcp
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain.isEmpty ? "local." : domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   let nwEndpoint = path.remoteEndpoint {
                    let record = self?.record(from: nwEndpoint, name: name, type: type)
                    if let record {
                        self?.lock.lock()
                        self?.results[record.id] = record
                        let all = Array(self?.results.values ?? [])
                        self?.lock.unlock()
                        self?.onUpdate?(all)
                    }
                }
                connection.cancel()
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            connection.cancel()
        }
    }

    private func record(from endpoint: NWEndpoint, name: String, type: String) -> MDNSServiceRecord? {
        switch endpoint {
        case .hostPort(let host, let port):
            let hostStr: String
            switch host {
            case .ipv4(let v4):
                hostStr = "\(v4)"
            case .ipv6(let v6):
                hostStr = "\(v6)"
            case .name(let n, _):
                hostStr = n
            @unknown default:
                hostStr = "\(host)"
            }
            return MDNSServiceRecord(
                name: name,
                type: type,
                host: hostStr,
                port: Int(port.rawValue),
                txt: [:]
            )
        default:
            return nil
        }
    }
}
