import AVFoundation
import MediaToolbox
import os

/// Эквалайзер и нормализация громкости на iPhone: `MTAudioProcessingTap` в `AVAudioMix` элемента
/// плеера. Звук трека проходит через 12 фильтров (`Equalizer`) и выравниватель (`Leveler`) — числа и
/// формулы в `PlayerDSP.swift`.
///
/// Ограничение AVFoundation: `audioMix` работает только для файлов — Яндекс (mp3 / FLAC), SoundCloud через
/// Яндекс, прогрессивный mp3 SoundCloud и скачанные треки. Поток HLS (почти весь SoundCloud) AVPlayer
/// отдаёт мимо `audioMix` — там эквалайзер и нормализация не звучат (сказано в настройках).
enum AudioTap {
    /// Текущие настройки звука — одни на все элементы плеера.
    static let params = AudioTapParams()

    /// Подключить обработку к элементу. Звуковая дорожка известна, когда элемент готов (`readyToPlay`):
    /// тогда `tracks` у файла уже есть. Уже подключено или дорожки нет — ничего.
    @MainActor
    static func attach(to item: AVPlayerItem) {
        guard item.audioMix == nil,
              let track = item.tracks.compactMap(\.assetTrack).first(where: { $0.mediaType == .audio }) else { return }
        guard let tap = makeTap(TapContext(params: params)) else { return }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        item.audioMix = mix
    }

    /// Вне главного актора: обработчики зовёт звуковой поток, замыкание с главного актора упало бы на
    /// проверке изоляции.
    nonisolated private static func makeTap(_ context: TapContext) -> MTAudioProcessingTap? {
        let info = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: Int32(kMTAudioProcessingTapCallbacksVersion_0),
            clientInfo: info,
            init: { _, clientInfo, storageOut in
                // контекст уже удержан passRetained — отпускает finalize
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(format: format.pointee, maxFrames: Int(maxFrames))
            },
            unprepare: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().unprepare()
            },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
                guard status == noErr else { return }
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .process(buffers, frames: Int(framesOut.pointee))
            }
        )
        var unmanaged: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                MTAudioProcessingTapCreationFlags(kMTAudioProcessingTapCreationFlag_PostEffects), &unmanaged)
        // Create отдаёт +1 (правило Create) — забираем владение
        guard status == noErr, let tap = unmanaged?.takeRetainedValue() else {
            // init не позвали — удержание снимаем сами
            Unmanaged<TapContext>.fromOpaque(info).release()
            return nil
        }
        return tap
    }
}

/// Настройки звука для звукового потока: пишет главный поток, читает обработчик (замок, без ожидания —
/// занят, значит берём прежние).
final class AudioTapParams: Sendable {
    struct Values: Sendable {
        var gains: [Double] = Equalizer.flat
        var eqEnabled = true
        var normalize = false
        var version = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: Values())

    func update(gains: [Double], eqEnabled: Bool, normalize: Bool) {
        lock.withLock { values in
            values.gains = gains
            values.eqEnabled = eqEnabled
            values.normalize = normalize
            values.version &+= 1
        }
    }

    /// Новые значения, если поменялись с версии `seen`.
    func values(newerThan seen: Int) -> Values? {
        lock.withLockIfAvailable { values in values.version == seen ? nil : values } ?? nil
    }
}

/// Состояние одного элемента плеера. Всё, кроме init, — на звуковом потоке AVFoundation.
private final class TapContext: @unchecked Sendable {
    private static let bands = Equalizer.frequencies.count
    private static let maxChannels = 8

    private let params: AudioTapParams
    private var version = -1
    private var sampleRate: Double = 44100
    private var ready = false
    private var channels = 0
    private var eqOn = false
    private var normalize = false
    private var leveler = Leveler.State()
    private let coefficients = UnsafeMutablePointer<FloatBiquad>.allocate(capacity: TapContext.bands)
    private let active = UnsafeMutablePointer<Bool>.allocate(capacity: TapContext.bands)
    private let states = UnsafeMutablePointer<BiquadState>.allocate(capacity: TapContext.bands * TapContext.maxChannels)

