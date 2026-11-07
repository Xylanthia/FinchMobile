import Foundation

@main struct ActionTests {
    static func check(_ value: Bool) { precondition(value) }
    static func main() throws {
        let filter = ARIAAction(name: "Filter", command: "./aria ble filter \"%s\"")
        check(try filter.resolved(values: ["Desk speaker"]).command == "./aria ble filter \"Desk speaker\"")
        let upstream = ARIAAction(name: "Upstream", command: "./aria wifi mitm upstream \"%s\" \"%s\"")
        check(try upstream.resolved(values: ["My WiFi", "a&b%stuff"]).command == "./aria wifi mitm upstream \"My WiFi\" \"a&b%stuff\"")
        check(try upstream.resolved(values: ["Open WiFi", ""]).command == "./aria wifi mitm upstream \"Open WiFi\" \"\"")
        for values in [[], ["x\ny"], ["quote\"break"]] {
            do { _ = try filter.resolved(values: values); fatalError("Invalid input accepted") } catch {}
        }
        let groups = ARIAAction.forGroup(["id": "bluetooth", "actions": [["name": "Devices", "command": "ui.devices"]]])
        precondition(groups[0].nativeDestination == "ble")
        precondition(ARIAAction(name: "Devices", command: "ui.devices", group: "wifi").nativeDestination == "wifi")
        precondition(ARIAAction(name: "Replay", command: "ui.replay").nativeDestination == "subghz")
        precondition(ARIAAction(name: "Track", command: "ui.trackpick subghz").nativeDestination == "track:subghz")
        precondition(ARIAAction(name: "Arm", command: "ui.track arm").remoteTemplate == "./aria track arm")
        let block = ARIAAction(name: "Block", command: "ui.wifiblock")
        check(try block.resolved(values: ["AA:BB:CC:DD:EE:FF"]).command == "./aria wifi lab-disconnect prepare-block AA:BB:CC:DD:EE:FF")
        precondition(ARIAAction.confirmationCommand(from: "Confirm within 30 seconds: ./aria wifi lab-disconnect confirm 12AB34CD\nCancel") == "./aria wifi lab-disconnect confirm 12AB34CD")
        precondition(ARIAAction.confirmationCommand(from: "./aria wifi lab-disconnect confirm 123456789") == nil)
        precondition(ARIAAction.confirmationCommand(from: "ERROR") == nil)
        // Every current registry action must have either native navigation or a concrete command.
        let registry = try String(contentsOfFile: "/work/Tests/menu-fixture.h", encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\"(ui\.[^\"]+)\""#)
        for match in regex.matches(in: registry, range: NSRange(registry.startIndex..., in: registry)) {
            let command = String(registry[Range(match.range(at: 1), in: registry)!])
            let action = ARIAAction(name: command, command: command)
            precondition(action.nativeDestination != nil || !action.remoteTemplate.hasPrefix("ui."), command)
        }
        print("PASS: registry routing, parameters, quoting, legacy metadata, native navigation and confirmation tokens")
    }
}
