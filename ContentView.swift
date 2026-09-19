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

    func load() {
        hero = loadImage("sungarov")
        enemy = loadImage("bad")
        bullet = loadImage("pula")
        loaded = true
    }

    private func loadImage(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }
}

// MARK: - Экраны
enum AppScreen { case loading, menu, account, friends, leaderboard, game, gameOver }

// MARK: - Имя с галочкой
struct VerifiedName: View {
    let name: String
    let verified: Bool
    var fontSize: CGFloat = 15
    var fontWeight: Font.Weight = .bold

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(.white)
            if verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: fontSize * 0.9, weight: .bold))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.6), radius: 3)
            }
        }
    }
}

// MARK: - Корень
struct ContentView: View {
    @StateObject private var store = GameStore()
    @StateObject private var loader = ImageLoader()
    @StateObject private var network = NetworkManager()
    @StateObject private var music = MusicManager()
    @State private var screen: AppScreen = .loading
    @State private var lastScore = 0
    @State private var lastCoins = 0
    @State private var showInviteAlert = false
    @State private var showAuthNeededAlert = false
    @State private var multiplayerGame = false
    @State private var profileUsername: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.059, blue: 0.165)
                .ignoresSafeArea()

            switch screen {
            case .loading:
                LoadingView()
            case .menu:
                MenuView(
                    loader: loader,
                    store: store,
                    isAuthenticated: network.isAuthenticated,
                    isVerified: network.isVerified,
                    onStart: {
                        multiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .game }
                    },
                    onFriends: {
                        if !network.isAuthenticated {
                            showAuthNeededAlert = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) { screen = .friends }
                        }
                    },
                    onLeaderboard: {
                        if !network.isAuthenticated {
                            showAuthNeededAlert = true
                        } else {
                            network.getLeaderboard()
                            withAnimation(.easeInOut(duration: 0.25)) { screen = .leaderboard }
                        }
                    },
                    onAccount: {
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .account }
                    }
                )
            case .account:
                AccountView(
                    network: network,
                    store: store,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            case .friends:
                FriendsView(
                    network: network,
                    onBack: {
                        network.disconnect()
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    },
                    onOpenProfile: { username in
                        openProfile(username: username)
                    }
                )
            case .leaderboard:
                LeaderboardView(
                    network: network,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    },
                    onOpenProfile: { username in
                        openProfile(username: username)
                    }
                )
            case .game:
                GameView(
                    loader: loader,
                    store: store,
                    network: multiplayerGame ? network : nil,
                    onSaveProgress: { s, c in
                        // Вызывается когда игрок выходит через домик
                        if network.isAuthenticated && !multiplayerGame {
                            network.submitScore(s, coinsEarned: c)
                        }
                    },
                    onGameOver: { s, c in
                        lastScore = s; lastCoins = c
                        if network.isAuthenticated {
                            network.submitScore(s, coinsEarned: c)
                        }
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .gameOver }
                    },
                    onExitToMenu: {
                        network.disconnect()
                        multiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            case .gameOver:
                GameOverView(
                    score: lastScore, coins: lastCoins, store: store,
                    onRestart: {
                        network.disconnect()
                        multiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    },
                    onMenu: {
                        network.disconnect()
                        multiplayerGame = false
                        withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                    }
                )
            }

            // === ERROR OVERLAYS ===
            if screen != .loading {
                if !network.hasInternet {
                    NoInternetView(onRetry: { network.retry() })
                        .transition(.opacity)
                        .zIndex(100)
                } else if network.serverDown {
                    ServerErrorView(onRestart: {
                        network.retry()
                        if screen == .friends || screen == .leaderboard {
                            withAnimation(.easeInOut(duration: 0.25)) { screen = .menu }
                        }
                    })
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .sheet(item: Binding(
            get: { profileUsername.map { ProfileSheetItem(username: $0) } },
            set: { if $0 == nil { profileUsername = nil } }
        )) { item in
            ProfileSheet(network: network, username: item.username)
        }
        .onAppear {
            forceLandscape()
            loader.load()
            music.preload()
        }
        .onChange(of: loader.loaded) { isLoaded in
            if isLoaded && screen == .loading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.4)) { screen = .menu }
                    music.playMenu()
                }
            }
        }
        .onChange(of: screen) { newScreen in
            switch newScreen {
            case .loading, .menu, .account, .friends, .leaderboard:
                music.playMenu()
                // Обновляем лидерборд при возврате в меню, чтобы у всех были свежие данные
                if network.isAuthenticated && network.isConnected {
                    network.getLeaderboard()
                }
            case .game:
                music.playGame()
            case .gameOver:
                music.stop()
            }
        }
        .onChange(of: network.incomingInvite) { newValue in
            if newValue != nil { showInviteAlert = true }
        }
        .onChange(of: network.gameStarted) { started in
            guard started else { return }
            let onFriends = (screen == .friends)
            let onMenu = (screen == .menu)
            if onFriends || onMenu {
                multiplayerGame = true
                withAnimation(.easeInOut(duration: 0.3)) { screen = .game }
            }
        }
        .onChange(of: network.serverBest) { newBest in
            if store.bestScore != newBest { store.bestScore = newBest }
        }
        .onChange(of: network.serverCoins) { newCoins in
            if store.coins != newCoins { store.coins = newCoins }
        }
        .alert("Хотите помочь игроку?", isPresented: $showInviteAlert) {
            Button("Да") {
                if let peer = network.incomingInvite {
                    multiplayerGame = true
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
        .alert("Нужен аккаунт", isPresented: $showAuthNeededAlert) {
            Button("Создать аккаунт") {
                withAnimation(.easeInOut(duration: 0.25)) { screen = .account }
            }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Чтобы играть с друзьями и смотреть лидеров, войдите в аккаунт.")
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func openProfile(username: String) {
        network.getProfile(username: username)
        profileUsername = username
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

// Обёртка для sheet(item:)
struct ProfileSheetItem: Identifiable {
    let username: String
    var id: String { username }
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
                    Text("Установка пакетов…")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.purple).tracking(2)
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
    let isAuthenticated: Bool
    let isVerified: Bool
    let onStart: () -> Void
    let onFriends: () -> Void
    let onLeaderboard: () -> Void
    let onAccount: () -> Void
    @State private var float = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()

                // Кнопка Аккаунт (левый верх)
                VStack {
                    HStack {
                        Button(action: onAccount) {
                            HStack(spacing: 6) {
                                Image(systemName: isAuthenticated ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Аккаунт")
                                    .font(.system(size: 13, weight: .bold))
                                if isAuthenticated && isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.blue)
                                }
                            }
                            .foregroundColor(isAuthenticated ? .green : .white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .stroke(isAuthenticated ? Color.green.opacity(0.6) : Color.purple.opacity(0.6), lineWidth: 1.5))
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.leading, max(16, geo.safeAreaInsets.leading + 8))
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))
                    Spacer()
                }

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
                                .frame(width: geo.size.width * 0.26, height: 54)
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
                                    Image(systemName: isAuthenticated ? "person.2.fill" : "lock.fill")
                                        .font(.system(size: 20))
                                    Text("Друзья").font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(width: 70, height: 54)
                                .background(LinearGradient(
                                    colors: isAuthenticated ?
                                        [Color(red: 0.20, green: 0.65, blue: 0.98), Color(red: 0.10, green: 0.45, blue: 0.85)] :
                                        [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                                    startPoint: .top, endPoint: .bottom))
                                .cornerRadius(18)
                                .shadow(color: (isAuthenticated ? Color.blue : Color.gray).opacity(0.6), radius: 15)
                            }
                            .buttonStyle(.plain)

                            Button(action: onLeaderboard) {
                                VStack(spacing: 2) {
                                    Image(systemName: isAuthenticated ? "trophy.fill" : "lock.fill")
                                        .font(.system(size: 20))
                                    Text("Лидеры").font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(width: 70, height: 54)
                                .background(LinearGradient(
                                    colors: isAuthenticated ?
                                        [Color(red: 1.0, green: 0.72, blue: 0.15), Color(red: 0.85, green: 0.45, blue: 0.05)] :
                                        [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                                    startPoint: .top, endPoint: .bottom))
                                .cornerRadius(18)
                                .shadow(color: (isAuthenticated ? Color.orange : Color.gray).opacity(0.6), radius: 15)
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

// MARK: - Экран Аккаунта
struct AccountView: View {
    @ObservedObject var network: NetworkManager
    @ObservedObject var store: GameStore
    let onBack: () -> Void

    @State private var isRegisterMode = true
    @State private var username = ""
    @State private var password = ""
    @State private var showSuccess = false
    @State private var isSending = false
    @FocusState private var focusField: Field?

    enum Field { case username, password }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()

                VStack(spacing: 14) {
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
                        Text("АККАУНТ")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white).tracking(3)
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, max(20, geo.safeAreaInsets.leading + 8))
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))

                    Spacer()

                    if network.isAuthenticated {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            Text("Вы вошли!")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)

                            HStack(spacing: 6) {
                                Text(network.displayName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.cyan)
                                if network.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.blue)
                                        .shadow(color: .blue.opacity(0.7), radius: 5)
                                }
                            }

                            HStack(spacing: 30) {
                                VStack(spacing: 4) {
                                    Text("Рекорд")
                                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.circle.fill")
                                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                        Text("\(store.bestScore)")
                                            .font(.system(size: 22, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                }
                                VStack(spacing: 4) {
                                    Text("Монеты")
                                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                                    HStack(spacing: 4) {
                                        Image(systemName: "dollarsign.circle.fill")
                                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                        Text("\(store.coins)")
                                            .font(.system(size: 22, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(.top, 10)

                            Button(action: { network.logout() }) {
                                Text("Выйти из аккаунта")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        }
                        .padding(30)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.green.opacity(0.5), lineWidth: 2))
                    }
                    else if !network.isConnected {
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5).tint(.purple)
                            Text("Загрузка сервера…")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                            if let err = network.connectionError {
                                Text(err).font(.system(size: 13)).foregroundColor(.red)
                                Button(action: { network.retry() }) {
                                    Text("Повторить")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24).padding(.vertical, 10)
                                        .background(Color.purple)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(40)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(24)
                    }
                    else {
                        ScrollView {
                            VStack(spacing: 14) {
                                Text(showSuccess ? "Вы зарегистрировались!" :
                                     (isRegisterMode ? "Хотите создать аккаунт?" : "Вход в аккаунт"))
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundColor(showSuccess ? .green : .white)

                                if !showSuccess {
                                    TextField("Имя (3-20 символов)", text: $username)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .textContentType(.username)
                                        .focused($focusField, equals: .username)
                                        .submitLabel(.next)
                                        .onSubmit { focusField = .password }
                                        .padding(14)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(14)
                                        .foregroundColor(.white)
                                        .frame(width: geo.size.width * 0.45)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(focusField == .username ? Color.cyan : Color.clear, lineWidth: 1.5)
                                        )

                                    SecureField("Пароль (минимум 4)", text: $password)
                                        .textContentType(.password)
                                        .focused($focusField, equals: .password)
                                        .submitLabel(.go)
                                        .onSubmit { sendAuthRequest() }
                                        .padding(14)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(14)
                                        .foregroundColor(.white)
                                        .frame(width: geo.size.width * 0.45)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(focusField == .password ? Color.cyan : Color.clear, lineWidth: 1.5)
                                        )

                                    if let err = network.authError {
                                        Text(err)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.red)
                                            .multilineTextAlignment(.center)
                                            .frame(width: geo.size.width * 0.45)
                                    }

                                    if let err = network.connectionError {
                                        Text("⚠️ \(err)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.orange)
                                            .multilineTextAlignment(.center)
                                            .frame(width: geo.size.width * 0.45)
                                    }

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(network.isConnected ? Color.green : Color.red)
                                            .frame(width: 8, height: 8)
                                        Text(network.isConnected ? "Сервер подключён" : "Нет соединения с сервером")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.6))
                                    }

                                    Button(action: sendAuthRequest) {
                                        HStack(spacing: 8) {
                                            if isSending {
                                                ProgressView().tint(.white).scaleEffect(0.8)
                                            }
                                            Text(isSending ? "Отправка…" :
                                                 (isRegisterMode ? "Создать аккаунт" : "Войти"))
                                                .font(.system(size: 17, weight: .bold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: geo.size.width * 0.45, height: 50)
                                        .background(LinearGradient(
                                            colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                                     Color(red: 0.29, green: 0.23, blue: 0.71)],
                                            startPoint: .top, endPoint: .bottom))
                                        .cornerRadius(14)
                                        .shadow(color: .purple.opacity(0.6), radius: 15)
                                        .opacity(isSending ? 0.6 : 1.0)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSending)

                                    Button(action: {
                                        isRegisterMode.toggle()
                                        network.authError = nil
                                        focusField = nil
                                    }) {
                                        Text(isRegisterMode ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.cyan)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(30)
                        }
                        .frame(width: geo.size.width * 0.6, height: geo.size.height * 0.75)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.purple.opacity(0.5), lineWidth: 2))
                    }

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !network.isConnected { network.connect() }
        }
        .onChange(of: network.isAuthenticated) { authed in
            isSending = false
            if authed {
                showSuccess = true
                focusField = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSuccess = false }
            }
        }
        .onChange(of: network.authError) { err in
            if err != nil { isSending = false }
        }
    }

    private func sendAuthRequest() {
        guard !isSending else { return }
        guard network.isConnected else {
            network.authError = "Подключение к серверу…"
            return
        }
        focusField = nil
        isSending = true
        network.authError = nil

        if isRegisterMode {
            network.register(username: username, password: password)
        } else {
            network.login(username: username, password: password)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if isSending { isSending = false }
        }
    }
}

