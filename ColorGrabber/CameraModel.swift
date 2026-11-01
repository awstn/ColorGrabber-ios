import AVFoundation
import Combine

/// The latest measurement from the crosshair.
struct Reading {
    let red: Int
    let green: Int
    let blue: Int
    let color: OKLCH
    /// The color primaries the camera reports for this frame, used to confirm the sRGB assumption.
    let colorPrimaries: String

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

/// Runs the camera and turns the center of each frame into a Reading.
final class CameraModel: NSObject, ObservableObject {
    @Published var reading: Reading?
    @Published var errorMessage: String?

    let session = AVCaptureSession()

    /// Width and height of the sampled square, in camera pixels.
    /// sample size = crosshair width + crosshair height
    private let sampleSize = 60
    /// Seconds between readings, so the numbers stay readable (5 per second).
    private let updateInterval = 0.2

    private let cameraQueue = DispatchQueue(label: "camera")
    private var lastUpdate = 0.0

    /// Asks for camera permission, then starts the camera.
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                self.show(error: "Camera access is off. Turn it on in Settings.")
                return
            }
            self.cameraQueue.async {
                self.configureSession()
                self.session.startRunning()
            }
        }
    }

    private func configureSession() {
        guard !session.isRunning, session.inputs.isEmpty else { return }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            show(error: "No camera found. This app needs a real iPhone.")
            return
        }

        session.beginConfiguration()
        // Stops iOS from switching to wide color, which would break our sRGB math.
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.sessionPreset = .hd1920x1080

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: cameraQueue)

        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            show(error: "Couldn't set up the camera.")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        if camera.activeFormat.supportedColorSpaces.contains(.sRGB), (try? camera.lockForConfiguration()) != nil {
            camera.activeColorSpace = .sRGB
            camera.unlockForConfiguration()
        }
    }

    private func show(error: String) {
        DispatchQueue.main.async { self.errorMessage = error }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on cameraQueue for every frame.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = sampleBuffer.presentationTimeStamp.seconds
        guard now - lastUpdate >= updateInterval,
              let frame = sampleBuffer.imageBuffer,
              let reading = centerReading(of: frame) else { return }

        lastUpdate = now
        DispatchQueue.main.async { self.reading = reading }
    }

    /// Averages the square of pixels at the center of the frame.
    /// The frame's center is the preview's center at any rotation, so it's always under the crosshair.
    private func centerReading(of frame: CVPixelBuffer) -> Reading? {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        let left = (CVPixelBufferGetWidth(frame) - sampleSize) / 2
        let top = (CVPixelBufferGetHeight(frame) - sampleSize) / 2

        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0

        // Each pixel is 4 bytes, stored in blue, green, red, alpha order.
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in top..<(top + sampleSize) {
            for x in left..<(left + sampleSize) {
                let offset = y * bytesPerRow + x * 4
                blueTotal += Int(pixels[offset])
                greenTotal += Int(pixels[offset + 1])
                redTotal += Int(pixels[offset + 2])
            }
        }

        let count = sampleSize * sampleSize
        let red = redTotal / count
        let green = greenTotal / count
        let blue = blueTotal / count

        let primaries = CVBufferCopyAttachment(frame, kCVImageBufferColorPrimariesKey, nil) as? String

        return Reading(red: red,
                       green: green,
                       blue: blue,
                       color: ColorConversion.oklch(red: Double(red), green: Double(green), blue: Double(blue)),
                       colorPrimaries: primaries ?? "unknown")
    }
}
