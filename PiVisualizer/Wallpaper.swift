import Observation
import SwiftUI

/// Renders the current visualization as a phone wallpaper and offers it for saving or sharing.
@MainActor
@Observable
final class Wallpaper {
    static let shared = Wallpaper()

    struct Rendered: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    /// A finished wallpaper waiting to be previewed.
    var rendered: Rendered?
    /// Snapshots the live 3D view; registered by the visible 3D scene.
    @ObservationIgnored var snapshot3D: (() -> UIImage?)?

    /// iPhone 15 Pro Max size in points; rendered at 3× (1290 × 2796 pixels).
    private static let size = CGSize(width: 430, height: 932)

    /// Renders a SwiftUI visualization, centred on black.
    func render(_ content: some View) {
        let page = ZStack {
            Color.black
            content.aspectRatio(1, contentMode: .fit).padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 3
        if let image = renderer.uiImage { rendered = Rendered(image: image) }
    }

    /// Places a snapshot of the 3D view in the middle of a black wallpaper.
    func renderSnapshot() {
        guard let shot = snapshot3D?() else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: Self.size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: Self.size))
            let fit = min(Self.size.width / shot.size.width, Self.size.height / shot.size.height)
            let drawn = CGSize(width: shot.size.width * fit, height: shot.size.height * fit)
            shot.draw(in: CGRect(x: (Self.size.width - drawn.width) / 2, y: (Self.size.height - drawn.height) / 2,
                                 width: drawn.width, height: drawn.height))
        }
        rendered = Rendered(image: image)
    }
}

/// The finished wallpaper: share it or save it to Photos, then set it from the Photos app.
struct WallpaperPreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2)))
                HStack(spacing: 12) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Magic of π", image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        saved = true
                    } label: {
                        Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(saved)
                }
                .controlSize(.large)
                Text("To use it: Photos → share → Use as Wallpaper.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
