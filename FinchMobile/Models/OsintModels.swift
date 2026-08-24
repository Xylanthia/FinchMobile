import Foundation

struct OsintFinding: Identifiable, Codable, Hashable {
    var id: UUID
    var source: String
    var kind: String
    var value: String
    var relevance: String
    var url: String?
    var note: String

    init(
        id: UUID = UUID(),
        source: String,
        kind: String,
        value: String,
        relevance: String = "static",
        url: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.value = value
        self.relevance = relevance
        self.url = url
        self.note = note
    }
}

struct OsintAction: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var seed: String
    var pipeline: PipelineKind

    init(id: UUID = UUID(), title: String, seed: String, pipeline: PipelineKind) {
        self.id = id
        self.title = title
        self.seed = seed
        self.pipeline = pipeline
    }
}

struct OsintReport: Codable, Hashable {
    var query: String
    var pipeline: PipelineKind
    var brief: [String]
    var findings: [OsintFinding]
    var actions: [OsintAction]
    var startedAt: Date
    var finishedAt: Date

    var signalCount: Int { findings.filter { $0.relevance == "signal" }.count }
    var staticCount: Int { findings.filter { $0.relevance != "signal" }.count }
}

struct CaseSeed: Identifiable, Hashable, Codable {
    var id: UUID
    var kind: PipelineKind
    var value: String

    init(id: UUID = UUID(), kind: PipelineKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}
