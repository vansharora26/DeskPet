import AVFoundation
import DeskPetCore

/// Real-time sound synthesis for ambient soundscapes. Everything is generated
/// from noise and simple oscillators, so there are no recordings or licences
/// involved. Runs on the audio thread; parameters are plain floats that the
/// main thread updates (benign, smoothed per sample).
final class AmbientGenerator: @unchecked Sendable {
    var sound: AmbientSound = .rain
    /// Desired output gain (0…1); the actual gain glides towards it to avoid clicks.
    var targetGain: Float = 0
    private(set) var gain: Float = 0
    let sampleRate: Double

    private var rng: UInt64 = 0x9E3779B97F4A7C15
    // Filter / generator state per channel.
    private var brown: [Float] = [0, 0]
    private var pink: [[Float]] = [[0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]]
    private var lowpass: [Float] = [0, 0]
    private var t: Double = 0
    // Short events (raindrops, crackles, chirps).
    private var dropEnv: Float = 0, dropPhase: Float = 0, dropFreq: Float = 3000
    private var crackleEnv: Float = 0
    private var chirpTime: Double = -1, chirpStart: Float = 0, nextChirp: Double = 4

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    @inline(__always) private func white() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(Int64(bitPattern: rng) >> 11) / Float(1 << 52)   // ≈ -1…1
    }

    @inline(__always) private func pinkNoise(_ ch: Int) -> Float {
        let w = white()
        var b = pink[ch]
        b[0] = 0.99886 * b[0] + w * 0.0555179
        b[1] = 0.99332 * b[1] + w * 0.0750759
        b[2] = 0.96900 * b[2] + w * 0.1538520
        b[3] = 0.86650 * b[3] + w * 0.3104856
        b[4] = 0.55000 * b[4] + w * 0.5329522
        b[5] = -0.7616 * b[5] - w * 0.0168980
        let out = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
        b[6] = w * 0.115926
        pink[ch] = b
        return out * 0.11
    }

    @inline(__always) private func brownNoise(_ ch: Int) -> Float {
        brown[ch] = (brown[ch] + 0.02 * white()) / 1.02
        return brown[ch] * 3.2
    }

    /// Fills non-interleaved stereo float buffers.
    func render(_ frames: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        let dt = 1 / sampleRate
        let glide: Float = 1 / Float(sampleRate * 0.35)
        for i in 0..<frames {
            gain += (targetGain - gain) * glide * 8
            if abs(targetGain - gain) < glide { gain = targetGain }
            var l: Float = 0, r: Float = 0
            switch sound {
            case .rain:
                // Steady hiss (pink, gently lowpassed) + scattered droplets.
                lowpass[0] += 0.35 * (pinkNoise(0) - lowpass[0])
                lowpass[1] += 0.35 * (pinkNoise(1) - lowpass[1])
                l = lowpass[0] * 0.9; r = lowpass[1] * 0.9
                if white() > 0.9993 { dropEnv = 0.5 + 0.5 * abs(white()); dropFreq = 1800 + 2600 * abs(white()) }
                dropPhase += Float(2 * Double.pi * Double(dropFreq) * dt)
                let drop = sin(dropPhase) * dropEnv * 0.08
                dropEnv *= 0.9965
                l += drop; r += drop * 0.6
            case .forest:
                // Wind: brown noise with slow gusts; occasional quiet bird chirps.
                let gust = Float(0.55 + 0.45 * sin(2 * .pi * 0.07 * t) * sin(2 * .pi * 0.031 * t + 1))
                l = brownNoise(0) * gust * 0.8; r = brownNoise(1) * gust * 0.8
                if t >= nextChirp && chirpTime < 0 {
                    chirpTime = 0; chirpStart = 2600 + 1200 * abs(white())
                }
                if chirpTime >= 0 {
                    let p = Float(chirpTime / 0.09)
                    let f = chirpStart + 1800 * p
                    let env = sin(Float.pi * min(1, p)) * 0.05
                    let s = sin(Float(2 * Double.pi * chirpTime) * f) * env
                    l += s; r += s * 0.4
                    chirpTime += dt
                    if chirpTime > 0.09 {
                        chirpTime = -1
                        nextChirp = t + 3 + 9 * Double(abs(white()))
                    }
                }
            case .brownNoise:
                l = brownNoise(0) * 0.7; r = brownNoise(1) * 0.7
            case .fireplace:
                // Low rumble + crackles.
                lowpass[0] += 0.05 * (brownNoise(0) - lowpass[0])
                l = lowpass[0] * 1.6; r = l
                if white() > 0.9994 { crackleEnv = 0.6 + 0.4 * abs(white()) }
                let c = white() * crackleEnv * 0.25
                crackleEnv *= 0.985
                l += c; r += c * 0.8
            }
            left[i] = max(-1, min(1, l * gain))
            right[i] = max(-1, min(1, r * gain))
            t += dt
        }
    }
}

