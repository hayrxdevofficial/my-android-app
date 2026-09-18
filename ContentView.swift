import SwiftUI
import UIKit

// MARK: - Модели
struct Bullet: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var fromClient: Bool = false
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

// MARK: - Загрузчик картинок
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
    @StateObject private var multiplayer = MultiplayerManager()
    @State private var screen: AppScreen = .loading
    @State private var lastScore = 0
    @State private var lastCoins = 0
    @State private var isMultiplayerGame = false
    @State private var showInviteAlert = false

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.059, blue: 0.165).ignoresSafeArea()

            switch screen {
            case .loading:
                LoadingView()
            case .menu:
                MenuView(loader: loader, store: store,
                         onStart: {
                             isMultiplayerGame = false
                             withAnimation(.easeInOut(duration: 0.25)) { screen = .game }
                         },
                         onFriends: {
                             multiplayer.startSearch()
                             withAnimation(.easeInOut(duration: 0.25)) { screen = .friends }
                         })
            case .friends:
                FriendsView(
                    multiplayer: multiplayer,
                    onBack: {
                        multiplayer.stopSearch()
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    },
                    onStartGame: {
                        isMultiplayerGame = true
                        multiplayer.stopSearch()
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .game }
                    }
                )
            case .game:
                GameView(
                    loader: loader,
                    store: store,
                    multiplayer: isMultiplayerGame ? multiplayer : nil,
                    onGameOver: { s, c in
                        lastScore = s; lastCoins = c
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .gameOver }
                    },
                    onExitToMenu: {
                        if isMultiplayerGame { multiplayer.disconnect() }
                        isMultiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            case .gameOver:
                GameOverView(
                    score: lastScore, coins: lastCoins, store: store,
                    isMultiplayer: isMultiplayerGame,
                    onRestart: {
                        if isMultiplayerGame { multiplayer.disconnect() }
                        isMultiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    },
                    onMenu: {
                        if isMultiplayerGame { multiplayer.disconnect() }
                        isMultiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            }
        }
        .onAppear {
            forceLandscape()
            loader.load()
            setupMultiplayerCallbacks()
        }
        .onChange(of: loader.loaded) { isLoaded in
            if isLoaded && screen == .loading {
                withAnimation(.easeInOut(duration: 0.4)) { screen = .menu }
            }
        }
        .onChange(of: multiplayer.incomingInvite?.peer) { peer in
            showInviteAlert = peer != nil
        }
        .alert("Хотите помочь игроку?", isPresented: $showInviteAlert) {
            Button("Да") {
                multiplayer.acceptInvite()
                isMultiplayerGame = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.3)) { screen = .game }
                }
            }
            Button("Нет", role: .cancel) {
                multiplayer.declineInvite()
            }
        } message: {
            Text("\(multiplayer.incomingInvite?.name ?? "Игрок") приглашает вас в игру")
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func setupMultiplayerCallbacks() {
        multiplayer.onMessage = { _ in
            // Обработка сообщений в GameView через подписку
        }
    }

    private func forceLandscape() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               scene.interfaceOrientation == .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                UIViewController.attemptRotationToDeviceOrientation()
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

// MARK: - Друзья
struct FriendsView: View {
    @ObservedObject var multiplayer: MultiplayerManager
    let onBack: () -> Void
    let onStartGame: () -> Void

    @State private var selectedPeer: MCPeerID?
    @State private var statusText = "Поиск игроков..."
    @State private var waiting = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()

                VStack(spacing: 16) {
                    // Шапка
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
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))

                    // Статус
                    HStack(spacing: 8) {
                        if multiplayer.discoveredPeers.isEmpty && !waiting {
                            ProgressView().tint(.purple)
                        }
                        Text(statusText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.top, 4)

                    // Список игроков
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(multiplayer.discoveredPeers, id: \.self) { peer in
                                Button {
                                    invite(peer)
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.purple.opacity(0.3)).frame(width: 44, height: 44)
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.white)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(peer.displayName)
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("Нажмите, чтобы пригласить")
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        Spacer()
                                        Image(systemName: "paperplane.fill")
                                            .foregroundColor(.blue)
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(waiting)
                            }

                            if multiplayer.discoveredPeers.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "wifi")
                                        .font(.system(size: 44))
                                        .foregroundColor(.purple.opacity(0.6))
                                    Text("Убедитесь, что друг открыл игру\nи находится в той же Wi-Fi сети")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                }
                                .padding(.top, 40)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: multiplayer.connectedPeers.count) { count in
            if count > 0 && multiplayer.isHost {
                statusText = "Подключено!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onStartGame()
                }
            }
        }
    }

    private func invite(_ peer: MCPeerID) {
        selectedPeer = peer
        waiting = true
        statusText = "Отправлено приглашение \(peer.displayName)..."
        multiplayer.invite(peer)
    }
}

