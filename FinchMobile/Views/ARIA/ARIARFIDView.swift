import SwiftUI

struct ARIARFIDView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tags = app.aria.session.rfid
        ScrollView {
            VStack(spacing: 12) {
                if tags.isEmpty {
                    // Idle/scanning state — never fabricate a tag client-side (§3.6).
                    VStack(spacing: 6) {
                        Image(systemName: "wave.3.right.circle").font(.largeTitle).foregroundStyle(FinchTheme.cyanDim)
                        Text(app.aria.connection.state.isConnected ? "SCANNING — no tag present" : "Not connected")
                            .font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                    }
                    .padding(.vertical, 40)
                }
                ForEach(tags) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.uid).font(FinchTheme.mono).foregroundStyle(FinchTheme.cyan).finchCopyable(t.uid)
                        if let ty = t.tagType { field("type", ty) }
                        if let a = t.atqa { field("ATQA", a) }
                        if let s = t.sak { field("SAK", s) }
                        if let rs = t.readStatus { field("read", rs) }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
                }
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle("RFID")
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary).finchCopyable(value)
        }
    }
}
