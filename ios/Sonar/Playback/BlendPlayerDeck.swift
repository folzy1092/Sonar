import AVFoundation
import Foundation

// Дек сведения поверх элемента AVQueuePlayer (docs/BLEND.md §13): время, скорость и высота — у плеера и элемента,
// кривые перехода — в `BlendDeckDSP`, который стоит первым в тапе элемента (`AudioTap.attach(blend:)`).
// HLS тап не пропускает — у такого дека из всей программы остаётся только громкость: её шагает
// `BlendDeckAutomation` раз в 50 мс и ставит в `player.volume` (без фильтров, эха и сдвига тона).
// Один дек — один элемент: цепочка обработки живёт со своим элементом и не делится между треками.

@MainActor
final class BlendPlayerDeck: BlendDeckControl {
    static let hlsStepSec = 0.05

    let player: AVQueuePlayer
    let item: AVPlayerItem
    let hls: Bool
    let dsp = BlendDeckDSP()
    /// Громкость дека без сведения (нормализация трека) — HLS умножает на неё громкость кривых.
    var baseGain = 1.0
    /// Громкость кривых у HLS (у файла — всегда 1, громкость в тапе).
    private(set) var hlsGain = 1.0

    private var automation = BlendDeckAutomation()
    private var stepper: Task<Void, Never>?

    init(player: AVQueuePlayer, item: AVPlayerItem, hls: Bool) {
        self.player = player
        self.item = item
        self.hls = hls
    }

    /// Элемент ещё стоит в своём плеере (дек не отпущен и не заменён).
    var isLoaded: Bool { player.items().contains { $0 === item } }

    var currentTime: Double {
        get {
            let t = item.currentTime().seconds
            return t.isFinite ? t : 0
        }
        set {
            item.seek(to: CMTime(seconds: max(0, newValue), preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        }
    }

    var rate: Double {
        get { Double(player.defaultRate) }
        set {
            let r = Float(newValue)
            player.defaultRate = r
            if player.rate != 0 { player.rate = r }
        }
    }

    var preservesPitch: Bool {
        get { item.audioTimePitchAlgorithm != .varispeed }
        set {
            let algorithm: AVAudioTimePitchAlgorithm = newValue ? .timeDomain : .varispeed
            if item.audioTimePitchAlgorithm != algorithm { item.audioTimePitchAlgorithm = algorithm }
        }
    }

    var isPaused: Bool { player.timeControlStatus == .paused }

    func play() {
        player.playImmediately(atRate: player.defaultRate)
    }

    func pause() {
        player.pause()
    }

    func blendStart(_ program: BlendDeckProgram?, echoDelaySec: Double) {
        guard hls else {
            dsp.start(program, echoDelaySec: echoDelaySec)
            return
        }
        automation.start(program)
        step()
    }

    func blendRamp(_ ramp: BlendRamp) {
        guard hls else {
            dsp.ramp(ramp)
            return
        }
        automation.enqueue(ramp)
        step()
    }

    func blendShift(_ ratio: Double) {
        // у HLS сдвига тона нет: тап к потоку не подключается
        if !hls { dsp.setShift(ratio) }
    }

    /// Дек отпущен: обычный звук и никаких шагов громкости.
    func stop() {
        stepper?.cancel()
        stepper = nil
        if hls {
            automation.start(nil)
            hlsGain = 1
        } else {
            dsp.start(nil, echoDelaySec: 0)
        }
    }

    // MARK: - HLS: громкость по кривым

    private func step() {
        guard stepper == nil else { return }
        stepper = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let values = self.automation.step(ms: self.currentTime * 1000, dt: now.timeIntervalSince(last))
                last = now
                self.hlsGain = values.gain
                self.player.volume = Float(self.baseGain * values.gain)
                if self.automation.isIdle {
                    self.stepper = nil
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.hlsStepSec * 1_000_000_000))
            }
        }
    }
}
