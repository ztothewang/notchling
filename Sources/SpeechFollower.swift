import AVFoundation
import Speech

/// Streams microphone audio into on-device speech recognition and reports the
/// words heard so far in the current recognition session.
@MainActor
final class SpeechFollower {
    private let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let requestBox = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var running = false

    var onWords: (([String]) -> Void)?
    var onStatus: ((String) -> Void)?

    /// Asks for microphone and speech recognition access if not yet decided.
    static func requestPermissions(_ done: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { mic in
            SFSpeechRecognizer.requestAuthorization { speech in
                DispatchQueue.main.async { done(mic && speech == .authorized) }
            }
        }
    }

    func start() {
        guard !running else { return }
        Self.requestPermissions { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.onStatus?("Microphone or Speech Recognition access denied. Enable both in System Settings → Privacy & Security.")
                return
            }
            self.begin()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        requestBox.request?.endAudio()
        requestBox.request = nil
        task?.cancel()
        task = nil
        onStatus?("Voice follow off")
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            onStatus?("Speech recognition is unavailable for this language.")
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let box = requestBox
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onStatus?("Could not start the microphone: \(error.localizedDescription)")
            return
        }
        running = true
        startTask()
        onStatus?(recognizer.supportsOnDeviceRecognition ? "Listening (on-device)" : "Listening")
    }

    private func startTask() {
        guard running, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        requestBox.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.segments.map(\.substring)
            let finished = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                guard let self, self.requestBox.request === request else { return }
                if let words { self.onWords?(words) }
                // Recognition sessions end on silence or time limits; start a fresh one.
                if finished {
                    request.endAudio()
                    self.startTask()
                }
            }
        }
    }
}

/// Shared between the main thread and the audio tap thread.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.lock(); defer { lock.unlock() }; return _request }
        set { lock.lock(); _request = newValue; lock.unlock() }
    }
}
