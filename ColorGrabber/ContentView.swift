import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Fills the whole screen like the preview, so both share the same center.
            Crosshair()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack {
                Spacer()
                readout
            }
        }
        .background(.black)
        .onAppear { camera.start() }
    }

    @ViewBuilder
    private var readout: some View {
        Group {
            if let message = camera.errorMessage {
                Text(message)
            } else if let reading = camera.reading {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "L %.2f   C %.3f   h %.1f°",
                                reading.color.lightness,
                                reading.color.chroma,
                                reading.color.hue))
                    Text("\(reading.hex)   primaries: \(reading.colorPrimaries)")
                        .font(.caption.monospaced())
                }
            } else {
                Text("Starting camera…")
            }
        }
        .font(.title3.monospaced())
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

/// Marks the center of the screen. The square roughly matches the sampled pixels.
private struct Crosshair: View {
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(lineWidth: 1)
                .frame(width: 30, height: 30)
        }
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 1)
        .allowsHitTesting(false)
    }
}

/// Wraps the UIKit camera preview so SwiftUI can display it.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

#Preview {
    ContentView()
}
