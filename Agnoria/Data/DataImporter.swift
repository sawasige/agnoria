import Foundation
import SwiftData

/// バンドル JSON を SwiftData へ upsert する。バックグラウンドで実行する
@ModelActor
actor DataImporter {
    struct Summary: Sendable, Equatable {
        var inserted = 0
        var updated = 0
        var archived = 0
    }

    /// `id` を主キーに upsert。JSON から消えた id は削除せず isArchived = true にする
    func importData(_ payload: BundleData.Payload) throws -> Summary {
        var summary = Summary()

        // --- Words
        let existingWords = try modelContext.fetch(FetchDescriptor<Word>())
        var wordByID = Dictionary(existingWords.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in payload.words {
            if let w = wordByID.removeValue(forKey: s.id) {
                w.apply(s)
                summary.updated += 1
            } else {
                modelContext.insert(Word(s))
                summary.inserted += 1
            }
        }
        for orphan in wordByID.values where !orphan.isArchived {
            orphan.isArchived = true
            summary.archived += 1
        }

        // --- Grammar
        let existingGrammar = try modelContext.fetch(FetchDescriptor<GrammarQuestion>())
        var grammarByID = Dictionary(existingGrammar.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in payload.grammar {
            if let g = grammarByID.removeValue(forKey: s.id) {
                g.apply(s)
                summary.updated += 1
            } else {
                modelContext.insert(GrammarQuestion(s))
                summary.inserted += 1
            }
        }
        for orphan in grammarByID.values where !orphan.isArchived {
            orphan.isArchived = true
            summary.archived += 1
        }

        try modelContext.save()
        return summary
    }
}
