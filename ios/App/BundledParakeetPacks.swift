import Foundation

/// Starter model descriptors are data. Compatible owner-supplied descriptors
/// use the same adapter without adding repository names to executable logic.
enum BundledParakeetPacks {
    static var manifests: [ModelManifest] {
        guard let url = Bundle.main.url(forResource: "Parakeet-v3", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? ParakeetModelPack.decode(data) else { return [] }
        return [manifest]
    }
}
