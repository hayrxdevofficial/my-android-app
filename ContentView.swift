import SwiftUI
import UIKit

// MARK: - Модели
struct Bullet: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
}

struct Enemy: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
}

// MARK: - Хранилище
final class GameStore: ObservableObject {
    @Published var coins: Int { didSet { UserDefaults.standard.set(coins, forKey: "cosmic_coins") } }
    @Published var bestScore: Int { didSet { UserDefaults.standard.set(bestScore, forKey: "cosmic_best") } }
    init() {
        coins = UserDefaults.standard.integer(forKey: "cosmic_coins")
        bestScore = UserDefaults.standard.integer(forKey: "cosmic_best")
    }
    func commit(score: Int, coins earned: Int) {
        if score > bestScore { bestScore = score }
        coins += earned
    }
}

// MARK: - Загрузчик
final class ImageLoader: ObservableObject {
    @Published var hero: UIImage?
    @Published var enemy: UIImage?
    @Published var bullet: UIImage?
    @Published var loaded = false
    private var remaining = 3

    func load() {
        loadOne("https://raw.githubusercontent.com/hayrxdevofficial/my-android-app/main/sungarov.png") { self.hero = $0; self.tick() }
        loadOne("https://raw.githubusercontent.com/hayrxdevofficial/my-android-app/main/bad.png")      { self.enemy = $0; self.tick() }
        loadOne("https://raw.githubusercontent.com/hayrxdevofficial/my-android-app/main/pula.png")     { self.bullet = $0; self.tick() }
    }
    private func tick() { remaining -= 1; if remaining <= 0 { loaded = true } }
    private func loadOne(_ s: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: s) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let img = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }
}

// MARK: - Экраны
enum AppScreen { case loading, menu, friends, game, gameOver }

// MARK: - Корень
struct ContentView: View {
    @StateObject private var store = GameStore()
    @StateObject private var loader = ImageLoader()
    @StateObject private var network = NetworkManager()
    @State private var screen: AppScreen = .loading
    @State private var lastScore = 0
    @State private var lastCoins = 0
    @State private var showInviteAlert = false

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.059, blue: 0.165).ignoresSafeArea()

            switch screen {
            case .loading:
                LoadingView()
            case .menu:
                MenuView(
                    loader: loader,
                    store: store,
                    onStart: { withAnimation(.easeInOut(duration: 0.25)) { screen = .game } },
                    onFriends: { withAnimation(.easeInOut(duration: 0.25)) { screen = .friends } }
                )
            case .friends:
                FriendsView(
                    network: network,
                    onBack: {
                        network.disconnect()
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            case .game:
                GameView(
                    loader: loader,
                    store: store,
                    onGameOver: { s, c in
                        lastScore = s; lastCoins = c
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .gameOver }
                    },
                    onExitToMenu: {
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            case .gameOver:
                GameOverView(
                    score: lastScore, coins: lastCoins, store: store,
                    onRestart: { withAnimation(.easeInOut(duration: 0.25)) { screen = .menu } },
                    onMenu:    { withAnimation(.easeInOut(duration: 0.25)) { screen = .menu } }
                )
            }
        }
        .onAppear {
            forceLandscape()
            loader.load()
        }
        .onChange(of: loader.loaded) { isLoaded in
            if isLoaded && screen == .loading {
                withAnimation(.easeInOut(duration: 0.4)) { screen = .menu }
            }
        }
        .onChange(of: network.incomingInvite) { newValue in
            if newValue != nil { showInviteAlert = true }
        }
        .alert("Хотите помочь игроку?", isPresented: $showInviteAlert) {
            Button("Да") {
                if let peer = network.incomingInvite {
                    network.respondToInvite(from: peer.id, accepted: true)
                    network.incomingInvite = nil
                    withAnimation(.easeInOut(duration: 0.3)) { screen = .game }
                }
            }
            Button("Нет", role: .cancel) {
                if let peer = network.incomingInvite {
                    network.respondToInvite(from: peer.id, accepted: false)
                }
                network.incomingInvite = nil
            }
        } message: {
            let inviteName: String = network.incomingInvite?.name ?? "Игрок"
            Text(inviteName + " приглашает вас в игру")
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func forceLandscape() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               scene.interfaceOrientation == .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        }
    }
}