/// Plays one ambient soundscape at a time (no overlap), with fades.
@MainActor
final class AmbientAudioEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var current: AmbientSound?
    @Published private(set) var lastError: String?

    private var engine: AVAudioEngine?
    private var generator: AmbientGenerator?
    private var stopWork: DispatchWorkItem?
    private var volume: Float = 0.45

    /// Starts (or switches to) a sound. Switching reuses the same engine, so
    /// two soundscapes can never play at once.
    func play(_ sound: AmbientSound, volume: Double) {
        self.volume = Float(min(1, max(0, volume)))
        stopWork?.cancel()
        if let generator, let engine, engine.isRunning {
            if current != sound {
                // Quick dip, swap, fade back in.
                generator.targetGain = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, self.generator === generator else { return }
                    generator.sound = sound
                    generator.targetGain = self.volume
                }
            } else {
                generator.targetGain = self.volume
            }
            current = sound
            isPlaying = true
            return
        }
        do {
            let engine = AVAudioEngine()
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate > 0
                ? engine.outputNode.outputFormat(forBus: 0).sampleRate : 44_100
            let gen = AmbientGenerator(sampleRate: rate)
            gen.sound = sound
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let node = Self.makeSourceNode(gen, format: format)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try engine.start()
            gen.targetGain = self.volume
            self.engine = engine
            self.generator = gen
            current = sound
            isPlaying = true
            lastError = nil
        } catch {
            lastError = "Couldn’t start audio: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    func setVolume(_ v: Double) {
        volume = Float(min(1, max(0, v)))
        if isPlaying { generator?.targetGain = volume }
    }

    /// Fades out, then releases the audio engine.
    func stop(fade: TimeInterval = 0.8) {
        guard engine != nil else { isPlaying = false; return }
        generator?.targetGain = 0
        isPlaying = false
        let work = DispatchWorkItem { [weak self] in
            self?.engine?.stop()
            self?.engine = nil
            self?.generator = nil
            self?.current = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: work)
    }

    nonisolated static func makeSourceNode(_ gen: AmbientGenerator, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            gen.render(Int(frameCount), l, r)
            return noErr
        }
    }

    /// Renders a sound offline (no speakers) — used by the self-test to prove it's real audio.
    nonisolated static func renderOffline(_ sound: AmbientSound, seconds: Double) throws -> (rms: Float, peak: Float) {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let gen = AmbientGenerator(sampleRate: 44_100)
        gen.sound = sound
        gen.targetGain = 0.5
        let node = makeSourceNode(gen, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var sumSq: Double = 0, count = 0, peak: Float = 0
        let total = AVAudioFramePosition(seconds * 44_100)
        while engine.manualRenderingSampleTime < total {
            let n = min(AVAudioFrameCount(total - engine.manualRenderingSampleTime), 4096)
            _ = try engine.renderOffline(n, to: buffer)
            // Skip the fade-in when measuring.
            if engine.manualRenderingSampleTime > 22_050, let data = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) {
                    sumSq += Double(data[i] * data[i]); count += 1
                    peak = max(peak, abs(data[i]))
                }
            }
        }
        engine.stop()
        return (Float(sqrt(sumSq / Double(max(1, count)))), peak)
    }
}
