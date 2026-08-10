import Foundation
import Network

actor TCPProbe {
    static func isOpen(host: String, port: UInt16, timeout: TimeInterval = 1.0) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let lock = NSLock()
            final class FlagBox: @unchecked Sendable { var resumed = false }
            let flag = FlagBox()
            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !flag.resumed else { return }
                flag.resumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }

    static func connectAndIO(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        send: Data?,
        readLimit: Int = 4096
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let lock = NSLock()
            final class BufferBox: @unchecked Sendable {
                var data = Data()
                var resumed = false
            }
            let buffer = BufferBox()

            @Sendable func finish(_ value: Data?) {
                lock.lock()
                defer { lock.unlock() }
                guard !buffer.resumed else { return }
                buffer.resumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            func startRead() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: readLimit) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        buffer.data.append(data)
                        if buffer.data.count >= readLimit {
                            finish(buffer.data)
                            return
                        }
                    }
                    if isComplete || error != nil {
                        finish(buffer.data.isEmpty ? nil : buffer.data)
                        return
                    }
                    if buffer.data.isEmpty {
                        startRead()
                    } else {
                        // brief grace for multi-packet banners
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                            finish(buffer.data)
                        }
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let send {
                        connection.send(content: send, completion: .contentProcessed { _ in
                            startRead()
                        })
                    } else {
                        startRead()
                    }
                case .failed, .cancelled:
                    finish(buffer.data.isEmpty ? nil : buffer.data)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(buffer.data.isEmpty ? nil : buffer.data)
            }
        }
    }
}

final class SubnetSweepService {
    var onHostFound: ((IoTHost) -> Void)?
    var onProgress: ((String) -> Void)?

    func sweep(cidr: String, ports: [Int] = IoTPorts.probeQuick, maxConcurrent: Int = 50) async -> (hosts: [IoTHost], warnings: [String], effectiveCIDR: String) {
        let (ips, warnings, effective) = NetworkInterfaceHelper.hosts(inCIDR: cidr)
        var live: [String: IoTHost] = [:]
        let total = ips.count
        var completed = 0

        await withTaskGroup(of: IoTHost?.self) { group in
            var inFlight = 0
            var index = 0

            func enqueueMore() {
                while inFlight < maxConcurrent && index < ips.count {
                    let ip = ips[index]
                    index += 1
                    inFlight += 1
                    group.addTask {
                        var open: [Int] = []
                        for p in ports {
                            if await TCPProbe.isOpen(host: ip, port: UInt16(p), timeout: 1.0) {
                                open.append(p)
                            }
                        }
                        guard !open.isEmpty else { return nil }
                        let mac = NetworkInterfaceHelper.macAddress(forIP: ip)
                        let vendor = mac.flatMap { OUIDatabase.shared.vendor(forMAC: $0) }
                        let hostname = await ReverseDNS.lookup(ip: ip)
                        return IoTHost(
                            ip: ip,
                            mac: mac,
                            vendor: vendor,
                            hostname: hostname,
                            openProbePorts: open,
                            openPorts: open
                        )
                    }
                }
            }

            enqueueMore()
            for await host in group {
                inFlight -= 1
                completed += 1
                if completed % 16 == 0 || completed == total {
                    onProgress?("Subnet sweep \(completed)/\(total)")
                }
                if let host {
                    live[host.ip] = host
                    onHostFound?(host)
                }
                enqueueMore()
            }
        }

        return (Array(live.values).sorted { $0.ip < $1.ip }, warnings, effective)
    }
}

enum ReverseDNS {
    static func lookup(ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(
                    ai_flags: AI_NUMERICHOST,
                    ai_family: AF_INET,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: 0,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(ip, nil, &hints, &res) == 0, let res else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(res) }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let r = getnameinfo(
                    res.pointee.ai_addr,
                    res.pointee.ai_addrlen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
                if r == 0 {
                    let name = String(cString: host)
                    continuation.resume(returning: name == ip ? nil : name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