// MARK: - Друзья
struct FriendsView: View {
    @ObservedObject var network: NetworkManager
    let onBack: () -> Void
    let onOpenProfile: (String) -> Void
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
            network.refreshPlayerList()
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
            Text(network.isConnected ? "Подключено" : (network.connectionError ?? "Подключение..."))
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
        let cleanName = extractUsername(from: player.name)

        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.3)).frame(width: 44, height: 44)
                Image(systemName: "person.fill").foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                VerifiedName(name: cleanName, verified: player.verified, fontSize: 16, fontWeight: .bold)
                Text("Нажмите ⋯ для действий")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()

            Menu {
                Button {
                    network.sendInvite(to: player.id)
                } label: {
                    Label("Пригласить в игру", systemImage: "paperplane.fill")
                }
                Button {
                    onOpenProfile(cleanName)
                } label: {
                    Label("Профиль", systemImage: "person.text.rectangle")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
                    .padding(6)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(player.verified ? Color.blue.opacity(0.6) : Color.purple.opacity(0.4), lineWidth: 1)
        )
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

    private func extractUsername(from display: String) -> String {
        if let openParen = display.firstIndex(of: "("),
           let closeParen = display.firstIndex(of: ")") {
            let inner = display[display.index(after: openParen)..<closeParen]
            if let underscore = inner.lastIndex(of: "_") {
                return String(inner[..<underscore])
            }
            return String(inner)
        }
        return display
    }
}

