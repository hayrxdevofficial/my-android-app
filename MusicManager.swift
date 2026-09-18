import Foundation
import AVFoundation

class MusicManager: ObservableObject {
    private var player: AVAudioPlayer?
    private var currentTrack: String? = nil

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // Ничего качать не надо — файлы внутри бандла
    func preload() {
        let menu = Bundle.main.url(forResource: "menu_music", withExtension: "mp3")
        let game = Bundle.main.url(forResource: "game_music", withExtension: "mp3")
        print("🎵 menu_music в бандле: \(menu != nil)")
        print("🎵 game_music в бандле: \(game != nil)")
    }

    func playMenu() { play(filename: "menu_music", name: "menu") }
    func playGame() { play(filename: "game_music", name: "game") }

    func stop() {
        player?.stop()
        player = nil
        currentTrack = nil
    }

    private func play(filename: String, name: String) {
        if currentTrack == name, let p = player, p.isPlaying { return }

        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
            print("❌ Не найден в бандле: \(filename).mp3")
            return
        }

        player?.stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.45
            player?.prepareToPlay()
            player?.play()
            currentTrack = name
            print("🎵 Играет: \(name)")
        } catch {
            print("Play error \(name): \(error)")
        }
    }
}
