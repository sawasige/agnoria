import AVFoundation

// 効果音 correct.caf / wrong.caf / fanfare.caf を作る（SPEC §6 [v1.5]）。
// macOS 内蔵の GM 音源（gs_instruments.dls）を AVAudioUnitSampler で演奏し、ホールのリバーブをかけて
// オフラインで WAV に書き出す。その後、ピーク -6 dBFS に正規化して末尾の無音を詰め、afconvert で CAF 化する。
// 使い方（出力先のディレクトリを渡す。fanfare.wav / correct.wav / wrong.wav ができる）:
//   swiftc -O -o /tmp/render tools/sounds/render-sounds.swift && /tmp/render /tmp/sounds
//   for n in fanfare correct wrong; do python3 tools/sounds/normalize.py /tmp/sounds/$n.wav /tmp/sounds/$n-16.wav \
//     && afconvert -f caff -d LEI16 /tmp/sounds/$n-16.wav Agnoria/Resources/Sounds/$n.caf; done
let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
struct Note { let t: Double; let pitch: UInt8; let vel: UInt8; let dur: Double }
struct Track { let program: UInt8; let notes: [Note]; let volume: Float }

func render(name: String, tracks: [Track], seconds: Double, reverbMix: Float = 35) throws {
    let engine = AVAudioEngine()
    let reverb = AVAudioUnitReverb(); reverb.loadFactoryPreset(.largeHall2); reverb.wetDryMix = reverbMix
    engine.attach(reverb)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    engine.connect(reverb, to: engine.mainMixerNode, format: format)
    var samplers: [AVAudioUnitSampler] = []
    for track in tracks {
        let s = AVAudioUnitSampler(); engine.attach(s)
        engine.connect(s, to: reverb, format: format)
        try s.loadSoundBankInstrument(at: bank, program: track.program, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        s.masterGain = 0; s.volume = track.volume
        samplers.append(s)
    }
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let out = URL(fileURLWithPath: "\(dir)/\(name).wav")
    let file = try AVAudioFile(forWriting: out, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
    let total = AVAudioFramePosition(seconds * 44100)
    // イベントを時刻順に
    var events: [(Double, () -> Void)] = []
    for (i, track) in tracks.enumerated() {
        for n in track.notes {
            events.append((n.t, { samplers[i].startNote(n.pitch, withVelocity: n.vel, onChannel: 0) }))
            events.append((n.t + n.dur, { samplers[i].stopNote(n.pitch, onChannel: 0) }))
        }
    }
    events.sort { $0.0 < $1.0 }
    var next = 0
    while engine.manualRenderingSampleTime < total {
        let now = Double(engine.manualRenderingSampleTime) / 44100
        while next < events.count, events[next].0 <= now { events[next].1(); next += 1 }
        let frames = min(buffer.frameCapacity, AVAudioFrameCount(total - engine.manualRenderingSampleTime), 512)
        let status = try engine.renderOffline(frames, to: buffer)
        if status == .success { try file.write(from: buffer) }
    }
    engine.stop()
    print("rendered \(name)")
}

// GM プログラム番号（0 始まり）: 46 ハープ, 9 グロッケン, 8 チェレスタ, 10 オルゴール, 11 ビブラフォン, 88 Pad(new age), 48 ストリングス, 56 トランペット
let C5: UInt8 = 72, E5: UInt8 = 76, G5: UInt8 = 79, C6: UInt8 = 84, E6: UInt8 = 88, G6: UInt8 = 91, C7: UInt8 = 96
let A4: UInt8 = 69, D5: UInt8 = 74, A5: UInt8 = 81, B5: UInt8 = 83, D6: UInt8 = 86

// 採用: ハープの上昇グリッサンド + グロッケンの和音（聞き比べた 3 案のうち案 1。他はチェレスタ + 弦、ビブラフォン + パッド）
let harp = Track(program: 46, notes: [C5, E5, G5, C6, E6, G6, C7].enumerated().map { Note(t: Double($0.offset) * 0.07, pitch: $0.element, vel: 92, dur: 0.6) }, volume: 0.9)
let glock = Track(program: 9, notes: [Note(t: 0.5, pitch: C6, vel: 100, dur: 1.5), Note(t: 0.5, pitch: E6, vel: 96, dur: 1.5), Note(t: 0.5, pitch: G6, vel: 92, dur: 1.5), Note(t: 0.62, pitch: C7, vel: 100, dur: 1.5)], volume: 0.8)
try render(name: "fanfare", tracks: [harp, glock], seconds: 2.8)

// 正解: グロッケンの E6 → C7（聞き比べた 3 案のうち 1。他はチェレスタの和音、マリンバ）
try render(name: "correct", tracks: [Track(program: 9, notes: [Note(t: 0, pitch: E6, vel: 100, dur: 0.25), Note(t: 0.11, pitch: C7, vel: 108, dur: 0.6)], volume: 0.9)], seconds: 1.2, reverbMix: 25)
// 不正解: マリンバの低い C3 → G2（他はピチカート、ピアノ低音の不協和音）
let C3: UInt8 = 48, G2: UInt8 = 43
try render(name: "wrong", tracks: [Track(program: 12, notes: [Note(t: 0, pitch: C3, vel: 100, dur: 0.25), Note(t: 0.13, pitch: G2, vel: 96, dur: 0.4)], volume: 0.9)], seconds: 1.0, reverbMix: 10)
