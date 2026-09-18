import SwiftUI

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
    @Published var coins: Int {
        didSet { UserDefaults.standard.set(coins, forKey: "cosmic_coins") }
    }
    @Published var bestScore: Int {
        didSet { UserDefaults.standard.set(bestScore, forKey: "cosmic_best") }
    }
    init() {
        coins = UserDefaults.standard.integer(forKey: "cosmic_coins")
        bestScore = UserDefaults.standard.integer(forKey: "cosmic_best")
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

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            DispatchQueue.main.async { self.loaded = true }
        }
    }

    private func loadOne(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let img = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }
}

// MARK: - Экраны
enum AppScreen {
    case loading
    case menu
    case game
    case gameOver
}

// MARK: - Корень
struct ContentView: View {
    @StateObject private var store = GameStore()
    @StateObject private var loader = ImageLoader()
    @State private var screen: AppScreen = .loading
    @State private var lastScore = 0
    @State private var lastCoins = 0

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.059, blue: 0.165).ignoresSafeArea()

            switch screen {
            case .loading:
                LoadingView()

            case .menu:
                MenuView(loader: loader, store: store) {
                    withAnimation(.easeInOut(duration: 0.3)) { screen = .game }
                }

            case .game:
                GameView(
                    loader: loader,
                    store: store,
                    onGameOver: { score, coins in
                        lastScore = score
                        lastCoins = coins
                        withAnimation(.easeInOut(duration: 0.3)) { screen = .gameOver }
                    },
                    onExitToMenu: {
                        withAnimation(.easeInOut(duration: 0.3)) { screen = .menu }
                    }
                )

            case .gameOver:
                GameOverView(
                    score: lastScore,
                    coins: lastCoins,
                    store: store,
                    onRestart: { withAnimation(.easeInOut(duration: 0.3)) { screen = .game } },
                    onMenu:    { withAnimation(.easeInOut(duration: 0.3)) { screen = .menu } }
                )
            }
        }
        .onAppear { loader.load() }
        .onChange(of: loader.loaded) { isLoaded in
            if isLoaded && screen == .loading {
                withAnimation(.easeInOut(duration: 0.4)) { screen = .menu }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

// MARK: - Загрузка
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.purple)
            Text("COSMIC SUNGAROV")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.purple)
                .tracking(3)
        }
    }
}

// MARK: - Меню
struct MenuView: View {
    @ObservedObject var loader: ImageLoader
    @ObservedObject var store: GameStore
    let onStart: () -> Void

    @State private var float = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()

                HStack(spacing: 0) {
                    // Левая половина — герой
                    ZStack {
                        if let hero = loader.hero {
                            Image(uiImage: hero)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.height * 0.65)
                                .rotationEffect(.degrees(float ? 5 : -5))
                                .offset(y: float ? -10 : 10)
                                .shadow(color: .purple.opacity(0.7), radius: 20)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: float)
                        }
                    }
                    .frame(width: geo.size.width * 0.45)

                    // Правая половина — название и кнопка
                    VStack(spacing: 16) {
                        Spacer()

                        Text("COSMIC")
                            .font(.system(size: geo.size.height * 0.16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .purple, radius: 20)
                            .tracking(4)

                        Text("SUNGAROV")
                            .font(.system(size: geo.size.height * 0.13, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.04), radius: 20)
                            .tracking(2)

                        Spacer()

                        Button(action: onStart) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("ИГРАТЬ")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(width: 260, height: 60)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                             Color(red: 0.29, green: 0.23, blue: 0.71)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: .purple.opacity(0.6), radius: 20)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 6) {
                            Image(systemName: "star.circle.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            Text("Рекорд: \(store.bestScore)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.top, 8)
                        .padding(.bottom, geo.size.height * 0.08)
                    }
                    .frame(width: geo.size.width * 0.55)
                }
            }
        }
        .onAppear { float = true }
    }
}

