import Foundation
import UIKit

// Информация об игроке для UI
struct PlayerInfo: Identifiable, Equatable {
    let id: String      // UUID, выданный сервером
    let name: String    // Имя, которое прислал игрок
}

class NetworkManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!

    @Published var isConnected = false
    @Published var onlinePlayers: [PlayerInfo] = []
    @Published var incomingInvite: PlayerInfo? = nil
    @Published var inviteAccepted: Bool? = nil
    @Published var connectionError: String? = nil

    let serverIP = "192.168.31.95"
    let serverPort = 8765

    // ID выдаёт сервер — здесь просто храним после welcome
    private var myPlayerID: String = ""
    // Имя берём с устройства — его отправим серверу
    private let myDisplayName: String

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
        print("🎮 Имя устройства: \(myDisplayName)")
    }

    func connect() {
        let urlString = "ws://\(serverIP):\(serverPort)"
        guard let url = URL(string: urlString) else {
            connectionError = "Неверный адрес сервера"
            return
        }

        print("🔌 Подключение к \(urlString)...")
        connectionError = nil
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
        // НЕ отправляем register тут — ждём welcome от сервера
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        onlinePlayers = []
        myPlayerID = ""
    }

    func refreshPlayerList() {
        sendJSON(["type": "get_players"])
    }

    // Отправляем имя после получения welcome
    private func sendName() {
        sendJSON([
            "type": "set_name",
            "name": myDisplayName
        ])
    }

    func sendInvite(to targetID: String) {
        sendJSON(["type": "invite", "target_id": targetID])
    }

    func respondToInvite(from targetID: String, accepted: Bool) {
        sendJSON([
            "type": "invite_response",
            "target_id": targetID,
            "accepted": accepted
        ])
    }

    func sendGameData(to targetID: String, payload: [String: Any]) {
        sendJSON(["type": "game_data", "target_id": targetID, "payload": payload])
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
                // Сервер выдал нам уникальный ID
                if let id = json["your_id"] as? String {
                    self.myPlayerID = id
                    print("🎁 Получен ID от сервера: \(id)")
                    // Теперь отправляем имя — сервер нас зарегистрирует
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
                    print("👥 Онлайн: \(infos.map { "\($0.name)(\($0.id))" })")
                }

            case "invite_received":
                if let fromID = json["from_id"] as? String,
                   let fromName = json["from_name"] as? String {
                    self.incomingInvite = PlayerInfo(id: fromID, name: fromName)
                    print("📨 Приглашение от \(fromName) (\(fromID))")
                }

            case "invite_answer":
                if let accepted = json["accepted"] as? Bool {
                    self.inviteAccepted = accepted
                    print("📬 Ответ: \(accepted ? "принято" : "отклонено")")
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
            print("✅ WebSocket подключен, ждём welcome...")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if self.connectionError == nil {
                self.connectionError = "Соединение закрыто"
            }
            print("❌ WebSocket отключен")
        }
    }
}
