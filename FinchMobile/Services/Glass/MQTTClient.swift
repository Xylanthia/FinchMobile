import Foundation
import Network

/// Minimal MQTT 3.1.1 client — CONNECT + SUBSCRIBE only (no publish).
final class MQTTClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aetherverse.finch.mqtt")
    private var onMessage: ((MQTTMessage) -> Void)?
    private var buffer = Data()
    private var finished = false

    func listen(
        host: String,
        port: UInt16 = 1883,
        topic: String = "#",
        username: String? = nil,
        password: String? = nil,
        durationSeconds: TimeInterval,
        onMessage: @escaping (MQTTMessage) -> Void
    ) async -> [MQTTMessage] {
        self.onMessage = onMessage
        finished = false
        buffer = Data()
        var collected: [MQTTMessage] = []
        let lock = NSLock()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            self.connection = conn

            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let connect = MQTTPacket.connect(
                        clientID: "finch-\(UUID().uuidString.prefix(8))",
                        cleanSession: true,
                        username: username,
                        password: password
                    )
                    conn.send(content: connect, completion: .contentProcessed { _ in
                        self.receiveLoop(onMessage: { msg in
                            lock.lock()
                            collected.append(msg)
                            lock.unlock()
                            onMessage(msg)
                        })
                    })
                case .failed, .cancelled:
                    if !self.finished {
                        self.finished = true
                        continuation.resume()
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)

            queue.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
                self?.connection?.cancel()
                if let self, !self.finished {
                    self.finished = true
                    continuation.resume()
                }
            }
        }

        connection?.cancel()
        connection = nil
        return collected
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    private func receiveLoop(onMessage: @escaping (MQTTMessage) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain(onMessage: onMessage)
            }
            if isComplete || error != nil {
                return
            }
            self.receiveLoop(onMessage: onMessage)
        }
    }

    private func drain(onMessage: @escaping (MQTTMessage) -> Void) {
        while buffer.count >= 2 {
            let packetType = buffer[0] >> 4
            guard let (remaining, headerLen) = MQTTPacket.decodeRemainingLength(buffer.dropFirst()) else { return }
            let total = 1 + headerLen + remaining
            guard buffer.count >= total else { return }
            let packet = Data(buffer.prefix(total))
            buffer.removeFirst(total)

            if packetType == 2 {
                // CONNACK — subscribe
                let sub = MQTTPacket.subscribe(topicFilter: "#", packetID: 1)
                connection?.send(content: sub, completion: .contentProcessed { _ in })
            } else if packetType == 3 {
                if let msg = MQTTPacket.parsePublish(packet) {
                    onMessage(msg)
                }
            }
        }
    }
}

enum MQTTPacket {
    static func connect(
        clientID: String,
        cleanSession: Bool,
        username: String? = nil,
        password: String? = nil
    ) -> Data {
        var variable = Data()
        variable.append(mqttString("MQTT"))
        variable.append(0x04) // protocol level 3.1.1
        var flags: UInt8 = cleanSession ? 0x02 : 0x00
        if username != nil { flags |= 0x80 }
        if password != nil { flags |= 0x40 }
        variable.append(flags)
        variable.append(contentsOf: [0x00, 0x3C]) // keepalive 60
        variable.append(mqttString(clientID))
        if let username { variable.append(mqttString(username)) }
        if let password { variable.append(mqttString(password)) }

        return fixedHeader(type: 1, flags: 0, payload: variable)
    }

    static func subscribe(topicFilter: String, packetID: UInt16) -> Data {
        var variable = Data()
        variable.append(UInt8(packetID >> 8))
        variable.append(UInt8(packetID & 0xFF))
        variable.append(mqttString(topicFilter))
        variable.append(0x00) // QoS 0
        return fixedHeader(type: 8, flags: 0x02, payload: variable)
    }

    static func parsePublish(_ packet: Data) -> MQTTMessage? {
        guard packet.count >= 4 else { return nil }
        let flags = packet[0] & 0x0F
        let qos = (flags >> 1) & 0x03
        guard let (remaining, headerLen) = decodeRemainingLength(packet.dropFirst()) else { return nil }
        var offset = 1 + headerLen
        guard offset + 2 <= packet.count else { return nil }
        let topicLen = Int(packet[offset]) << 8 | Int(packet[offset + 1])
        offset += 2
        guard offset + topicLen <= packet.count else { return nil }
        let topicData = packet.subdata(in: offset..<(offset + topicLen))
        let topic = String(data: topicData, encoding: .utf8) ?? ""
        offset += topicLen
        if qos > 0 {
            offset += 2 // packet id
        }
        let end = 1 + headerLen + remaining
        guard offset <= end, end <= packet.count else { return nil }
        let payload = packet.subdata(in: offset..<end)
        return MQTTMessage(topic: topic, payload: payload)
    }

    static func decodeRemainingLength(_ bytes: Data) -> (Int, Int)? {
        var multiplier = 1
        var value = 0
        var index = 0
        while index < bytes.count {
            let encoded = Int(bytes[index])
            index += 1
            value += (encoded & 127) * multiplier
            multiplier *= 128
            if multiplier > 128 * 128 * 128 { return nil }
            if encoded & 128 == 0 {
                return (value, index)
            }
        }
        return nil
    }

    private static func fixedHeader(type: UInt8, flags: UInt8, payload: Data) -> Data {
        var packet = Data()
        packet.append((type << 4) | flags)
        packet.append(contentsOf: encodeRemainingLength(payload.count))
        packet.append(payload)
        return packet
    }

    private static func encodeRemainingLength(_ length: Int) -> [UInt8] {
        var x = length
        var bytes: [UInt8] = []
        repeat {
            var encoded = UInt8(x % 128)
            x /= 128
            if x > 0 { encoded |= 128 }
            bytes.append(encoded)
        } while x > 0
        return bytes
    }

    private static func mqttString(_ s: String) -> Data {
        let utf = Array(s.utf8)
        var data = Data([UInt8(utf.count >> 8), UInt8(utf.count & 0xFF)])
        data.append(contentsOf: utf)
        return data
    }
}