    init(params: AudioTapParams) {
        self.params = params
        coefficients.initialize(repeating: FloatBiquad(.identity), count: Self.bands)
        active.initialize(repeating: false, count: Self.bands)
        states.initialize(repeating: BiquadState(), count: Self.bands * Self.maxChannels)
    }

    deinit {
        coefficients.deallocate()
        active.deallocate()
        states.deallocate()
    }

    /// Работаем только с float32 PCM (так AVPlayer отдаёт почти всегда); иное — пропускаем как есть.
    func prepare(format: AudioStreamBasicDescription, maxFrames _: Int) {
        let isFloat = format.mFormatID == AudioFormatID(kAudioFormatLinearPCM)
            && format.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsFloat) != 0
            && format.mBitsPerChannel == 32
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100
        channels = Int(format.mChannelsPerFrame)
        ready = isFloat && channels > 0 && channels <= Self.maxChannels
        version = -1
        states.update(repeating: BiquadState(), count: Self.bands * Self.maxChannels)
    }

    func unprepare() {
        ready = false
    }

    private func refresh() {
        guard let values = params.values(newerThan: version) else { return }
        version = values.version
        normalize = values.normalize
        eqOn = values.eqEnabled && !Equalizer.isFlat(values.gains)
        let filters = Equalizer.filters(values.gains, sampleRate: sampleRate)
        for band in 0 ..< Self.bands {
            let filter = band < filters.count ? filters[band] : .identity
            let wasActive = active[band]
            active[band] = eqOn && !filter.isIdentity
            coefficients[band] = FloatBiquad(filter)
            // полоса только что включилась — с чистой памятью, без щелчка от старых значений
            if active[band], !wasActive {
                for channel in 0 ..< Self.maxChannels { states[channel * Self.bands + band] = BiquadState() }
            }
        }
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard ready, frames > 0 else { return }
        refresh()
        let levelerBusy = normalize || abs(leveler.gain - 1) > 0.001
        guard eqOn || levelerBusy else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var sum: Double = 0
        var count = 0

        // 1. эквалайзер на месте + сумма квадратов для оценки громкости (после эквалайзера, как на ПК)
        var channelBase = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = max(1, Int(buffer.mNumberChannels))
            let length = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride))
            for c in 0 ..< stride where channelBase + c < Self.maxChannels {
                let state = states + (channelBase + c) * Self.bands
                var i = c
                for _ in 0 ..< length {
                    var x = data[i]
                    if eqOn {
                        for band in 0 ..< Self.bands where active[band] {
                            x = state[band].process(x, coefficients[band])
                        }
                        data[i] = x
                    }
                    sum += Double(x) * Double(x)
                    i += stride
                }
                count += length
            }
            channelBase += stride
        }

        // 2. выравниватель: усиление плавно от прошлого к новому за блок; громче 0 дБ — мягкий предел
        let before = Float(leveler.gain)
        let after = Float(leveler.step(blockDb: Leveler.rmsDb(sumOfSquares: sum, count: count),
                                       dt: Double(frames) / sampleRate, enabled: normalize))
        let boosting = eqOn || after > 1 || before > 1
        guard levelerBusy || boosting else { return }
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = max(1, Int(buffer.mNumberChannels))
            let length = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride))
            guard length > 0 else { continue }
            let step = (after - before) / Float(length)
            var gain = before
            var i = 0
            for _ in 0 ..< length {
                for c in 0 ..< stride {
                    data[i + c] = Self.soft(data[i + c] * gain)
                }
                gain += step
                i += stride
            }
        }
    }

    /// Мягкий предел выше 0.9: усиленный эквалайзером или выравнивателем звук не хрипит.
    @inline(__always)
    private static func soft(_ x: Float) -> Float {
        let a = abs(x)
        guard a > 0.9 else { return x }
        let limited = 0.9 + 0.1 * tanh((a - 0.9) / 0.1)
        return x < 0 ? -limited : limited
    }
}
