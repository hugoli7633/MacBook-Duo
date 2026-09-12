import SwiftUI
import AppKit

struct HingeDemoView: View {
    let onset: Double
    @ObservedObject var desktop: DesktopPreviewCapture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = true
    @State private var visible = false
    @State private var elapsed = 0.0
    @State private var manualAngle = 110.0

    private var running: Bool { playing && visible && !reduceMotion }
    private var angle: Double {
        playing && !reduceMotion ? HingeDemoMotion.angle(time: elapsed, onset: onset) : manualAngle
    }
    private var progress: Double { EffectAngle.progress(angle: angle, onset: onset) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("效果预览").font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    if playing { manualAngle = angle }
                    playing.toggle()
                } label: {
                    Image(systemName: playing && !reduceMotion ? "pause.fill" : "play.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(reduceMotion)
                .help(playing ? "暂停演示" : "播放演示")
                .accessibilityLabel(playing ? "暂停演示" : "播放演示")
            }
            ZStack(alignment: .bottom) {
                Ellipse().fill(.black.opacity(0.12)).frame(width: 405, height: 15)
                    .blur(radius: 9).offset(y: 7)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: MacBookProductImage.lid).resizable()
                    if let image = desktop.image {
                        GlassSurface(image: image, tilt: 80 * progress, frost: 0.09, distance: 2.4)
                            .frame(width: 340, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .offset(x: 5, y: 8.75)
                        UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                            .fill(.black).frame(width: 40, height: 8)
                            .offset(x: 155, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.4))
                            .frame(width: 340, height: 220).offset(x: 5, y: 8.75)
                        Text("等待桌面授权")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 350, height: 238)
                    }
                }
                .frame(width: 350, height: 237.5)
                .rotation3DEffect(.degrees((angle - 100) * 0.5), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.35)
                .offset(y: -15)
                Image(nsImage: MacBookProductImage.base).resizable()
                    .frame(width: 427.5, height: 20)
            }
            .frame(maxWidth: .infinity).frame(height: 265)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("MacBook Pro 桌面预览，\(desktop.image == nil ? "等待桌面授权" : (progress > 0 ? "逐渐模糊" : "保持清晰"))")

            HStack {
                Text(desktop.message).foregroundStyle(.secondary)
                Spacer()
                Button { desktop.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless).disabled(desktop.loading)
                .help("刷新桌面快照").accessibilityLabel("刷新桌面快照")
            }.font(.caption)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
        .background(WindowVisibilityObserver(visible: $visible).frame(width: 0, height: 0))
        .onChange(of: visible) { _, shown in
            if shown { desktop.refresh() }
        }
        .task(id: running) {
            guard running else { return }
            var previous = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                let now = Date()
                elapsed += min(0.1, now.timeIntervalSince(previous))
                previous = now
            }
        }
    }
}

private struct WindowVisibilityObserver: NSViewRepresentable {
    @Binding var visible: Bool
    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = { visible = $0 }
        return view
    }
    func updateNSView(_ view: VisibilityView, context: Context) {}
}

private final class VisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let window {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                self?.publishVisibility()
            }
        }
        publishVisibility()
    }
    private func publishVisibility() {
        let shown = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        DispatchQueue.main.async { [weak self] in self?.onChange?(shown) }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor
private enum MacBookProductImage {
    private static let original: CGImage = {
        let url = Bundle.main.url(forResource: "MacBookPro14", withExtension: "png")!
        let image = NSImage(contentsOf: url)!
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }()
    // Pixel coordinates in the bundled Apple product photograph, not synthetic hardware.
    static let lid = NSImage(cgImage: original.cropping(to: CGRect(x: 460, y: 274, width: 280, height: 190))!,
                             size: NSSize(width: 280, height: 190))
    static let base = NSImage(cgImage: original.cropping(to: CGRect(x: 428, y: 464, width: 342, height: 16))!,
                              size: NSSize(width: 342, height: 16))
}
