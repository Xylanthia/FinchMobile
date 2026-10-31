import SwiftUI

struct ARIAUASView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Only VALIDATED RID records render here. GENERIC_RF != UAS, enforced client-side (§3.5).
        let records = app.aria.history.uas
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    ARIAHistoryBanner()
                    ARIASourceCounts(source: .uas)
                }
                .padding().background(FinchCardBackground())
                if records.isEmpty {
                    // "NO VALID UAS DETECTED" is a normal, successful state — not empty/error.
                    VStack(spacing: 6) {
                        Image(systemName: "airplane.circle").font(.largeTitle).foregroundStyle(FinchTheme.cyanDim)
                        Text("NO VALID UAS DETECTED")
                            .font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                        Text("No validated Remote ID broadcasts in range.")
                            .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                    }
                    .padding(.vertical, 40)
                }
                ForEach(records) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.uasID).font(FinchTheme.mono).foregroundStyle(FinchTheme.cyan)
                            ARIARangeTag(source: .uas, id: r.uasID)
                            Spacer()
                            if let t = r.uaType { Text(t).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        if let it = r.idType { field("ID type", it) }
                        if let lat = r.latitude, let lon = r.longitude {
                            field("position", String(format: "%.5f, %.5f", lat, lon))
                        }
                        if let alt = r.altitude { field("altitude", String(format: "%.1f m", alt)) }
                        if let spd = r.speed { field("speed", String(format: "%.1f m/s", spd)) }
                        if let op = r.operatorID { field("operator", op) }
                        if let olat = r.operatorLatitude, let olon = r.operatorLongitude {
                            field("operator pos", String(format: "%.5f, %.5f", olat, olon))
                        }
                        if let prov = r.decoderProvenance { field("decoder", prov) }
                        DisclosureGroup("All handheld fields") {
                            ARIAStoredRecordSection(source: .uas, key: r.uasID)
                        }
                        .font(.caption).tint(FinchTheme.cyan)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
                }
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle("UAS / Remote ID")
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary).finchCopyable(value)
        }
    }
}
