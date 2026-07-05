import AVFoundation

/// Captures the microphone and resamples to 16 kHz mono 16-bit PCM (the sweet spot for
/// speech APIs: tiny payloads, no quality loss for ASR). Writes a WAV file on stop.
final class AudioRecorder {
    enum RecorderError: Error { case noInput, unsupportedFormat }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16000,
                                             channels: 1,
                                             interleaved: true)!
    private var pcmData = Data()
    private let lock = NSLock()
    private var isRecording = false

    /// Normalized 0…1 input level per buffer, for the recording overlay. Called off the main thread.
    var onLevel: ((Float) -> Void)?

    func start() throws {
        guard !isRecording else { return }
        lock.lock(); pcmData.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw RecorderError.noInput }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Leave the node clean: a leftover tap makes the next installTap throw an
            // Objective-C exception (uncatchable from Swift) and crash the app.
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); let data = pcmData; lock.unlock()
        guard !data.isEmpty else { return nil }
        return writeWav(data)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.int16ChannelData else { return }
        let count = Int(out.frameLength)
        guard count > 0 else { return }
        let bytes = Data(bytes: channel[0], count: count * MemoryLayout<Int16>.size)
        lock.lock(); pcmData.append(bytes); lock.unlock()

        if let onLevel {
            let samples = channel[0]
            var sum: Float = 0
            for i in 0..<count {
                let sample = Float(samples[i]) / 32768.0
                sum += sample * sample
            }
            onLevel(sqrt(sum / Float(count)))
        }
    }

    private func writeWav(_ pcm: Data) -> URL? {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)

        var out = Data()
        out.appendASCII("RIFF")
        out.appendLE(UInt32(36) + dataSize)
        out.appendASCII("WAVE")
        out.appendASCII("fmt ")
        out.appendLE(UInt32(16))
        out.appendLE(UInt16(1))                // PCM
        out.appendLE(channels)
        out.appendLE(sampleRate)
        out.appendLE(byteRate)
        out.appendLE(blockAlign)
        out.appendLE(bitsPerSample)
        out.appendASCII("data")
        out.appendLE(dataSize)
        out.append(pcm)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("susurro-\(UUID().uuidString).wav")
        do {
            try out.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private extension Data {
    mutating func appendASCII(_ s: String) {
        if let d = s.data(using: .ascii) { append(d) }
    }
    mutating func appendLE(_ v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: MemoryLayout<UInt16>.size))
    }
    mutating func appendLE(_ v: UInt32) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: MemoryLayout<UInt32>.size))
    }
}