// MARK: - Лидерборд
struct LeaderboardView: View {
    @ObservedObject var network: NetworkManager
    let onBack: () -> Void
    let onOpenProfile: (String) -> Void
    @State private var refreshTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldBackground()
                VStack(spacing: 16) {
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
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                            Text("ЛИДЕРЫ")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white).tracking(3)
                        }
                        Spacer()
                        Button(action: { network.getLeaderboard() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.cyan)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, max(20, geo.safeAreaInsets.leading + 8))
                    .padding(.top, max(8, geo.safeAreaInsets.top + 4))

                    if network.leaderboard.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView().tint(.purple)
                            Text("Загрузка рейтинга…")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(network.leaderboard) { entry in
                                    entryRow(entry)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            network.getLeaderboard()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                network.getLeaderboard()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        Button {
            onOpenProfile(entry.name)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(medalColor(for: entry.rank))
                        .frame(width: 44, height: 44)
                    if entry.rank <= 3 {
                        Text(medalEmoji(for: entry.rank))
                            .font(.system(size: 22))
                    } else {
                        Text("\(entry.rank)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                VerifiedName(name: entry.name, verified: entry.verified, fontSize: 16, fontWeight: .bold)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                        Text("\(entry.score)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                        Text("\(entry.coins)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(12)
            .background(
                entry.rank <= 3 ?
                    Color.orange.opacity(0.12) :
                    Color.white.opacity(0.06)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        entry.verified ? Color.blue.opacity(0.6) :
                        (entry.rank <= 3 ? Color.orange.opacity(0.5) : Color.purple.opacity(0.3)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.85, blue: 0.24).opacity(0.35)
        case 2: return Color(white: 0.75).opacity(0.35)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.25).opacity(0.35)
        default: return Color.purple.opacity(0.25)
        }
    }

    private func medalEmoji(for rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return ""
        }
    }
}

// MARK: - Профиль (sheet)
struct ProfileSheet: View {
    @ObservedObject var network: NetworkManager
    let username: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                if let profile = network.currentProfile {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.25))
                            .frame(width: 100, height: 100)
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        if profile.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                                .shadow(color: .blue.opacity(0.7), radius: 6)
                                .offset(x: 35, y: 35)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(profile.username)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if profile.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .shadow(color: .blue.opacity(0.7), radius: 5)
                        }
                    }

                    HStack(spacing: 30) {
                        VStack(spacing: 4) {
                            Text("Рекорд")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                            HStack(spacing: 4) {
                                Image(systemName: "star.circle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                Text("\(profile.bestScore)")
                                    .font(.system(size: 24, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                        }
                        VStack(spacing: 4) {
                            Text("Монеты")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.24))
                                Text("\(profile.coins)")
                                    .font(.system(size: 24, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 10)

                    if profile.verified {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                            Text("Верифицированный игрок")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue.opacity(0.9))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(20)
                    }
                } else if let err = network.profileError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(.purple).scaleEffect(1.3)
                        Text("Загрузка профиля…")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

// MARK: - Игра
struct GameView: View {
    @ObservedObject var loader: ImageLoader
    @ObservedObject var store: GameStore
    var network: NetworkManager? = nil
    let onSaveProgress: (Int, Int) -> Void
    let onGameOver: (Int, Int) -> Void
    let onExitToMenu: () -> Void

    @State private var heroY: CGFloat = 0
    @State private var heroTargetY: CGFloat = 0
    @State private var remoteHeroY: CGFloat = 0
    @State private var remoteHeroYTarget: CGFloat = 0
    @State private var bullets: [Bullet] = []
    @State private var enemies: [Enemy] = []
    @State private var score = 0
    @State private var earnedCoins = 0
    @State private var isGameOver = false
    @State private var spawnTimer: Double = 0
    @State private var fireTimer: Double = 0
    @State private var netSendTimer: Double = 0

    private let heroSizeRatio: CGFloat = 0.13
    private let enemySizeRatio: CGFloat = 0.11
    private let bulletSizeRatio: CGFloat = 0.045
    private let bulletSpeedRatio: CGFloat = 1.10
    private let baseEnemySpeed: CGFloat = 0.312
    private let baseSpawnInterval: Double = 1.35
    private let minSpawnInterval: Double = 0.96
    private let fireInterval: Double = 0.28

    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var isMultiplayer: Bool { network != nil }
    var isHost: Bool { network?.isHost ?? false }

    var enemySpeedMultiplier: CGFloat { 1.0 + min(CGFloat(score) * 0.00832, 0.52) }
    var currentSpawnInterval: Double { max(minSpawnInterval, baseSpawnInterval - Double(score) * 0.0052) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let heroSize = w * heroSizeRatio
            let myHeroX: CGFloat = w * 0.13
            let peerHeroX: CGFloat = w * 0.24
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

                if isMultiplayer, let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .hueRotation(.degrees(60))
                        .position(x: peerHeroX, y: remoteHeroY)
                        .shadow(color: .cyan.opacity(0.8), radius: 15)
                }

                if let hero = loader.hero {
                    Image(uiImage: hero)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: heroSize, height: heroSize)
                        .rotationEffect(.degrees(sin(Double(score)) * 5))
                        .position(x: myHeroX, y: heroY)
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
                remoteHeroY = h * 0.5
                remoteHeroYTarget = h * 0.5
            }
            .onReceive(timer) { _ in
                if !isGameOver {
                    tick(w: w, h: h, heroSize: heroSize,
                         myHeroX: myHeroX, peerHeroX: peerHeroX,
                         enemySize: enemySize, bulletSize: bulletSize)
                }
            }
        }
        .ignoresSafeArea()
    }

    func tick(w: CGFloat, h: CGFloat, heroSize: CGFloat,
              myHeroX: CGFloat, peerHeroX: CGFloat,
              enemySize: CGFloat, bulletSize: CGFloat) {

        heroY += (heroTargetY - heroY) * 0.2
        let minY = heroSize / 2 + 10
        let maxY = h - heroSize / 2 - 10
        if heroY < minY { heroY = minY }
        if heroY > maxY { heroY = maxY }

        if isMultiplayer && !isHost {
            netSendTimer += 1.0 / 60.0
            if netSendTimer >= 0.025 {
                netSendTimer = 0
                network?.sendClientY(heroY)
            }

            remoteHeroYTarget = network?.remoteHeroY ?? remoteHeroY
            remoteHeroY += (remoteHeroYTarget - remoteHeroY) * 0.35

            if let net = network {
                score = net.remoteScore
                earnedCoins = net.remoteCoins
                enemies = net.remoteEnemies.compactMap { dict in
                    guard let x = dict["x"] as? Double,
                          let y = dict["y"] as? Double,
                          let s = dict["size"] as? Double else { return nil }
                    return Enemy(x: CGFloat(x), y: CGFloat(y), size: CGFloat(s))
                }
                bullets = net.remoteBullets.compactMap { dict in
                    guard let x = dict["x"] as? Double,
                          let y = dict["y"] as? Double else { return nil }
                    return Bullet(x: CGFloat(x), y: CGFloat(y))
                }
                if net.remoteGameOver && !isGameOver { triggerGameOver() }
            }
            return
        }

        if isMultiplayer {
            remoteHeroYTarget = network?.remoteHeroY ?? remoteHeroY
            remoteHeroY += (remoteHeroYTarget - remoteHeroY) * 0.35
        }

        fireTimer += 1.0 / 60.0
        if fireTimer >= fireInterval {
            fireTimer = 0
            bullets.append(Bullet(x: myHeroX + heroSize * 0.4, y: heroY))
            if isMultiplayer {
                bullets.append(Bullet(x: peerHeroX + heroSize * 0.4, y: remoteHeroY))
            }
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
            let dx = abs(myHeroX - e.x)
            let dy2 = abs(heroY - e.y)
            if dx < (heroSize + e.size) / 2 - 10 && dy2 < (heroSize + e.size) / 2 - 10 {
                triggerGameOver(); return
            }
        }
        if isMultiplayer {
            for e in enemies {
                let dx = abs(peerHeroX - e.x)
                let dy2 = abs(remoteHeroY - e.y)
                if dx < (heroSize + e.size) / 2 - 10 && dy2 < (heroSize + e.size) / 2 - 10 {
                    triggerGameOver(); return
                }
            }
        }

        if isMultiplayer && isHost {
            netSendTimer += 1.0 / 60.0
            if netSendTimer >= 0.050 {
                netSendTimer = 0
                let enemiesJSON = enemies.map { ["x": Double($0.x), "y": Double($0.y), "size": Double($0.size)] }
                let bulletsJSON = bullets.map { ["x": Double($0.x), "y": Double($0.y)] }
                network?.sendGameState(
                    enemies: enemiesJSON, bullets: bulletsJSON,
                    hostY: heroY, score: score, coins: earnedCoins, gameOver: false
                )
            }
        }
    }

    func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        if !isMultiplayer {
            store.commit(score: score, coins: earnedCoins)
        }
        if isMultiplayer && isHost {
            network?.sendGameState(enemies: [], bullets: [], hostY: heroY,
                                   score: score, coins: earnedCoins, gameOver: true)
        }
        onGameOver(score, earnedCoins)
    }

    func exitGame() {
        if !isGameOver && (score > 0 || earnedCoins > 0) {
            if !isMultiplayer {
                // Одиночная игра — сохраняем локально и отправляем на сервер
                store.commit(score: score, coins: earnedCoins)
                onSaveProgress(score, earnedCoins)
            }
            // Co-op хост — сообщаем финальное состояние гостю
            if isMultiplayer && isHost {
                network?.sendGameState(enemies: [], bullets: [], hostY: heroY,
                                       score: score, coins: earnedCoins, gameOver: true)
            }
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

// MARK: - Экран "Нет интернета"
struct NoInternetView: View {
    let onRetry: () -> Void
    @State private var rotate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.15)).frame(width: 130, height: 130)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 60)).foregroundColor(.red)
                }
                Text("Нет соединения с интернетом")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white).multilineTextAlignment(.center)
                Text("Проверьте Wi-Fi или мобильные данные")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(action: {
                    rotate = true
                    onRetry()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { rotate = false }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(rotate ? 360 : 0))
                            .animation(.linear(duration: 0.6), value: rotate)
                        Text("Повторить").font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 34).padding(.vertical, 14)
                    .background(LinearGradient(
                        colors: [Color(red: 0.42, green: 0.36, blue: 0.91),
                                 Color(red: 0.29, green: 0.23, blue: 0.71)],
                        startPoint: .top, endPoint: .bottom))
                    .cornerRadius(16)
                    .shadow(color: .purple.opacity(0.6), radius: 15)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
    }
}

// MARK: - Экран "Технические неполадки"
struct ServerErrorView: View {
    let onRestart: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.15))
                        .frame(width: 130, height: 130)
                        .scaleEffect(pulse ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60)).foregroundColor(.orange)
                }
                Text("Технические неполадки")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Сервер временно недоступен.\nПопробуйте позже.")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(action: onRestart) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Перезагрузить игру").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(LinearGradient(
                        colors: [Color.orange, Color.red.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom))
                    .cornerRadius(16)
                    .shadow(color: .orange.opacity(0.6), radius: 15)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
        .onAppear { pulse = true }
    }
}

#Preview {
    ContentView()
}
