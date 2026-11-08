import AVFoundation
import Foundation
import Speech

@MainActor
final class DictationController: ObservableObject {
    @Published var isListening = false
    @Published var message: String?
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var stopping = false
    private var generation = 0
    private var base = ""
    private var onText: ((String) -> Void)?

    func toggle(current: String, onText: @escaping (String) -> Void, onStop: @escaping (String) -> Void) {
        if isListening {
            let text = current
            stop()
            onStop(text)
            return
        }
        self.onText = onText
        base = current.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil
        Task { await start() }
    }

    func stop() {
        generation += 1
        stopping = true
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        stopping = false
    }

    private func start() async {
        let token = generation
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "On-device dictation isn't available on this iPhone. Type the note, or use the microphone on the keyboard."
            return
        }
        let speech = await requestSpeechAuthorization()
        guard token == generation else { return }
        guard speech == .authorized else {
            message = "Speech recognition permission is off."
            return
        }
        let mic = await requestMicrophone()
        guard token == generation else { return }
        guard mic else {
            message = "Microphone permission is off."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                message = "The microphone didn't start. Type the note instead."
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            self.engine = engine
            engine.prepare()
            try engine.start()
            isListening = true
            message = "Dictating on this iPhone. Tap again to stop."
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        let combined = self.base.isEmpty ? spoken : self.base + " " + spoken
                        self.onText?(combined)
                    }
                    if error != nil, !self.stopping, self.isListening {
                        self.message = "Dictation stopped. The text already captured is still in the note."
                        self.stop()
                    }
                }
            }
        } catch {
            message = "The microphone didn't start. Type the note instead."
            stop()
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