// MARK: - Игра (с поддержкой multiplayer)
struct GameView: View {
    @ObservedObject var loader: ImageLoader
    @ObservedObject var store: GameStore
    var multiplayer: MultiplayerManager? = nil
    let onGameOver: (Int, Int) -> Void
    let onExitToMenu: () -> Void

    // Хост-логика
    @State private var heroY: CGFloat = 0
    @State private var heroTargetY: CGFloat = 0
    @State private var clientHeroY: CGFloat = 0
    @State private var bullets: [Bullet] = []
    @State private var enemies: [Enemy] = []
    @State private var score = 0
    @State private var earnedCoins = 0
    @State private var isGameOver = false
    @State private var spawnTimer: Double = 0
    @State private var fireTimer: Double = 0
    @State private var netTimer: Double = 0

    private let heroSizeRatio: CGFloat = 0.13
    private let enemySizeRatio: CGFloat = 0.11
    private let bulletSizeRatio: CGFloat = 0.045
    private let bulletSpeedRatio: CGFloat = 1.10
    private let baseEnemySpeed: CGFloat = 0.30
    private let baseSpawnInterval: Double = 1.4
    private let minSpawnInterval: Double = 1.0
    private let fireInterval: Double = 0.28

    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var isMultiplayer: Bool { multiplayer != nil }
    var isHost: Bool { multiplayer?.isHost ?? true }

    var enemySpeedMultiplier: CGFloat {
        1.0 + min(CGFloat(score) * 0.008, 0.5)
    }
    var currentSpawnInterval: Double {
        max(minSpawnInterval, baseSpawnInterval - Double(score) * 0.005)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let heroSize = w * heroSizeRatio
            let heroX: CGFloat = isMultiplayer ? w * 0.13 : w * 0.15
            let clientHeroX: CGFloat = w * 0.24
            let enemySize = w * enemySizeRatio
            let bulletSize = w * bulletSizeRatio

            let topInset = geo.safeAreaInsets.top
            let leadingInset = geo.safeAreaInsets.leading
            let trailingInset = geo.safeAreaInsets.trailing

            ZStack {
                StarfieldBackground()

                // Враги
                ForEach(enemies) { e in
                    if let img = loader.enemy {
                        Image(uiImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: e.size, height: e.size)
                            .position(x: e.x, y: e.y)
                            .shadow(color: .red.opacity(0.5), radius: 8)
                    }
                }

                // Пули
                ForEach(bullets) { b in
                    if let img = loader.bullet {
                        Image(uiImage: img)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: bulletSize * 1.8, height: bulletSize)
                            .rotationEffect(.degrees(90))
                            .position(x: b.x, y: b.y)
                            .shadow(color: b.fromClient ? .cyan : .yellow, radius: 8)
                    } else {
                        Circle()
                            .fill(b.fromClient ? Color.cyan : Color.yellow)
                            .frame(width: bulletSize, height: bulletSize)
                            .position(x: b.x, y: b.y)
                    }
                }

                // Второй герой (в multiplayer)
                if isMultiplayer, let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .hueRotation(.degrees(isHost ? 0 : 60)) // цветовой сдвиг у второго игрока
                        .position(x: clientHeroX, y: clientHeroY)
                        .shadow(color: .cyan.opacity(0.8), radius: 15)
                }

