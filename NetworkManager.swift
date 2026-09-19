import Foundation
import UIKit

struct PlayerInfo: Identifiable, Equatable {
    let id: String
    let name: String
}

class NetworkManager: NSObject, ObservableObject, URLSessionWebSocketDelegate, URLSessionDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!

    @Published var isConnected = false
    @Published var onlinePlayers: [PlayerInfo] = []
    @Published var incomingInvite: PlayerInfo? = nil
    @Published var connectionError: String? = nil

    // Авторизация
    @Published var isAuthenticated = false
    @Published var username: String = ""
    @Published var displayName: String = ""
    @Published var userID: Int = 0
    @Published var authError: String? = nil
    @Published var needAuth = false
    @Published var isConnecting = false

    // Мультиплеер
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

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    func connect() {
        if isConnected || isConnecting { return }
        print("🔌 Подключение к \(serverURL)")
        guard let url = URL(string: serverURL) else {
            connectionError = "Неверный адрес"
            return
        }
        connectionError = nil
        isConnecting = true
        resetGameState()
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnecting = false
        onlinePlayers = []
        myPlayerID = ""
        resetGameState()
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
        disconnect()
    }

    // ============ АВТОРИЗАЦИЯ ============
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
    func submitScore(_ score: Int, coins: Int) {
        sendJSON(["type": "submit_score", "score": score, "coins": coins])
    }

    func refreshPlayerList() { sendJSON(["type": "get_players"]) }
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

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(string)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.connectionError = "Ошибка отправки: \(error.localizedDescription)"
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.isConnecting = false
                    if self?.connectionError == nil {
                        self?.connectionError = "Сервер недоступен"
                    }
                    print("❌ WS: \(error.localizedDescription)")
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
                    self.sendName()
                    if let best = json["best_score"] as? Int {
                        UserDefaults.standard.set(best, forKey: "cosmic_best")
                    }
                    if let co = json["coins"] as? Int {
                        UserDefaults.standard.set(co, forKey: "cosmic_coins")
                    }
                    print("✅ Авторизован: \(display)")
                }

            case "auth_error":
                if let msg = json["message"] as? String {
                    self.authError = msg
                    self.isAuthenticated = false
                    AuthStore.shared.clear()
                }

            case "player_list":
                if let players = json["players"] as? [[String: Any]] {
                    var infos: [PlayerInfo] = []
                    for p in players {
                        guard let id = p["id"] as? String,
                              let name = p["name"] as? String else { continue }
                        infos.append(PlayerInfo(id: id, name: name))
                    }
                    self.onlinePlayers = infos
                }

            case "invite_received":
                if let fromID = json["from_id"] as? String,
                   let fromName = json["from_name"] as? String {
                    self.incomingInvite = PlayerInfo(id: fromID, name: fromName)
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

    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.isConnecting = false
            self.connectionError = nil
            print("✅ WebSocket подключен")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            if self.connectionError == nil { self.connectionError = "Соединение закрыто" }
        }
    }

    // MARK: - Доверие сертификату
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
