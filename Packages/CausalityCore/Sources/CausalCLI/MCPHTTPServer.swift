import Dispatch
import Foundation
import Network
import CausalityCore

struct MCPHTTPOptions {
    var host: String
    var port: UInt16
    var token: String
}

/// MCP 的 Streamable HTTP 传输：一个会话一个 `MCPServer`，状态不串。
///
/// 只实现 JSON 单请求 + 请求级 SSE（进度通知）；GET /mcp 目前返回 405，
/// 旧版「GET /sse 拿 POST 地址」的 transport 等有客户端明确要求再加。
final class MCPHTTPServer: @unchecked Sendable {
    private let options: MCPHTTPOptions
    private let packagePath: String?
    private let queue = DispatchQueue(label: "causal.mcp.http")
    private let sessionLock = NSLock()
    private var sessions: [String: MCPServer] = [:]
    private var listener: NWListener?

    init(options: MCPHTTPOptions, packagePath: String?) {
        self.options = options
        self.packagePath = packagePath
    }

    func run() -> Int32 {
        guard !options.token.isEmpty else {
            log(CoreText.text("HTTP 传输需要 token：设置 CAUSAL_MCP_TOKEN，或传 --token / --token-file"))
            return 2
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: options.port) else {
            log(CoreText.format("端口不正确：%lld", Int(options.port)))
            return 2
        }
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(options.host), port: port)
        do {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let actual = self.listener?.port?.rawValue ?? self.options.port
                    self.log(CoreText.format("MCP HTTP 监听 http://%@:%lld/mcp", self.options.host, Int(actual)))
                case let .failed(error):
                    self.log(CoreText.format("HTTP 监听失败：%@", "\(error)"))
                    exit(1)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        } catch {
            log(CoreText.format("HTTP 监听失败：%@", "\(error)"))
            return 1
        }
        dispatchMain()
    }

    // MARK: - 连接与 HTTP 解析

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let data, !data.isEmpty { next.append(data) }
            switch self.parseRequest(next) {
            case let .request(request):
                self.handle(request, on: connection)
            case let .failure(status, message):
                self.sendError(connection, status: status, code: -32600, message: message)
            case .incomplete:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: next)
                }
            }
        }
    }

    private struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    private enum ParseResult {
        case incomplete
        case failure(Int, String)
        case request(Request)
    }

    private func parseRequest(_ data: Data) -> ParseResult {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: delimiter) else {
            return data.count > 64 * 1024 ? .failure(431, CoreText.text("请求头太大")) : .incomplete
        }
        let headerLength = data.distance(from: data.startIndex, to: headerEnd.lowerBound)
        guard headerLength <= 64 * 1024 else { return .failure(431, CoreText.text("请求头太大")) }
        guard let headerText = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .failure(400, CoreText.text("请求头不是 UTF-8"))
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .failure(400, CoreText.text("空请求")) }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return .failure(400, CoreText.text("请求行不完整")) }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? target
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil {
            return .failure(411, CoreText.text("暂不支持分块传输，请带 Content-Length"))
        }
        if method == "POST", headers["content-length"] == nil {
            return .failure(411, CoreText.text("缺少 Content-Length"))
        }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else {
            return .failure(400, CoreText.text("Content-Length 不正确"))
        }
        guard length <= 8 * 1024 * 1024 else { return .failure(413, CoreText.text("请求体太大")) }
        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= length else { return .incomplete }
        let bodyEnd = data.index(bodyStart, offsetBy: length)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        return .request(Request(method: method, path: path, headers: headers, body: body))
    }

    // MARK: - 路由

    private func handle(_ request: Request, on connection: NWConnection) {
        if request.method == "GET", request.path == "/health" {
            sendResponse(
                connection,
                status: 200,
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data("ok".utf8)
            )
            return
        }
        guard request.path == "/mcp" else {
            sendError(connection, status: 404, code: -32000, message: "not found")
            return
        }
        guard authorized(request.headers) else {
            sendError(
                connection,
                status: 401,
                code: -32000,
                message: "unauthorized",
                headers: ["WWW-Authenticate": "Bearer"]
            )
            return
        }
        switch request.method {
        case "POST":
            handlePost(request, on: connection)
        case "DELETE":
            handleDelete(request, on: connection)
        case "GET":
            sendError(
                connection,
                status: 405,
                code: -32000,
                message: CoreText.text("GET /mcp 暂不支持；进度用 POST 的 SSE 响应"),
                headers: ["Allow": "POST, DELETE"]
            )
        default:
            sendError(
                connection,
                status: 405,
                code: -32000,
                message: "method not allowed",
                headers: ["Allow": "POST, DELETE"]
            )
        }
    }

    private func handlePost(_ request: Request, on connection: NWConnection) {
        let contentType = request.headers["content-type"]?.lowercased() ?? ""
        guard contentType.contains("application/json") else {
            sendError(connection, status: 415, code: -32000, message: CoreText.text("Content-Type 要是 application/json"))
            return
        }
        guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            sendError(connection, status: 400, code: -32700, message: "Parse error")
            return
        }
        let method = object["method"] as? String ?? ""
        let id = object["id"]

        if method == "initialize" {
            let (sessionID, server) = createSession()
            process(server, body: request.body, sessionID: sessionID, on: connection, accept: request.headers["accept"] ?? "")
            return
        }

        guard let sessionID = request.headers["mcp-session-id"], let server = session(sessionID) else {
            sendError(connection, status: 404, code: -32000, message: "unknown session")
            return
        }

        if method == "notifications/cancelled" {
            let params = object["params"] as? [String: Any] ?? [:]
            server.cancel(requestID: params["requestId"])
            sendResponse(connection, status: 202, headers: ["Mcp-Session-Id": sessionID])
            return
        }
        if id == nil || method.hasPrefix("notifications/") {
            sendResponse(connection, status: 202, headers: ["Mcp-Session-Id": sessionID])
            return
        }
        process(server, body: request.body, sessionID: sessionID, on: connection, accept: request.headers["accept"] ?? "")
    }

    private func handleDelete(_ request: Request, on connection: NWConnection) {
        guard let sessionID = request.headers["mcp-session-id"], removeSession(sessionID) else {
            sendError(connection, status: 404, code: -32000, message: "unknown session")
            return
        }
        sendResponse(connection, status: 204, headers: ["Mcp-Session-Id": sessionID])
    }

    private func process(
        _ server: MCPServer,
        body: Data,
        sessionID: String,
        on connection: NWConnection,
        accept: String
    ) {
        if accept.contains("text/event-stream") {
            beginSSE(connection, sessionID: sessionID)
            server.handleRequest(body, emit: { [weak self] message in
                self?.sendSSE(connection, message)
            }, completion: { [weak self] in
                self?.finishSSE(connection)
            })
            return
        }

        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var messages: [Data] = []

            func append(_ data: Data) {
                lock.lock()
                messages.append(data)
                lock.unlock()
            }

            func response() -> Data? {
                lock.lock()
                let snapshot = messages
                lock.unlock()
                return snapshot.last { data in
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return false
                    }
                    if object["id"] == nil { return false }
                    return !(object["id"] is NSNull)
                } ?? snapshot.last
            }
        }

        let collector = Collector()
        server.handleRequest(body, emit: { data in
            collector.append(data)
        }, completion: { [weak self] in
            guard let self else { return }
            if let response = collector.response() {
                self.sendResponse(
                    connection,
                    status: 200,
                    headers: [
                        "Content-Type": "application/json; charset=utf-8",
                        "Mcp-Session-Id": sessionID,
                    ],
                    body: response
                )
            } else {
                self.sendResponse(connection, status: 202, headers: ["Mcp-Session-Id": sessionID])
            }
        })
    }

    // MARK: - 会话

    private func createSession() -> (String, MCPServer) {
        let sessionID = UUID().uuidString
        let server = MCPServer(packagePath: packagePath)
        sessionLock.lock()
        sessions[sessionID] = server
        sessionLock.unlock()
        return (sessionID, server)
    }

    private func session(_ sessionID: String) -> MCPServer? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessions[sessionID]
    }

    private func removeSession(_ sessionID: String) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return sessions.removeValue(forKey: sessionID) != nil
    }

}

