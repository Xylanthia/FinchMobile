import SwiftUI

struct ConsentView: View {
    @Environment(AppModel.self) private var app
    @State private var subject = "lab-owner"
    @State private var hours: Double = 8
    @State private var waiver = true
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kill switch") {
                    Toggle("Engage kill switch (block all Tx)", isOn: Binding(
                        get: { app.consent.killSwitchEngaged },
                        set: { on in
                            if on { app.consent.engageKillSwitch() }
                            else { app.consent.killSwitchEngaged = false }
                            app.forensic.record(category: "consent", summary: app.consent.statusSummary)
                        }
                    ))
                    .tint(.red)
                    Text(app.consent.auditLine)
                        .font(FinchTheme.monoSmall)
                }

                Section("Consent token") {
                    if let t = app.consent.token {
                        LabeledContent("Subject", value: t.subject)
                        LabeledContent("Issuer", value: t.issuer)
                        LabeledContent("Expires", value: t.expiresAt.formatted())
                        LabeledContent("Scope", value: t.scope.joined(separator: ", "))
                        LabeledContent("Valid sig", value: app.consent.hasValidToken ? "yes" : "no")
                        Button("Clear token", role: .destructive) { app.consent.clearToken() }
                    } else {
                        Text("No token loaded — passive only.")
                            .font(FinchTheme.monoSmall)
                    }
                }

                Section("Issue local lab token") {
                    TextField("Subject", text: $subject)
                        .font(FinchTheme.mono)
                    Stepper("Valid \(Int(hours))h", value: $hours, in: 1...72)
                    Toggle("Synthetic / research waiver", isOn: $waiver)
                    Button("Issue + load token (* scope)") {
                        _ = app.consent.issueLocalToken(
                            subject: subject,
                            scope: ["*"],
                            hoursValid: hours,
                            waiverSynthetic: waiver
                        )
                        app.forensic.record(category: "consent", summary: "Issued local token for \(subject)")
                        message = "Token issued"
                    }
                    Button("Arm system") {
                        message = app.consent.attemptArm() ? "ARMED" : (app.consent.lastDenial ?? "Arm failed")
                        app.forensic.record(category: "consent", summary: message)
                    }
                    .disabled(app.consent.killSwitchEngaged)
                }

                if let denial = app.consent.lastDenial {
                    Section("Last denial") {
                        Text(denial).font(FinchTheme.monoSmall).foregroundStyle(.orange)
                    }
                }
                if !message.isEmpty {
                    Section { Text(message).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("CONSENT · ARM")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