// MARK: - Игра
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

    // Размеры (относительные)
    private let heroSizeRatio: CGFloat = 0.13
    private let enemySizeRatio: CGFloat = 0.11
    private let bulletSizeRatio: CGFloat = 0.045
    private let bulletSpeedRatio: CGFloat = 1.10
    private let enemySpeedRatio: CGFloat = 0.32
    private let spawnInterval: Double = 1.3
    private let fireInterval: Double = 0.28

    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

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

                // Враги
                ForEach(enemies) { e in
                    if let img = loader.enemy {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: e.size, height: e.size)
                            .position(x: e.x, y: e.y)
                    }
                }

                // Пули
                ForEach(bullets) { b in
                    if let img = loader.bullet {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: bulletSize * 1.8, height: bulletSize)
                            .rotationEffect(.degrees(90))
                            .position(x: b.x, y: b.y)
                            .shadow(color: .yellow, radius: 6)
                    } else {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: bulletSize, height: bulletSize)
                            .position(x: b.x, y: b.y)
                    }
                }

                // Герой
                if let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .rotationEffect(.degrees(sin(Double(score)) * 5))
                        .position(x: heroX, y: heroY)
                        .shadow(color: .purple.opacity(0.6), radius: 10)
                }

                // HUD
                VStack {
                    HStack {
                        Text("\(score)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .purple, radius: 10)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(20)

                        Spacer()

                        HStack(spacing: 8) {
                            Image(systemName: "star.circle.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            Text("\(earnedCoins)")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(20)

                        Button(action: onExitToMenu) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(12, geo.safeAreaInsets.top))
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        heroTargetY = value.location.y
                    }
            )
            .onAppear {
                heroY = h * 0.5
                heroTargetY = h * 0.5
            }
            .onReceive(timer) { _ in
                if !isGameOver {
                    tick(w: w, h: h,
                         heroSize: heroSize, heroX: heroX,
                         enemySize: enemySize, bulletSize: bulletSize)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Логика
    func tick(w: CGFloat, h: CGFloat,
              heroSize: CGFloat, heroX: CGFloat,
              enemySize: CGFloat, bulletSize: CGFloat) {

        // Плавное движение героя к пальцу
        let dy = heroTargetY - heroY
        heroY += dy * 0.2
        // Ограничения
        let minY = heroSize / 2 + 10
        let maxY = h - heroSize / 2 - 10
        if heroY < minY { heroY = minY }
        if heroY > maxY { heroY = maxY }

        // Автострельба
        fireTimer += 1.0 / 60.0
        if fireTimer >= fireInterval {
            fireTimer = 0
            bullets.append(Bullet(x: heroX + heroSize * 0.4, y: heroY))
        }

        // Движение пуль
        let bSpeed = w * bulletSpeedRatio
        for i in bullets.indices {
            bullets[i].x += bSpeed / 60.0
        }
        bullets.removeAll { $0.x > w + 30 }

        // Движение врагов
        let eSpeed = w * enemySpeedRatio
        for i in enemies.indices {
            enemies[i].x -= eSpeed / 60.0
        }
        enemies.removeAll { $0.x < -enemySize }

        // Спавн врагов
        spawnTimer += 1.0 / 60.0
        if spawnTimer >= spawnInterval {
            spawnTimer = 0
            let y = CGFloat.random(in: enemySize/2...(h - enemySize/2))
            enemies.append(Enemy(x: w + enemySize, y: y, size: enemySize))
        }

        // Столкновения: пуля → враг
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

        // Столкновение героя с врагом
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
        if score > store.bestScore { store.bestScore = score }
        store.coins += earnedCoins
        onGameOver(score, earnedCoins)
    }
}

// MARK: - Game Over
struct GameOverView: View {
    let score: Int
    let coins: Int
    @ObservedObject var store: GameStore
    let onRestart: () -> Void
    let onMenu: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()

                VStack(spacing: 14) {
                    Text("ИГРА ОКОНЧЕНА")
                        .font(.system(size: geo.size.height * 0.10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .purple, radius: 20)
                        .tracking(2)

                    Text("Счёт: \(score)")
                        .font(.system(size: geo.size.height * 0.06, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))

                    HStack(spacing: 6) {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                        Text("+\(coins) монет")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                    }

                    if score >= store.bestScore && score > 0 {
                        Text("🏆 НОВЫЙ РЕКОРД!")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                    } else {
                        Text("Рекорд: \(store.bestScore)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Button(action: onRestart) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Играть снова")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 240, height: 52)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                         Color(red: 0.29, green: 0.23, blue: 0.71)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: .purple.opacity(0.6), radius: 16)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    Button(action: onMenu) {
                        Text("В меню")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                            .underline()
                    }
                }
                .padding(30)
                .background(Color.black.opacity(0.5))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.purple.opacity(0.6), lineWidth: 2)
                )
                .padding(40)
            }
        }
    }
}

// MARK: - Звёздный фон
struct StarfieldBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.10, green: 0.06, blue: 0.25),
                        Color(red: 0.043, green: 0.059, blue: 0.165),
                        Color(red: 0.02, green: 0.03, blue: 0.06)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height)
                )
                .ignoresSafeArea()

                ForEach(0..<60, id: \.self) { i in
                    let x = CGFloat((i * 137) % Int(geo.size.width))
                    let y = CGFloat((i * 73) % Int(geo.size.height))
                    let size: CGFloat = CGFloat(i % 3) * 0.7 + 1
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: size, height: size)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
