import Foundation
import SwiftData

struct PersistenceBootstrap {
    let container: ModelContainer
    let storageError: String?
    let isUsingFallback: Bool
}

enum PersistenceContainer {
    static func make() -> PersistenceBootstrap? {
        let schema = FlipabularySchema.schema

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestInMemory") {
            return makeInMemory(schema: schema)
        }
        #endif

        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return PersistenceBootstrap(container: container, storageError: nil, isUsingFallback: false)
        } catch {
            // Do not delete or recreate the store. Fall back to memory and show a recoverable message.
            guard let fallback = makeInMemory(schema: schema) else { return nil }
            return PersistenceBootstrap(
                container: fallback.container,
                storageError: "Your library could not be opened. Changes are temporary until the storage problem is fixed. \(error.localizedDescription)",
                isUsingFallback: true
            )
        }
    }

    private static func makeInMemory(schema: Schema) -> PersistenceBootstrap? {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return PersistenceBootstrap(container: container, storageError: nil, isUsingFallback: false)
        } catch {
            return nil
        }
    }
}
