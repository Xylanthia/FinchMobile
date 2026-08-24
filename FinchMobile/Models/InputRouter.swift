import Foundation

enum PipelineKind: String, CaseIterable, Identifiable, Codable {
    case auto
    case identity
    case property
    case plate
    case cyber
    case web3
    case glassFabric
    case ble

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "AUTO"
        case .identity: return "ID"
        case .property: return "ADDR"
        case .plate: return "PLATE"
        case .cyber: return "CYBER"
        case .web3: return "WEB3"
        case .glassFabric: return "GLASS"
        case .ble: return "BLE"
        }
    }

    var isOsint: Bool {
        switch self {
        case .identity, .property, .plate, .cyber, .web3: return true
        default: return false
        }
    }
}

enum InputRouter {
    static let streetSuffixes: [String] = [
        "st", "street", "ave", "avenue", "blvd", "boulevard", "rd", "road",
        "dr", "drive", "ln", "lane", "ct", "court", "way", "hwy", "highway",
        "pkwy", "pike", "trl", "trail", "cir", "circle", "pl", "place", "ter", "terrace"
    ]

    static let usStates: Set<String> = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY","DC"
    ]

    static func classify(_ raw: String) -> PipelineKind {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()

        if lower == "scan ble" || lower == "ble radar" || lower == "scanble" || lower == "nearby bluetooth" {
            return .ble
        }
        if isCIDR(q) || isPrivateIP(q) || lower == "scan my network" || lower == "scan network" || lower.hasPrefix("scan my") {
            return .glassFabric
        }
        if isETH(q) {
            return .web3
        }
        if isEmail(q) {
            return .identity
        }
        if isURL(q) || isDomain(q) || isPublicIPv4(q) {
            return .cyber
        }
        if isMAC(q) {
            return .identity
        }
        if isPhone(q) {
            return .identity
        }
        if isVIN(q) || isPlate(q) {
            return .plate
        }
        if looksLikeAddress(q) {
            return .property
        }
        if q.contains("/") && q.split(separator: "/").count == 2 {
            return .glassFabric
        }
        return .identity
    }

    static func resolve(query: String, override: PipelineKind) -> PipelineKind {
        override == .auto ? classify(query) : override
    }

    static func isCIDR(_ s: String) -> Bool {
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32 else { return false }
        return isIPv4(String(parts[0]))
    }

    static func isPrivateIP(_ s: String) -> Bool {
        guard isIPv4(s) else { return false }
        let octets = s.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 127 { return true }
        return false
    }

    static func isIPv4(_ s: String) -> Bool {
        let octets = s.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { part in
            guard let n = Int(part), (0...255).contains(n) else { return false }
            return true
        }
    }

    static func isPublicIPv4(_ s: String) -> Bool {
        isIPv4(s) && !isPrivateIP(s)
    }

    static func isEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@")
        guard parts.count == 2 else { return false }
        return parts[0].count >= 1 && isDomain(String(parts[1]))
    }

    static func isDomain(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard t.contains("."), !t.contains(" "), !t.contains("/") else { return false }
        let labels = t.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2 else { return false }
        return t.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    static func isURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
    }

    static func isETH(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 42, t.lowercased().hasPrefix("0x") else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    static func isMAC(_ s: String) -> Bool {
        let hex = s.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return false }
        let compact = s.replacingOccurrences(of: "-", with: ":")
        return compact.contains(":") || compact.contains(".") || hex.count == 12 && s.filter({ $0.isLetter || $0.isNumber }).count == 12
    }

    static func isPhone(_ s: String) -> Bool {
        let d = digitsOnly(s)
        if d.count == 10 || (d.count == 11 && d.hasPrefix("1")) { return true }
        if s.contains("+") && (10...15).contains(d.count) { return true }
        return false
    }

    static func isVIN(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "").uppercased()
        guard t.count == 17 else { return false }
        return t.allSatisfy { ch in
            let u = String(ch)
            return (ch.isLetter || ch.isNumber) && u != "I" && u != "O" && u != "Q"
        }
    }

    static func isPlate(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard (2...8).contains(t.count) else { return false }
        guard t.contains(where: { $0.isNumber }) else { return false }
        guard t.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        if looksLikeAddress(s) { return false }
        if isVIN(s) { return false }
        return true
    }

    static func isUsername(_ s: String) -> Bool {
        if s.hasPrefix("@") { return true }
        if s.contains(" ") || s.contains("@") || s.contains(".") { return false }
        return (3...32).contains(s.count) && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    static func looksLikeAddress(_ s: String) -> Bool {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return false }
        let first = String(parts[0]).filter { $0.isNumber }
        guard !first.isEmpty else { return false }
        let lower = s.lowercased()
        if streetSuffixes.contains(where: { lower.contains(" \($0)") || lower.contains(" \($0).") || lower.hasSuffix(" \($0)") }) {
            return true
        }
        if s.contains(",") {
            let tail = s.split(separator: ",").last.map { String($0).trimmingCharacters(in: .whitespaces).uppercased() } ?? ""
            let st = tail.split(separator: " ").first.map(String.init) ?? tail
            if usStates.contains(st) { return true }
        }
        return false
    }

    static func digitsOnly(_ s: String) -> String {
        s.filter { $0.isNumber }
    }

    static func formatNANP(_ digits: String) -> String {
        var d = digits
        if d.count == 11 && d.hasPrefix("1") { d = String(d.dropFirst()) }
        guard d.count == 10 else { return digits }
        let a = d.prefix(3)
        let b = d.dropFirst(3).prefix(3)
        let c = d.suffix(4)
        return "+1 (\(a)) \(b)-\(c)"
    }
}
