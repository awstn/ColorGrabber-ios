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

/// The average color of the sampled square in one frame.
private struct PixelAverage {
    let red: Double
    let green: Double
    let blue: Double
}

/// Runs the camera and takes a spot reading from the center of the frame on request.
final class CameraModel: NSObject, ObservableObject {
    @Published var reading: Reading?
    @Published var errorMessage: String?
    @Published var isMeasuring = false

    let session = AVCaptureSession()

    /// Width and height of the sampled square, in camera pixels.
    /// One screen point covers about 2.2 camera pixels, so 60 fills the 30-point crosshair.
    private let sampleSize = 60
    /// Seconds of frames averaged into one spot reading, to smooth out frame-to-frame noise.
    private let measureDuration = 0.5

    private let cameraQueue = DispatchQueue(label: "camera")
    private var isCollecting = false
    private var collected: [PixelAverage] = []
    private var collectionStart = 0.0

    /// Starts a spot reading. The result replaces `reading` once enough frames are collected.
    func takeReading() {
        guard !isMeasuring else { return }
        isMeasuring = true
        cameraQueue.async {
            self.collected = []
            self.isCollecting = true
        }
    }

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
    /// Called on cameraQueue for every frame. Frames are ignored unless a reading is in progress.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isCollecting,
              let frame = sampleBuffer.imageBuffer,
              let average = centerAverage(of: frame) else { return }

        let now = sampleBuffer.presentationTimeStamp.seconds
        if collected.isEmpty { collectionStart = now }
        collected.append(average)
        guard now - collectionStart >= measureDuration else { return }

        isCollecting = false
        let primaries = CVBufferCopyAttachment(frame, kCVImageBufferColorPrimariesKey, nil) as? String
        let reading = makeReading(from: collected, colorPrimaries: primaries ?? "unknown")
        DispatchQueue.main.async {
            self.reading = reading
            self.isMeasuring = false
        }
    }

    /// Averages the collected frames into one reading.
    private func makeReading(from frames: [PixelAverage], colorPrimaries: String) -> Reading {
        let count = Double(frames.count)
        let red = frames.reduce(0) { $0 + $1.red } / count
        let green = frames.reduce(0) { $0 + $1.green } / count
        let blue = frames.reduce(0) { $0 + $1.blue } / count

        return Reading(red: Int(red.rounded()),
                       green: Int(green.rounded()),
                       blue: Int(blue.rounded()),
                       color: ColorConversion.oklch(red: red, green: green, blue: blue),
                       colorPrimaries: colorPrimaries)
    }

    /// Averages the square of pixels at the center of the frame.
    /// The frame's center is the preview's center at any rotation, so it's always under the crosshair.
    private func centerAverage(of frame: CVPixelBuffer) -> PixelAverage? {
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

        let count = Double(sampleSize * sampleSize)
        return PixelAverage(red: Double(redTotal) / count,
                            green: Double(greenTotal) / count,
                            blue: Double(blueTotal) / count)
    }
}
