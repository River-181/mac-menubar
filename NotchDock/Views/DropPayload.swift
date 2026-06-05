import Foundation
import UniformTypeIdentifiers

enum DropPayload {
    /// Resolves dropped file URLs from item providers, then calls completion on the main thread.
    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                } else if let string = item as? String {
                    resolved = URL(string: string)
                }
                if let resolved {
                    lock.lock()
                    urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}
