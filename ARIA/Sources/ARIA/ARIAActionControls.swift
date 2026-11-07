import SwiftUI

struct ARIAActionDestination: View {
    @Environment(AppModel.self) private var app
    let action: ARIAAction

    @ViewBuilder var body: some View {
        if let destination = action.nativeDestination {
            switch destination {
            case "wifi": ARIAWiFiView()
            case "ble": ARIABLEView()
            case "uas": ARIAUASView()
            case "subghz": ARIASubGHzView()
            case "wifiLab":
                ARIAModeActionsView(mode: ARIAMode(name: "Wi-Fi client controls", actions: [
                    ARIAAction(name: "Connected clients", command: "./aria wifi lab-disconnect status"),
                    ARIAAction(name: "Disconnect client", command: "./aria wifi lab-disconnect prepare %s", input: 3),
                    ARIAAction(name: "Block client", command: "./aria wifi lab-disconnect prepare-block %s", input: 3),
                    ARIAAction(name: "Unblock client", command: "./aria wifi lab-disconnect unblock")
                ]))
            default:
                if destination.hasPrefix("track:") {
                    ARIATrackControls(band: String(destination.dropFirst(6)))
                } else if let mode = groupMode(destination) {
                    ARIAModeActionsView(mode: mode)
                } else {
                    Text("This control group has not been reported by ARIA.").padding()
                }
            }
        } else {
            ARIACommandForm(action: action)
        }
    }

    private func groupMode(_ destination: String) -> ARIAMode? {
        let keys = ["modes", "wifi", "bluetooth", "subghz", "lora", "dragon", "track", "captures", "long_range", "session", "device"]
        guard destination.hasPrefix("group:"), let index = Int(destination.dropFirst(6)), keys.indices.contains(index) else { return nil }
        return app.aria.modes.first { $0.command == keys[index] }
    }
}

struct ARIACommandForm: View {
    @Environment(AppModel.self) private var app
    let action: ARIAAction
    @State private var values: [String]
    @State private var output = ""
    @State private var running = false
    @State private var pending: ARIAAction?
    @State private var preparedCommand: String?
    @State private var preparedAt: Date?

    init(action: ARIAAction) {
        self.action = action
        _values = State(initialValue: (0..<action.parameterCount).map { _ in action.parameterChoices.first ?? "" })
    }

    var body: some View {
        Form {
            if let detail = action.description { Text(detail) }
            if action.command == "ui.calibrate" {
                Text("Start calibration over Wi-Fi, then touch the three targets on the ARIA display.")
            }
            ForEach(values.indices, id: \.self) { index in
                if !action.parameterChoices.isEmpty {
                    Picker(action.parameterLabel(index), selection: $values[index]) {
                        ForEach(action.parameterChoices, id: \.self) { Text($0).tag($0) }
                    }
                } else if action.remoteTemplate.contains("mitm upstream") && index == 1 {
                    SecureField(action.parameterLabel(index), text: $values[index])
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    TextField(action.parameterLabel(index), text: $values[index])
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Button(running ? "Running…" : "Run over Wi-Fi") {
                do {
                    let resolved = try action.resolved(values: values)
                    if action.requiresConfirmation == true { pending = resolved }
                    else { execute(resolved) }
                } catch { output = error.localizedDescription }
            }
            .disabled(running || !app.aria.connection.state.isConnected)
            if !app.aria.connection.state.isConnected { Text("Connect to ARIA Wi-Fi to run this control.") }
            if let command = preparedCommand {
                Button("Confirm prepared action", role: .destructive) {
                    guard let preparedAt, Date().timeIntervalSince(preparedAt) < 28 else {
                        output += "\nPreparation expired. Run again to prepare."; preparedCommand = nil; return
                    }
                    preparedCommand = nil
                    execute(ARIAAction(name: "Confirm", command: command))
                }.disabled(running || !app.aria.connection.state.isConnected)
                Button("Cancel preparation") {
                    preparedCommand = nil
                    let command = command.contains("lab-disconnect") ? "./aria wifi lab-disconnect cancel" : "./aria subghz tx cancel"
                    execute(ARIAAction(name: "Cancel", command: command))
                }.disabled(running)
            }
            if !output.isEmpty {
                Section("ESP32 response") {
                    Text(output).font(FinchTheme.monoSmall).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(action.displayLabel)
        .confirmationDialog("Run \(action.displayLabel)?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible) {
            Button("Run", role: .destructive) { if let command = pending { execute(command) }; pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func execute(_ resolved: ARIAAction) {
        running = true; preparedCommand = nil; preparedAt = nil
        Task { @MainActor in
            defer { running = false }
            do {
                let data = try await app.aria.client.fire(resolved)
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                output = object?["output"] as? String ?? String(decoding: data, as: UTF8.self)
                if let command = ARIAAction.confirmationCommand(from: output) {
                    preparedCommand = command; preparedAt = Date()
                }
                await app.aria.refresh()
            } catch let failure as ARIAClient.Failure where failure.statusCode == nil {
                output = "Outcome unknown: \(failure.message)"
            } catch { output = "Failed: \(error.localizedDescription)" }
        }
    }
}

struct ARIATrackControls: View {
    @Environment(AppModel.self) private var app
    let band: String
    @State private var devices: [Candidate] = []
    @State private var error = ""
    struct Candidate: Identifiable {
        let id: String
        let name: String
    }
    var body: some View {
        List {
            if !error.isEmpty { Text(error) }
            if devices.isEmpty && error.isEmpty { Text("No observed devices available to track.") }
            ForEach(devices) { device in
                NavigationLink(device.name) {
                    ARIACommandForm(action: ARIAAction(name: "Track \(device.name)",
                        command: "./aria track select \(band) \(device.id) %s", choices: "on|off"))
                }
            }
            NavigationLink("Scene status") {
                ARIACommandForm(action: ARIAAction(name: "Scene status", command: "./aria track status"))
            }
        }
        .navigationTitle("Track \(band)")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do {
            let data = try await app.aria.client.omni("./aria track devices \(band)")
            let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let output = reply?["output"] as? String ?? "{}"
            let root = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            devices = (root?["devices"] as? [[String: Any]] ?? []).compactMap {
                guard let address = $0["address"] as? String else { return nil }
                return Candidate(id: address, name: $0["name"] as? String ?? address)
            }
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}