                // Свой герой
                if let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .rotationEffect(.degrees(sin(Double(score)) * 5))
                        .position(x: heroX, y: heroY)
                        .shadow(color: .purple.opacity(0.8), radius: 15)
                }

                // HUD
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

                        if isMultiplayer {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill").font(.system(size: 12))
                                Text("Co-op").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.cyan.opacity(0.6), lineWidth: 1.5))
                            .cornerRadius(18)
                        }

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
                    .padding(.leading, max(16, leadingInset + 8))
                    .padding(.trailing, max(16, trailingInset + 8))
                    .padding(.top, max(8, topInset + 4))
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        heroTargetY = value.location.y
                        if isMultiplayer && !isHost {
                            // Клиент шлёт свою позицию хосту
                            multiplayer?.send(.clientHero(y: heroTargetY))
                        }
                    }
            )
            .onAppear {
                heroY = h * 0.5
                heroTargetY = h * 0.5
                clientHeroY = h * 0.5
                if isMultiplayer {
                    setupNetworking()
                }
            }
            .onReceive(timer) { _ in
                if !isGameOver {
                    tick(w: w, h: h, heroSize: heroSize, heroX: heroX,
                         enemySize: enemySize, bulletSize: bulletSize,
                         clientHeroX: clientHeroX)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Сетевые колбэки
    func setupNetworking() {
        guard let mp = multiplayer else { return }
        mp.onMessage = { msg in
            switch msg {
            case .clientHero(let y):
                if isHost { clientHeroY = y }
            case .gameState(let state):
                if !isHost {
                    // Клиент применяет состояние от хоста
                    enemies = state.enemies.enumerated().map { (i, e) in
                        Enemy(id: UUID(), x: e.x, y: e.y, size: e.size)
                    }
                    bullets = state.bullets.map { b in
                        Bullet(x: b.x, y: b.y, fromClient: b.fromClient)
                    }
                    clientHeroY = state.hostHeroY
                    score = state.score
                    earnedCoins = state.coins
                    if state.isGameOver {
                        triggerGameOver()
                    }
                }
            case .accept:
                // Хост — клиент принял приглашение, но мы уже через connectedPeers триггерим старт
                break
            default: break
            }
        }
        mp.onDisconnect = {
            if !isGameOver { triggerGameOver() }
        }
    }

    // MARK: Логика
    func tick(w: CGFloat, h: CGFloat, heroSize: CGFloat, heroX: CGFloat,
              enemySize: CGFloat, bulletSize: CGFloat, clientHeroX: CGFloat) {

        // Плавное движение
        heroY += (heroTargetY - heroY) * 0.2
        let minY = heroSize / 2 + 10
        let maxY = h - heroSize / 2 - 10
        if heroY < minY { heroY = minY }
        if heroY > maxY { heroY = maxY }

        if isMultiplayer && isHost {
            clientHeroY += (clientHeroY - clientHeroY) * 0.2 // клиент уже прислал точное Y
        }

        // Логику тикает только хост (или одиночная игра)
        guard !isMultiplayer || isHost else { return }

        // Автострельба своего героя
        fireTimer += 1.0 / 60.0
        if fireTimer >= fireInterval {
            fireTimer = 0
            bullets.append(Bullet(x: heroX + heroSize * 0.4, y: heroY, fromClient: false))
            // В multiplayer — второй герой тоже стреляет
            if isMultiplayer {
                bullets.append(Bullet(x: clientHeroX + heroSize * 0.4, y: clientHeroY, fromClient: true))
            }
        }

        // Пули
        let bSpeed = w * bulletSpeedRatio
        for i in bullets.indices { bullets[i].x += bSpeed / 60.0 }
        bullets.removeAll { $0.x > w + 30 }

        // Враги
        let eSpeed = w * baseEnemySpeed * enemySpeedMultiplier
        for i in enemies.indices { enemies[i].x -= eSpeed / 60.0 }
        enemies.removeAll { $0.x < -enemySize }

        // Спавн
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

        // Пуля → враг
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

        // Свой герой → враг
        for e in enemies {
            let dx = abs(heroX - e.x)
            let dy2 = abs(heroY - e.y)
            if dx < (heroSize + e.size) / 2 - 10 && dy2 < (heroSize + e.size) / 2 - 10 {
                triggerGameOver(); return
            }
        }
        // Второй герой → враг (в multiplayer)
        if isMultiplayer {
            for e in enemies {
                let dx = abs(clientHeroX - e.x)
                let dy2 = abs(clientHeroY - e.y)
                if dx < (heroSize + e.size) / 2 - 10 && dy2 < (heroSize + e.size) / 2 - 10 {
                    triggerGameOver(); return
                }
            }
        }

        // Отправка состояния клиенту (20 fps)
        if isMultiplayer && isHost {
            netTimer += 1.0 / 60.0
            if netTimer >= 0.05 {
                netTimer = 0
                let state = NetGameState(
                    hostHeroY: heroY,
                    clientHeroY: clientHeroY,
                    enemies: enemies.map { NetEnemy(x: $0.x, y: $0.y, size: $0.size) },
                    bullets: bullets.map { NetBullet(x: $0.x, y: $0.y, fromClient: $0.fromClient) },
                    score: score,
                    coins: earnedCoins,
                    isGameOver: false
                )
                multiplayer?.send(.gameState(state: state))
            }
        }
    }

    func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        store.commit(score: score, coins: earnedCoins)
        if isMultiplayer && isHost {
            let state = NetGameState(hostHeroY: heroY, clientHeroY: clientHeroY,
                                     enemies: [], bullets: [], score: score,
                                     coins: earnedCoins, isGameOver: true)
            multiplayer?.send(.gameState(state: state), reliable: true)
        }
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
    var isMultiplayer: Bool = false
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

                    if isMultiplayer {
                        Text("Co-op партия")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
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
