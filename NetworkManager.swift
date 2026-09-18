import Foundation
import UIKit

struct PlayerInfo: Identifiable, Equatable {
    let id: String
    let name: String
}

class NetworkManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!

    @Published var isConnected = false
    @Published var onlinePlayers: [PlayerInfo] = []
    @Published var incomingInvite: PlayerInfo? = nil
    @Published var connectionError: String? = nil

    // Мультиплеер
    @Published var gameStarted = false
    @Published var peerID: String? = nil
    @Published var isHost: Bool = false

    // Данные от партнёра
    @Published var remoteHeroY: CGFloat = 0
    @Published var remoteEnemies: [[String: Any]] = []
    @Published var remoteBullets: [[String: Any]] = []
    @Published var remoteScore: Int = 0
    @Published var remoteCoins: Int = 0
    @Published var remoteGameOver = false

    let serverIP = "192.168.31.95"
    let serverPort = 8765

    private var myPlayerID: String = ""
    private let myDisplayName: String
    private var pendingPeerID: String? = nil

    override init() {
        var name = UIDevice.current.name
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Player" }
        if name.count > 20 { name = String(name.prefix(20)) }
        self.myDisplayName = name

        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    func connect() {
        let urlString = "ws://\(serverIP):\(serverPort)"
        guard let url = URL(string: urlString) else {
            connectionError = "Неверный адрес сервера"
            return
        }
        connectionError = nil
        resetGameState()
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
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

    func refreshPlayerList() { sendJSON(["type": "get_players"]) }
    private func sendName() { sendJSON(["type": "set_name", "name": myDisplayName]) }

    func sendInvite(to targetID: String) {
        pendingPeerID = targetID
        sendJSON(["type": "invite", "target_id": targetID])
    }

    func respondToInvite(from targetID: String, accepted: Bool) {
        if accepted {
            peerID = targetID
            isHost = false
            gameStarted = true
        }
        sendJSON(["type": "invite_response", "target_id": targetID, "accepted": accepted])
    }

    // Хост шлёт состояние гостю
    func sendGameState(enemies: [[String: Any]], bullets: [[String: Any]],
                       hostY: CGFloat, score: Int, coins: Int, gameOver: Bool) {
        guard let peer = peerID else { return }
        let payload: [String: Any] = [
            "kind": "state",
            "enemies": enemies,
            "bullets": bullets,
            "hostY": hostY,
            "score": score,
            "coins": coins,
            "gameOver": gameOver
        ]
        sendJSON(["type": "game_data", "target_id": peer, "payload": payload])
    }

    // Гость шлёт свою Y хосту
    func sendClientY(_ y: CGFloat) {
        guard let peer = peerID else { return }
        let payload: [String: Any] = ["kind": "clientY", "y": Double(y)]
        sendJSON(["type": "game_data", "target_id": peer, "payload": payload])
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
                    if self?.connectionError == nil {
                        self?.connectionError = "Сервер недоступен"
                    }
                    print("❌ WS error: \(error.localizedDescription)")
                }
            case .success(let message):
                switch message {
                case .string(let text): self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
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
            case "welcome":
                if let id = json["your_id"] as? String {
                    self.myPlayerID = id
                    self.sendName()
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
                    // Хост: приглашение принято — стартуем игру
                    if let peer = self.pendingPeerID {
                        self.peerID = peer
                        self.isHost = true
                        self.gameStarted = true
                    }
                }

            case "game_data":
                if let payload = json["payload"] as? [String: Any],
                   let kind = payload["kind"] as? String {
                    if kind == "state" && !self.isHost {
                        // Гость получает состояние от хоста
                        self.remoteEnemies = payload["enemies"] as? [[String: Any]] ?? []
                        self.remoteBullets = payload["bullets"] as? [[String: Any]] ?? []
                        if let hostY = payload["hostY"] as? Double {
                            self.remoteHeroY = CGFloat(hostY)
                        }
                        if let sc = payload["score"] as? Int { self.remoteScore = sc }
                        if let co = payload["coins"] as? Int { self.remoteCoins = co }
                        if let go = payload["gameOver"] as? Bool { self.remoteGameOver = go }
                    } else if kind == "clientY" && self.isHost {
                        // Хост получает позицию гостя
                        if let y = payload["y"] as? Double {
                            self.remoteHeroY = CGFloat(y)
                        }
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
            self.connectionError = nil
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if self.connectionError == nil {
                self.connectionError = "Соединение закрыто"
            }
        }
    }
}
