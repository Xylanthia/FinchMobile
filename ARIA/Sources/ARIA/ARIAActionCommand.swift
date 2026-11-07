import Foundation

/// Phone-side routing for the existing registry, including firmware predating input metadata.
extension ARIAAction {
    var nativeDestination: String? {
        let c = command ?? name
        if c.hasPrefix("ui.group ") { return "group:" + c.dropFirst(9) }
        if c == "ui.devices" { return ["bluetooth", "dragon"].contains(group ?? "") ? "ble" : "wifi" }
        switch c {
        case "ui.uas": return "uas"
        case "ui.replay", "ui.wave", "ui.subghzintel": return "subghz"
        case "ui.wifideauth": return "wifiLab"
        case "ui.trackpick wifi", "ui.trackpick ble", "ui.trackpick subghz", "ui.trackpick lora":
            return "track:" + c.dropFirst(13)
        default: return nil
        }
    }

    var remoteTemplate: String {
        switch command ?? name {
        case "ui.wifitarget %s", "ui.wifidisconnect": return "./aria wifi lab-disconnect prepare %s"
        case "ui.wifiblock": return "./aria wifi lab-disconnect prepare-block %s"
        case "ui.raw": return "./aria subghz raw last"
        case "ui.blecapture": return "./aria dragon sniff status"
        case "ui.blelab": return "./aria dragon mitm %s"
        case "ui.track asset": return "./aria track status"
        case "ui.track arm": return "./aria track arm"
        case "ui.track disarm": return "./aria track disarm"
        case "ui.theme": return "./aria display theme %s"
        case "ui.calibrate": return "./aria display calibrate"
        default: return command ?? name
        }
    }

    var parameterCount: Int { remoteTemplate.components(separatedBy: "%s").count - 1 }
    var parameterChoices: [String] {
        if let choices { return choices.components(separatedBy: "|") }
        if command == "ui.theme" { return ["cyan", "violet", "amber"] }
        if remoteTemplate == "./aria wifi channel %s" { return (1...11).map(String.init) }
        return []
    }
    func parameterLabel(_ index: Int) -> String {
        if remoteTemplate.contains("mitm upstream") { return index == 0 ? "Network name (SSID)" : "Password" }
        if remoteTemplate.contains("lab-disconnect prepare") || command == "ui.blelab" || input == 3 { return "Target MAC address" }
        return parameterCount == 1 ? displayLabel : "Value \(index + 1)"
    }

    func resolved(values: [String]) throws -> ARIAAction {
        guard nativeDestination == nil, !remoteTemplate.hasPrefix("ui.") else {
            throw CommandError("Open this control in the app.")
        }
        let pieces = remoteTemplate.components(separatedBy: "%s")
        guard values.count == pieces.count - 1 else { throw CommandError("Enter every command value.") }
        var result = pieces[0]
        for i in values.indices {
            let value = values[i]
            let emptyPassword = remoteTemplate.contains("mitm upstream") && i == 1
            guard (emptyPassword || !value.trimmingCharacters(in: .whitespaces).isEmpty),
                  !value.contains(where: { $0.isNewline || $0 == "\0" }) else {
                throw CommandError("Enter a single-line value.")
            }
            // The firmware tokenizer has no quote escaping. Preserve spaces inside its quotes.
            if pieces[i].hasSuffix("\"") && value.contains("\"") {
                throw CommandError("This firmware does not support quotation marks inside this value.")
            }
            result += value + pieces[i + 1]
        }
        var action = self
        action.command = result
        return action
    }

    struct CommandError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Preserve the firmware's prepare/confirm protocol; never auto-confirm a prepared action.
    static func confirmationCommand(from output: String) -> String? {
        for prefix in ["./aria wifi lab-disconnect confirm ", "./aria subghz tx confirm "] {
            guard let range = output.range(of: prefix) else { continue }
            let token = String(output[range.upperBound...].prefix(while: { $0.isHexDigit }))
            if token.count == 8 { return prefix + token }
        }
        return nil
    }
}
