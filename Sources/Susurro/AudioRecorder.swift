import AVFoundation

/// A finished capture: the WAV on disk plus the signal stats the app uses to discard
/// recordings that contain no speech (Whisper hallucinates phrases on silent audio).
struct Recording {
    let fileURL: URL
    let duration: TimeInterval
    /// Loudest per-buffer RMS seen during the capture, linear 0…1.
    let peakLevel: Float
    /// Seconds of audio whose buffers exceeded the speech threshold. Speech has sustained
    /// energy; sparse transients (key clicks, a cough) barely accumulate any.
    let activeDuration: TimeInterval
}

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
    /// Linear RMS ≈ −45 dB: quieter buffers count as room noise, not speech.
    private let speechThreshold: Float = 0.006

    private var pcmData = Data()
    private var peakRMS: Float = 0
    private var activeSamples = 0
    private let lock = NSLock()
    private var isRecording = false

    /// Normalized 0…1 input level per buffer, for the recording overlay. Called off the main thread.
    var onLevel: ((Float) -> Void)?

    func start() throws {
        guard !isRecording else { return }
        lock.lock(); pcmData.removeAll(keepingCapacity: true); peakRMS = 0; activeSamples = 0; lock.unlock()

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

    func stop() -> Recording? {
        guard isRecording else { return nil }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); let data = pcmData; let peak = peakRMS; let active = activeSamples; lock.unlock()
        guard !data.isEmpty, let url = writeWav(data) else { return nil }
        let duration = Double(data.count / MemoryLayout<Int16>.size) / targetFormat.sampleRate
        return Recording(fileURL: url,
                         duration: duration,
                         peakLevel: peak,
                         activeDuration: Double(active) / targetFormat.sampleRate)
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

        let samples = channel[0]
        var sum: Float = 0
        for i in 0..<count {
            let sample = Float(samples[i]) / 32768.0
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))

        let bytes = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
        lock.lock()
        pcmData.append(bytes)
        peakRMS = max(peakRMS, rms)
        if rms > speechThreshold { activeSamples += count }
        lock.unlock()

        onLevel?(rms)
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