// MARK: - Загрузка
struct LoadingView: View {
    @State private var spin = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()
                VStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(Color.purple.opacity(0.2), lineWidth: 4).frame(width: 60, height: 60)
                        Circle().trim(from: 0, to: 0.25)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    }
                    Text("COSMIC SUNGAROV")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.purple).tracking(4)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear { spin = true }
    }
}

// MARK: - Меню
struct MenuView: View {
    @ObservedObject var loader: ImageLoader
    @ObservedObject var store: GameStore
    let onStart: () -> Void
    let onFriends: () -> Void
    @State private var float = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()
                HStack(spacing: 0) {
                    ZStack {
                        if let hero = loader.hero {
                            Image(uiImage: hero)
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.height * 0.55)
                                .rotationEffect(.degrees(float ? 5 : -5))
                                .offset(y: float ? -10 : 10)
                                .shadow(color: .purple.opacity(0.8), radius: 25)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: float)
                        }
                    }
                    .frame(width: geo.size.width * 0.45)

                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Text("COSMIC")
                            .font(.system(size: geo.size.height * 0.13, weight: .heavy, design: .rounded))
                            .foregroundColor(.white).shadow(color: .purple, radius: 25).tracking(5)
                        Text("SUNGAROV")
                            .font(.system(size: geo.size.height * 0.10, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.04), radius: 25).tracking(3)
                        Spacer(minLength: 0)

                        HStack(spacing: 12) {
                            Button(action: onStart) {
                                HStack(spacing: 10) {
                                    Image(systemName: "play.fill")
                                    Text("ИГРАТЬ").font(.system(size: 20, weight: .heavy, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(width: geo.size.width * 0.28, height: 54)
                                .background(LinearGradient(
                                    colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                             Color(red: 0.29, green: 0.23, blue: 0.71)],
                                    startPoint: .top, endPoint: .bottom))
                                .cornerRadius(18)
                                .shadow(color: .purple.opacity(0.7), radius: 20)
                            }
                            .buttonStyle(.plain)

                            Button(action: onFriends) {
                                VStack(spacing: 2) {
                                    Image(systemName: "person.2.fill").font(.system(size: 20))
                                    Text("Друзья").font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(width: 70, height: 54)
                                .background(LinearGradient(
                                    colors: [Color(red: 0.20, green: 0.65, blue: 0.98),
                                             Color(red: 0.10, green: 0.45, blue: 0.85)],
                                    startPoint: .top, endPoint: .bottom))
                                .cornerRadius(18)
                                .shadow(color: .blue.opacity(0.6), radius: 15)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Image(systemName: "star.circle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                Text("\(store.bestScore)")
                                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                Text("\(store.coins)")
                                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .padding(.top, 6)
                        Spacer(minLength: 0).frame(height: geo.size.height * 0.06)
                    }
                    .frame(width: geo.size.width * 0.55)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { float = true }
    }
}

// MARK: - Друзья (через WebSocket)
struct FriendsView: View {
    @ObservedObject var network: NetworkManager
    let onBack: () -> Void

    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()
                VStack(spacing: 16) {
                    header(topInset: geo.safeAreaInsets.top)
                    statusBar
                    playersList
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            network.connect()
            timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                if network.isConnected { network.refreshPlayerList() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func header(topInset: CGFloat) -> some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            Spacer()
            Text("ДРУЗЬЯ")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white).tracking(3)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, max(8, topInset + 4))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(network.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(network.isConnected ? "Подключено к серверу" : (network.connectionError ?? "Подключение..."))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            if network.isConnected {
                Button("Обновить") { network.refreshPlayerList() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 24)
    }

    private var playersList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(network.onlinePlayers) { player in
                    playerRow(player: player)
                }
                if network.onlinePlayers.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func playerRow(player: PlayerInfo) -> some View {
        Button(action: { network.sendInvite(to: player.id) }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.3)).frame(width: 44, height: 44)
                    Image(systemName: "person.fill").foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("ID: \(player.id)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "paperplane.fill").foregroundColor(.blue)
            }
            .padding(12)
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.purple.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 44))
                .foregroundColor(.purple.opacity(0.6))
            Text(network.isConnected
                 ? "Пока никого нет онлайн.\nПопроси друга открыть игру."
                 : "Подключение к серверу...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 40)
    }
}

// MARK: - Игра (одиночная)
struct GameView: View {
    @ObservedObject var loader: ImageLoader
    @ObservedObject var store: GameStore
    let onGameOver: (Int, Int) -> Void
    let onExitToMenu: () -> Void

    @State private var heroY: CGFloat = 0
    @State private var heroTargetY: CGFloat = 0
    @State private var bullets: [Bullet] = []
    @State private var enemies: [Enemy] = []
    @State private var score = 0
    @State private var earnedCoins = 0
    @State private var isGameOver = false
    @State private var spawnTimer: Double = 0
    @State private var fireTimer: Double = 0

    private let heroSizeRatio: CGFloat = 0.13
    private let enemySizeRatio: CGFloat = 0.11
    private let bulletSizeRatio: CGFloat = 0.045
    private let bulletSpeedRatio: CGFloat = 1.10
    private let baseEnemySpeed: CGFloat = 0.30
    private let baseSpawnInterval: Double = 1.4
    private let minSpawnInterval: Double = 1.0
    private let fireInterval: Double = 0.28

    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var enemySpeedMultiplier: CGFloat { 1.0 + min(CGFloat(score) * 0.008, 0.5) }
    var currentSpawnInterval: Double { max(minSpawnInterval, baseSpawnInterval - Double(score) * 0.005) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let heroSize = w * heroSizeRatio
            let heroX = w * 0.15
            let enemySize = w * enemySizeRatio
            let bulletSize = w * bulletSizeRatio

            ZStack {
                StarfieldBackground()

                ForEach(enemies) { e in
                    if let img = loader.enemy {
                        Image(uiImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: e.size, height: e.size)
                            .position(x: e.x, y: e.y)
                            .shadow(color: .red.opacity(0.5), radius: 8)
                    }
                }

                ForEach(bullets) { b in
                    if let img = loader.bullet {
                        Image(uiImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: bulletSize * 1.8, height: bulletSize)
                            .rotationEffect(.degrees(90))
                            .position(x: b.x, y: b.y)
                            .shadow(color: .yellow, radius: 8)
                    } else {
                        Circle().fill(Color.yellow)
                            .frame(width: bulletSize, height: bulletSize)
                            .position(x: b.x, y: b.y)
                    }
                }

                if let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .rotationEffect(.degrees(sin(Double(score)) * 5))
                        .position(x: heroX, y: heroY)
                        .shadow(color: .purple.opacity(0.8), radius: 15)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("\(score)")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.purple.opacity(0.6), lineWidth: 1.5))
                            .cornerRadius(18)

                        HStack(spacing: 6) {
                            Image(systemName: "star.circle.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            Text("\(earnedCoins)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.purple.opacity(0.6), lineWidth: 1.5))
                        .cornerRadius(18)

                        Spacer()

                        Button(action: exitGame) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.purple.opacity(0.6), lineWidth: 1.5))
                        }
                    }
                    .padding(.leading, max(16, geo.safeAreaInsets.leading + 8))
                    .padding(.trailing, max(16, geo.safeAreaInsets.trailing + 8))
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in heroTargetY = value.location.y }
            )
            .onAppear {
                heroY = h * 0.5
                heroTargetY = h * 0.5
            }
            .onReceive(timer) { _ in
                if !isGameOver {
                    tick(w: w, h: h, heroSize: heroSize, heroX: heroX,
                         enemySize: enemySize, bulletSize: bulletSize)
                }
            }
        }
        .ignoresSafeArea()
    }

    func tick(w: CGFloat, h: CGFloat, heroSize: CGFloat, heroX: CGFloat,
              enemySize: CGFloat, bulletSize: CGFloat) {

        heroY += (heroTargetY - heroY) * 0.2
        let minY = heroSize / 2 + 10
        let maxY = h - heroSize / 2 - 10
        if heroY < minY { heroY = minY }
        if heroY > maxY { heroY = maxY }

        fireTimer += 1.0 / 60.0
        if fireTimer >= fireInterval {
            fireTimer = 0
            bullets.append(Bullet(x: heroX + heroSize * 0.4, y: heroY))
        }

        let bSpeed = w * bulletSpeedRatio
        for i in bullets.indices { bullets[i].x += bSpeed / 60.0 }
        bullets.removeAll { $0.x > w + 30 }

        let eSpeed = w * baseEnemySpeed * enemySpeedMultiplier
        for i in enemies.indices { enemies[i].x -= eSpeed / 60.0 }
        enemies.removeAll { $0.x < -enemySize }

        spawnTimer += 1.0 / 60.0
        if spawnTimer >= currentSpawnInterval {
            spawnTimer = 0
            let y = CGFloat.random(in: enemySize/2...(h - enemySize/2))
            enemies.append(Enemy(x: w + enemySize, y: y, size: enemySize))
            if score >= 40 && Bool.random() {
                let y2 = CGFloat.random(in: enemySize/2...(h - enemySize/2))
                enemies.append(Enemy(x: w + enemySize * 2, y: y2, size: enemySize))
            }
        }

        var bulletsToRemove = Set<UUID>()
        var enemiesToRemove = Set<UUID>()
        for b in bullets {
            for e in enemies {
                if enemiesToRemove.contains(e.id) { continue }
                let dx = abs(b.x - e.x)
                let dy2 = abs(b.y - e.y)
                if dx < (bulletSize + e.size) / 2 && dy2 < (bulletSize + e.size) / 2 {
                    bulletsToRemove.insert(b.id)
                    enemiesToRemove.insert(e.id)
                    score += 1
                    earnedCoins += 1
                }
            }
        }
        bullets.removeAll { bulletsToRemove.contains($0.id) }
        enemies.removeAll { enemiesToRemove.contains($0.id) }

        for e in enemies {
            let dx = abs(heroX - e.x)
            let dy2 = abs(heroY - e.y)
            if dx < (heroSize + e.size) / 2 - 10 && dy2 < (heroSize + e.size) / 2 - 10 {
                triggerGameOver()
                return
            }
        }
    }

    func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        store.commit(score: score, coins: earnedCoins)
        onGameOver(score, earnedCoins)
    }

    func exitGame() {
        if !isGameOver && (score > 0 || earnedCoins > 0) {
            store.commit(score: score, coins: earnedCoins)
        }
        onExitToMenu()
    }
}

