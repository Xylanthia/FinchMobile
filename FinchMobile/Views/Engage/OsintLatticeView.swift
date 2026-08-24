import SwiftUI

struct OsintLatticeView: View {
    var report: OsintReport
    var onAction: (OsintAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(report.pipeline.label)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                    Spacer()
                    Text("\(report.signalCount) signal · \(report.staticCount) static")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
                Text(report.query)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                    .finchCopyable(report.query)

                if !report.brief.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BRIEF")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                        ForEach(Array(report.brief.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textPrimary)
                                .finchCopyable(line)
                        }
                    }
                    .padding(12)
                    .background(FinchCardBackground())
                }

                if !report.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEXT SEEDS")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                        ForEach(report.actions) { action in
                            Button {
                                onAction(action)
                            } label: {
                                HStack {
                                    Text(action.title)
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.textPrimary)
                                    Spacer()
                                    Text(action.pipeline.label)
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.cyan)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(FinchCardBackground())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("FINDINGS")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                    ForEach(report.findings) { hit in
                        OsintFindingRow(hit: hit)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}

struct OsintFindingRow: View {
    var hit: OsintFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hit.source.uppercased())
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan)
                Text(hit.kind)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                Spacer()
                Circle()
                    .fill(hit.relevance == "signal" ? FinchTheme.cyan : FinchTheme.textSecondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
            Text(hit.value)
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textPrimary)
                .finchCopyable(hit.value)
            if !hit.note.isEmpty {
                Text(hit.note)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .finchCopyable(hit.note)
            }
            if let url = hit.url, let link = URL(string: url) {
                Link(destination: link) {
                    Text(url)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(FinchCardBackground())
        .contextMenu {
            Button("Copy finding") {
                FinchCopy.set([hit.source, hit.kind, hit.value, hit.note, hit.url ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
        }
    }
}