private extension MCPHTTPServer {
    // MARK: - 鉴权与响应

    private func authorized(_ headers: [String: String]) -> Bool {
        guard let raw = headers["authorization"] else { return false }
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return secureEqual(String(parts[1]), options.token)
    }

    /// 固定长度比较，避免按字符提前退出。
    private func secureEqual(_ lhs: String, _ rhs: String) -> Bool {
        let leftBytes = Array(lhs.utf8)
        let rightBytes = Array(rhs.utf8)
        var difference = leftBytes.count ^ rightBytes.count
        let count = max(leftBytes.count, rightBytes.count)
        for index in 0..<count {
            let left = index < leftBytes.count ? leftBytes[index] : 0
            let right = index < rightBytes.count ? rightBytes[index] : 0
            difference |= Int(left ^ right)
        }
        return difference == 0
    }

    private func sendError(
        _ connection: NWConnection,
        status: Int,
        code: Int,
        message: String,
        headers: [String: String] = [:]
    ) {
        sendJSON(
            connection,
            status: status,
            object: [
                "jsonrpc": "2.0",
                "id": NSNull(),
                "error": ["code": code, "message": message],
            ],
            headers: headers
        )
    }

    private func sendJSON(
        _ connection: NWConnection,
        status: Int,
        object: Any,
        sessionID: String? = nil,
        headers: [String: String] = [:]
    ) {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
        var all = headers
        all["Content-Type"] = "application/json; charset=utf-8"
        if let sessionID { all["Mcp-Session-Id"] = sessionID }
        sendResponse(connection, status: status, headers: all, body: body)
    }

    private func sendResponse(
        _ connection: NWConnection,
        status: Int,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        var all = headers
        all["Content-Length"] = "\(body.count)"
        all["Connection"] = "close"
        if all["Content-Type"] == nil {
            all["Content-Type"] = "application/json; charset=utf-8"
        }
        var head = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (key, value) in all {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        case 431: "Request Header Fields Too Large"
        default: "Error"
        }
    }

    private func beginSSE(_ connection: NWConnection, sessionID: String) {
        let head = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: close\r\n"
            + "Mcp-Session-Id: \(sessionID)\r\n"
            + "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
    }

    private func sendSSE(_ connection: NWConnection, _ message: Data) {
        let text = String(decoding: message, as: UTF8.self)
        let chunk = "event: message\ndata: \(text)\n\n"
        connection.send(content: Data(chunk.utf8), completion: .contentProcessed { _ in })
    }

    private func finishSSE(_ connection: NWConnection) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data(("[causal] " + message + "\n").utf8))
    }
}
