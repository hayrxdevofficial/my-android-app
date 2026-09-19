import Foundation
import UIKit
import Network

struct PlayerInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let verified: Bool
}

struct LeaderboardEntry: Identifiable, Equatable {
    let id = UUID()
    let rank: Int
    let name: String
    let score: Int
    let coins: Int
    let verified: Bool
}

struct ProfileInfo: Equatable {
    let username: String
    let bestScore: Int
    let coins: Int
    let verified: Bool
}

class NetworkManager: NSObject, ObservableObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.hayrx.networkMonitor")

    // Буфер
    private var pendingMessages: [String] = []
    private let maxBufferSize = 50
    private var isSocketOpen = false
    private var isSocketAlive = false

    // Heartbeat
    private var pingTimer: Timer?
    private var lastPongTime: Date = Date()
    private let pingInterval: TimeInterval = 25
    private let pongTimeout: TimeInterval = 60

    // Live-save
    private var liveTimer: Timer?
    private var pendingScore: Int = 0
    private var pendingEarned: Int = 0
    private var roundActive: Bool = false

    @Published var isConnected = false
    @Published var onlinePlayers: [PlayerInfo] = []
    @Published var incomingInvite: PlayerInfo? = nil
    @Published var connectionError: String? = nil

    @Published var hasInternet = true
    @Published var serverDown = false

    @Published var isAuthenticated = false
    @Published var username: String = ""
    @Published var displayName: String = ""
    @Published var userID: Int = 0
    @Published var isVerified: Bool = false
    @Published var authError: String? = nil
    @Published var needAuth = false
    @Published var isConnecting = false

    @Published var serverBest: Int = 0
    @Published var serverCoins: Int = 0

    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var currentProfile: ProfileInfo? = nil
    @Published var profileError: String? = nil

    @Published var gameStarted = false
    @Published var peerID: String? = nil
    @Published var isHost: Bool = false

    @Published var remoteHeroY: CGFloat = 0
    @Published var remoteEnemies: [[String: Any]] = []
    @Published var remoteBullets: [[String: Any]] = []
    @Published var remoteScore: Int = 0
    @Published var remoteCoins: Int = 0
    @Published var remoteGameOver = false

    let serverURL = "wss://popularly-phlegmatic-tomcat.cloudpub.ru:443"

    private var myPlayerID: String = ""
    private var pendingPeerID: String? = nil
    private var isIntentionalDisconnect = false

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        startInternetMonitor()
    }

    deinit {
        pingTimer?.invalidate()
        liveTimer?.invalidate()
    }

    // MARK: - Интернет
    private func startInternetMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let hasNet = path.status == .satisfied
                let wasOffline = (self.hasInternet == false)
                self.hasInternet = hasNet
                if !hasNet {
                    self.serverDown = false
                } else if wasOffline {
                    print("🌐 [NET] Интернет вернулся")
                    self.serverDown = false
                    self.connectionError = nil
                    if !self.isConnected { self.connect() }
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Подключение
    func connect() {
        if isConnected || isConnecting { return }
        guard hasInternet else {
            connectionError = "Нет соединения с интернетом"
            return
        }
        guard let url = URL(string: serverURL) else {
            connectionError = "Неверный адрес"
            return
        }
        connectionError = nil
        serverDown = false
        isConnecting = true
        isIntentionalDisconnect = false
        isSocketOpen = false
        isSocketAlive = false
        resetGameState()
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
        startHeartbeat()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        stopHeartbeat()
        liveTimer?.invalidate()
        liveTimer = nil
        roundActive = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnecting = false
        isSocketOpen = false
        isSocketAlive = false
        onlinePlayers = []
        myPlayerID = ""
        resetGameState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isIntentionalDisconnect = false
        }
    }

    func retry() {
        connectionError = nil
        serverDown = false
        isConnecting = false
        isConnected = false
        isSocketOpen = false
        isSocketAlive = false
        stopHeartbeat()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connect()
        }
    }

    private func resetGameState() {
        gameStarted = false
        peerID = nil
        isHost = false
        pendingPeerID = nil
        remoteHeroY = 0
        remoteEnemies = []
        remoteBullets = []
        remoteScore = 0
        remoteCoins = 0
        remoteGameOver = false
    }

    func logout() {
        AuthStore.shared.clear()
        isAuthenticated = false
        username = ""
        displayName = ""
        userID = 0
        isVerified = false
        serverBest = 0
        serverCoins = 0
        leaderboard = []
        currentProfile = nil
        disconnect()
    }

    // MARK: - Heartbeat
    private func startHeartbeat() {
        pingTimer?.invalidate()
        lastPongTime = Date()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        guard isSocketOpen, webSocketTask != nil else { return }
        let elapsed = Date().timeIntervalSince(lastPongTime)
        if elapsed > pongTimeout {
            print("💀 [NET] Сокет мёртв \(Int(elapsed)) сек — переподключение")
            isSocketOpen = false
            isSocketAlive = false
            isConnected = false
            stopHeartbeat()
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.connect()
            }
            return
        }
        sendJSON(["type": "ping"])
    }

    // MARK: - Round (live-save)
    func startRound() {
        guard isAuthenticated else { return }
        roundActive = true
        pendingScore = 0
        pendingEarned = 0
        print("📤 [NET] → start_round")
        sendJSON(["type": "start_round"])
    }

    /// Live-сохранение: вызывай при каждом изменении score/earnedCoins.
    /// Дебаунс 150 мс — если изменения идут подряд, уйдёт только последнее.
    func submitScoreLive(score: Int, earnedCoins: Int) {
        guard roundActive else { return }
        pendingScore = score
        pendingEarned = earnedCoins

        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.flushLiveScore()
        }
    }

    /// Финальная отправка — при выходе через домик или смерти.
    /// Уходит немедленно, без ожидания дебаунса.
    func submitScoreFinal(score: Int, earnedCoins: Int) {
        guard roundActive else { return }
        liveTimer?.invalidate()
        liveTimer = nil
        pendingScore = score
        pendingEarned = earnedCoins
        flushLiveScore()
        roundActive = false
    }

    private func flushLiveScore() {
        guard pendingScore > 0 || pendingEarned > 0 else { return }
        print("📤 [NET] → submit_score(\(pendingScore), \(pendingEarned))")
        sendJSON([
            "type": "submit_score",
            "score": pendingScore,
            "coins_earned": pendingEarned
        ])
    }

    // MARK: - Авторизация
    func register(username: String, password: String) {
        authError = nil
        sendJSON(["type": "register", "username": username, "password": password])
    }
    func login(username: String, password: String) {
        authError = nil
        sendJSON(["type": "login", "username": username, "password": password])
    }
    func tokenLogin() {
        guard let token = AuthStore.shared.token else { return }
        sendJSON(["type": "token_login", "token": token])
    }
    func sendName() { sendJSON(["type": "set_name"]) }

    func refreshPlayerList() { sendJSON(["type": "get_players"]) }
    func getLeaderboard() { sendJSON(["type": "get_leaderboard"]) }
    func getProfile(username: String) {
        currentProfile = nil
        profileError = nil
        sendJSON(["type": "get_profile", "username": username])
    }

    func sendInvite(to targetID: String) {
        pendingPeerID = targetID
        sendJSON(["type": "invite", "target_id": targetID])
    }
    func respondToInvite(from targetID: String, accepted: Bool) {
        if accepted { peerID = targetID; isHost = false; gameStarted = true }
        sendJSON(["type": "invite_response", "target_id": targetID, "accepted": accepted])
    }

    func sendGameState(enemies: [[String: Any]], bullets: [[String: Any]],
                       hostY: CGFloat, score: Int, coins: Int, gameOver: Bool) {
        guard let peer = peerID else { return }
        sendJSON(["type": "game_data", "target_id": peer, "payload": [
            "kind": "state", "enemies": enemies, "bullets": bullets,
            "hostY": hostY, "score": score, "coins": coins, "gameOver": gameOver
        ]])
    }
    func sendClientY(_ y: CGFloat) {
        guard let peer = peerID else { return }
        sendJSON(["type": "game_data", "target_id": peer, "payload": [
            "kind": "clientY", "y": Double(y)
        ]])
    }

    // MARK: - Отправка
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        let isCritical = isCriticalMessage(dict)

        if !isSocketOpen || !isSocketAlive || webSocketTask == nil {
            if isCritical {
                if pendingMessages.count < maxBufferSize {
                    print("⏳ [NET] Буферизую: \(string.prefix(80))")
                    pendingMessages.append(string)
                } else {
                    pendingMessages.removeFirst()
                    pendingMessages.append(string)
                }
            }
            return
        }

        webSocketTask?.send(.string(string)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.connectionError = "Ошибка: \(error.localizedDescription)"
                    if isCritical, let s = self, s.pendingMessages.count < s.maxBufferSize {
                        s.pendingMessages.append(string)
                    }
                }
            }
        }
    }

    private func isCriticalMessage(_ dict: [String: Any]) -> Bool {
        guard let t = dict["type"] as? String else { return false }
        return [
            "register", "login", "token_login",
            "submit_score", "start_round", "set_name",
            "get_leaderboard", "get_profile",
            "invite", "invite_response", "get_players"
        ].contains(t)
    }

    private func flushPendingMessages() {
        guard isSocketOpen, isSocketAlive, !pendingMessages.isEmpty else { return }
        print("🚀 [NET] Отправляю буфер (\(pendingMessages.count))")
        let toSend = pendingMessages
        pendingMessages.removeAll()
        for string in toSend {
            webSocketTask?.send(.string(string)) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.pendingMessages.append(string)
                    }
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    print("❌ [NET] WS: \(error.localizedDescription)")
                    self.isConnected = false
                    self.isConnecting = false
                    self.isSocketOpen = false
                    self.isSocketAlive = false
                    if self.isIntentionalDisconnect { return }
                    if !self.hasInternet {
                        self.connectionError = "Нет соединения с интернетом"
                        self.serverDown = false
                    } else {
                        self.connectionError = "Восстанавливаю соединение…"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            guard let self = self, !self.isIntentionalDisconnect, !self.isConnected else { return }
                            print("🔄 [NET] Авто-переподключение")
                            self.connect()
                        }
                    }
                }
            case .success(let message):
                switch message {
                case .string(let text): self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self?.handleMessage(text) }
                @unknown default: break
                }
                self?.receiveMessage()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "pong":
                self.lastPongTime = Date()
                if !self.isSocketAlive {
                    self.isSocketAlive = true
                    print("💚 [NET] Сокет живой — flush буфер")
                    self.flushPendingMessages()
                }

            case "need_auth":
                self.needAuth = true
                if AuthStore.shared.token != nil { self.tokenLogin() }

            case "auth_ok":
                if let token = json["token"] as? String,
                   let name = json["username"] as? String,
                   let uid = json["user_id"] as? Int,
                   let display = json["display_name"] as? String {
                    AuthStore.shared.token = token
                    AuthStore.shared.username = name
                    self.username = name
                    self.displayName = display
                    self.userID = uid
                    self.isAuthenticated = true
                    self.needAuth = false
                    self.authError = nil
                    self.serverDown = false
                    self.isVerified = (json["verified"] as? Bool) ?? false
                    self.sendName()
                    if let best = json["best_score"] as? Int {
                        self.serverBest = best
                        UserDefaults.standard.set(best, forKey: "cosmic_best")
                    }
                    if let co = json["coins"] as? Int {
                        self.serverCoins = co
                        UserDefaults.standard.set(co, forKey: "cosmic_coins")
                    }
                }

            case "auth_error":
                if let msg = json["message"] as? String {
                    self.authError = msg
                    self.isAuthenticated = false
                    AuthStore.shared.clear()
                }

            case "banned":
                if let msg = json["message"] as? String {
                    self.authError = msg
                    self.isAuthenticated = false
                    AuthStore.shared.clear()
                    self.disconnect()
                }

            case "round_started":
                print("🏁 [NET] Раунд начат")

            case "score_saved":
                if let best = json["best_score"] as? Int,
                   let coins = json["coins"] as? Int {
                    self.serverBest = best
                    self.serverCoins = coins
                    UserDefaults.standard.set(best, forKey: "cosmic_best")
                    UserDefaults.standard.set(coins, forKey: "cosmic_coins")
                }

            case "player_list":
                if let players = json["players"] as? [[String: Any]] {
                    var infos: [PlayerInfo] = []
                    for p in players {
                        guard let id = p["id"] as? String,
                              let name = p["name"] as? String else { continue }
                        infos.append(PlayerInfo(id: id, name: name,
                                                verified: (p["verified"] as? Bool) ?? false))
                    }
                    self.onlinePlayers = infos
                }

            case "leaderboard":
                if let players = json["players"] as? [[String: Any]] {
                    var entries: [LeaderboardEntry] = []
                    for p in players {
                        guard let rank = p["rank"] as? Int,
                              let name = p["name"] as? String,
                              let score = p["score"] as? Int,
                              let coins = p["coins"] as? Int else { continue }
                        entries.append(LeaderboardEntry(
                            rank: rank, name: name, score: score, coins: coins,
                            verified: (p["verified"] as? Bool) ?? false
                        ))
                    }
                    self.leaderboard = entries
                }

            case "profile":
                if let name = json["username"] as? String,
                   let best = json["best_score"] as? Int,
                   let coins = json["coins"] as? Int {
                    self.currentProfile = ProfileInfo(
                        username: name, bestScore: best, coins: coins,
                        verified: (json["verified"] as? Bool) ?? false
                    )
                }

            case "profile_error":
                if let msg = json["message"] as? String { self.profileError = msg }

            case "invite_received":
                if let fromID = json["from_id"] as? String,
                   let fromName = json["from_name"] as? String {
                    self.incomingInvite = PlayerInfo(
                        id: fromID, name: fromName,
                        verified: (json["from_verified"] as? Bool) ?? false
                    )
                }

            case "invite_answer":
                if let accepted = json["accepted"] as? Bool, accepted {
                    if let peer = self.pendingPeerID {
                        self.peerID = peer; self.isHost = true; self.gameStarted = true
                    }
                }

            case "game_data":
                if let payload = json["payload"] as? [String: Any],
                   let kind = payload["kind"] as? String {
                    if kind == "state" && !self.isHost {
                        self.remoteEnemies = payload["enemies"] as? [[String: Any]] ?? []
                        self.remoteBullets = payload["bullets"] as? [[String: Any]] ?? []
                        if let y = payload["hostY"] as? Double { self.remoteHeroY = CGFloat(y) }
                        if let sc = payload["score"] as? Int { self.remoteScore = sc }
                        if let co = payload["coins"] as? Int { self.remoteCoins = co }
                        if let go = payload["gameOver"] as? Bool { self.remoteGameOver = go }
                    } else if kind == "clientY" && self.isHost {
                        if let y = payload["y"] as? Double { self.remoteHeroY = CGFloat(y) }
                    }
                }

            default: break
            }
        }
    }

    // MARK: - Delegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            print("✅ [NET] WebSocket открыт")
            self.isConnected = true
            self.isConnecting = false
            self.isSocketOpen = true
            self.isSocketAlive = false
            self.lastPongTime = Date()
            self.connectionError = nil
            self.serverDown = false

            if self.isAuthenticated, let token = AuthStore.shared.token {
                self.sendJSON(["type": "token_login", "token": token])
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            print("🔌 [NET] WS закрыт (\(closeCode.rawValue))")
            self.isSocketOpen = false
            self.isSocketAlive = false
            self.isConnected = false
            self.isConnecting = false
            guard !self.isIntentionalDisconnect else { return }
            if !self.hasInternet {
                self.connectionError = "Нет соединения с интернетом"
                self.serverDown = false
            } else {
                self.connectionError = "Восстанавливаю соединение…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self = self, !self.isIntentionalDisconnect, !self.isConnected else { return }
                    print("🔄 [NET] Авто-переподключение")
                    self.connect()
                }
            }
        }
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
