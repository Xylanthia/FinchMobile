import SwiftUI
import SwiftData
import UIKit

struct VaultView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var items: [VaultItem]
    @State private var unlocked = false
    @State private var decryptedJSON: String?
    @State private var selectedTitle: String = ""
    @State private var showDetail = false
    @State private var passphrase = ""

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                if unlocked {
                    list
                } else {
                    lockGate
                }
            }
            .navigationTitle("VAULT")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    ScrollView {
                        Text(decryptedJSON ?? "")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.textPrimary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(FinchTheme.background)
                    .navigationTitle(selectedTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showDetail = false }
                        }
                    }
                }
            }
        }
    }

    private var lockGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(FinchTheme.cyan)
            Text("AES-256-GCM · biometric gate")
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textSecondary)
            Button("Unlock with Face ID / Touch ID") {
                Task {
                    unlocked = await app.vaultManager.authenticateBiometric()
                }
            }
            .buttonStyle(FinchOutlineButtonStyle())

            if !app.vaultManager.hasPassphrase() {
                SecureField("Set vault passphrase", text: $passphrase)
                    .font(FinchTheme.mono)
                    .padding(12)
                    .glowBorder(active: true)
                    .padding(.horizontal)
                Button("Save Passphrase") {
                    app.vaultManager.setPassphrase(passphrase)
                    unlocked = true
                }
                .buttonStyle(FinchOutlineButtonStyle())
            }

            if let err = app.vaultManager.lastError {
                Text(err)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.danger)
            }
        }
    }

    private var list: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("No persisted reports")
                        .font(FinchTheme.mono)
                        .foregroundStyle(FinchTheme.textSecondary)
                    Text("Engage → Persist to encrypt a Glass / BLE snapshot.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            open(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(FinchTheme.mono)
                                    .foregroundStyle(FinchTheme.cyan)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.textSecondary)
                            }
                        }
                        .listRowBackground(FinchTheme.surface)
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func open(_ item: VaultItem) {
        do {
            if !app.vaultManager.isUnlocked {
                _ = app.vaultManager.unlockWithStoredPassphrase()
            }
            let data = try app.vaultManager.decrypt(item)
            decryptedJSON = String(data: data, encoding: .utf8) ?? ""
            selectedTitle = item.title
            showDetail = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            app.vaultManager.lastError = error.localizedDescription
            unlocked = false
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(items[i])
        }
        try? modelContext.save()
    }
}
