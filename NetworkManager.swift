import Foundation
import UIKit

class NetworkManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!

    @Published var isConnected = false
    @Published var onlinePlayers: [String] = []
    @Published var incomingInvite: String? = nil
    @Published var inviteAccepted: Bool? = nil
    @Published var connectionError: String? = nil

    // ← ЗДЕСЬ IP ТВОЕГО ПК
    let serverIP = "192.168.31.95"
    let serverPort = 8765

    private var myPlayerID: String

    override init() {
        // Имя игрока — из настроек устройства, но можно захардкодить для теста
        let deviceName = UIDevice.current.name
        // Ограничиваем 20 символами и убираем спецсимволы
        self.myPlayerID = deviceName
            .replacingOccurrences(of: "'", with: "")
            .prefix(20)
            .trimmingCharacters(in: .whitespaces)
        if myPlayerID.isEmpty { myPlayerID = "Player" }

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

        print("🔌 Подключение к \(urlString)...")
        connectionError = nil
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        registerPlayer()
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // Периодически обновляем список игроков
    func refreshPlayerList() {
        sendJSON(["type": "get_players"])
    }

    private func registerPlayer() {
        sendJSON(["type": "register", "player_id": myPlayerID])
    }

    func sendInvite(to targetID: String) {
        sendJSON(["type": "invite", "target_id": targetID])
    }

    func respondToInvite(from targetID: String, accepted: Bool) {
        sendJSON(["type": "invite_response", "target_id": targetID, "accepted": accepted])
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
                    print("❌ WebSocket error: \(error.localizedDescription)")
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
            case "player_list":
                if let players = json["players"] as? [[String: Any]] {
                    let ids = players.compactMap { $0["id"] as? String }
                    self.onlinePlayers = ids.filter { $0 != self.myPlayerID }
                    print("👥 Онлайн: \(self.onlinePlayers)")
                }
            case "invite_received":
                if let fromID = json["from_id"] as? String {
                    self.incomingInvite = fromID
                    print("📨 Приглашение от \(fromID)")
                }
            case "invite_answer":
                if let accepted = json["accepted"] as? Bool {
                    self.inviteAccepted = accepted
                    print("📬 Ответ: \(accepted ? "принято" : "отклонено")")
                }
            case "game_data":
                break
            default: break
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
            print("✅ WebSocket подключен")
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
