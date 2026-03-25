import SwiftUI

// MARK: - Legacy Container Background Modifier

#if os(macOS)

extension View {
    func legacy_containerBackground(_ material: Material) -> some View {
        if #available(macOS 15.0, *) {
            return self.containerBackground(material, for: .window)
        } else {
            return self
        }
    }
}
#else

extension View {
    func legacy_containerBackground(_ material: Material) -> some View {
        return self
    }
}
#endif