// MARK: - Game Over
struct GameOverView: View {
    let score: Int
    let coins: Int
    @ObservedObject var store: GameStore
    let onRestart: () -> Void
    let onMenu: () -> Void

    var isRecord: Bool { score >= store.bestScore && score > 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()
                VStack(spacing: 8) {
                    Text("ИГРА ОКОНЧЕНА")
                        .font(.system(size: geo.size.height * 0.08, weight: .heavy, design: .rounded))
                        .foregroundColor(.white).shadow(color: .purple, radius: 20).tracking(3)

                    Text("\(score)")
                        .font(.system(size: geo.size.height * 0.16, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                        .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.04), radius: 20)

                    HStack(spacing: 6) {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                        Text("+\(coins) монет")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                    }

                    if isRecord {
                        Text("🏆 НОВЫЙ РЕКОРД!")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                    } else {
                        Text("Рекорд: \(store.bestScore)")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    }

                    Button(action: onRestart) {
                        HStack(spacing: 8) {
                            Image(systemName: "house.fill")
                            Text("В МЕНЮ").font(.system(size: 16, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(width: 220, height: 48)
                        .background(LinearGradient(
                            colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                     Color(red: 0.29, green: 0.23, blue: 0.71)],
                            startPoint: .top, endPoint: .bottom))
                        .cornerRadius(14)
                        .shadow(color: .purple.opacity(0.7), radius: 20)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(24)
                .background(Color.black.opacity(0.6))
                .cornerRadius(22)
                .overlay(RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.purple.opacity(0.7), lineWidth: 2))
                .padding(30)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Фон
struct StarfieldBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.10, green: 0.06, blue: 0.25),
                             Color(red: 0.043, green: 0.059, blue: 0.165),
                             Color(red: 0.02, green: 0.03, blue: 0.06)],
                    center: .topLeading, startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height))
                ForEach(0..<60, id: \.self) { i in
                    let x = CGFloat((i * 137) % Int(geo.size.width))
                    let y = CGFloat((i * 73) % Int(geo.size.height))
                    let size: CGFloat = CGFloat(i % 3) * 0.7 + 1
                    Circle().fill(Color.white.opacity(0.6))
                        .frame(width: size, height: size)
                        .position(x: x, y: y)
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
