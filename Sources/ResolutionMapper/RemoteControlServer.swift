import Darwin
import Foundation
import Network

struct RemoteControlState: Codable {
    let dimmingEnabled: Bool
    let dimmingAmount: Double
    let volume: Int
}

@MainActor
final class RemoteControlServer {
    private let token: String
    private let stateProvider: () -> RemoteControlState
    private let dimmingHandler: (Bool, Double) -> Void
    private let volumeHandler: (Int) -> Void
    private let mediaHandler: (RemoteMediaAction) -> Void
    private let queue = DispatchQueue(label: "local.codex.resolutionmapper.remote")
    private var listener: NWListener?
    private var port: UInt16

    var onEndpointChanged: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    init(
        token: String,
        preferredPort: UInt16 = 49491,
        stateProvider: @escaping () -> RemoteControlState,
        dimmingHandler: @escaping (Bool, Double) -> Void,
        volumeHandler: @escaping (Int) -> Void,
        mediaHandler: @escaping (RemoteMediaAction) -> Void
    ) {
        self.token = token
        self.port = preferredPort
        self.stateProvider = stateProvider
        self.dimmingHandler = dimmingHandler
        self.volumeHandler = volumeHandler
        self.mediaHandler = mediaHandler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        } catch {
            listener = try NWListener(using: parameters, on: .any)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleListenerState(state)
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func urlString() -> String {
        "http://\(Self.localIPv4Address() ?? "localhost"):\(port)/?token=\(token)"
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let rawPort = listener?.port?.rawValue {
                port = rawPort
            }
            onEndpointChanged?(urlString())
            onStatusChanged?("Phone remote ready.")
        case .failed(let error):
            onStatusChanged?("Phone remote failed: \(error.localizedDescription)")
            stop()
        case .cancelled:
            onStatusChanged?("Phone remote stopped.")
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            Task { @MainActor in
                self?.respond(to: connection, data: data)
            }
        }
    }

    private func respond(to connection: NWConnection, data: Data?) {
        let request = data.flatMap(parseRequest)
        let response = handle(request)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func handle(_ request: HTTPRequest?) -> Data {
        guard let request else {
            return response(status: "400 Bad Request", body: "Bad request")
        }

        if request.method == "OPTIONS" {
            return response(status: "204 No Content", body: "")
        }

        if request.path == "/favicon.ico" {
            return response(status: "204 No Content", body: "")
        }

        guard request.query["token"] == token else {
            return response(status: "403 Forbidden", body: "Forbidden")
        }

        switch (request.method, request.path) {
        case ("GET", "/"):
            return response(contentType: "text/html", body: htmlPage())
        case ("GET", "/api/state"):
            return jsonResponse(stateProvider())
        case ("POST", "/api/dim"):
            let enabled = request.query["enabled"] == "1" || request.query["enabled"] == "true"
            let amount = Double(request.query["amount"] ?? "") ?? stateProvider().dimmingAmount
            dimmingHandler(enabled, amount)
            return jsonResponse(stateProvider())
        case ("POST", "/api/volume"):
            if let value = Int(request.query["value"] ?? "") {
                volumeHandler(Swift.max(0, Swift.min(100, value)))
            }
            return jsonResponse(stateProvider())
        case ("POST", "/api/media"):
            if let rawAction = request.query["action"],
               let action = RemoteMediaAction(rawValue: rawAction) {
                mediaHandler(action)
            }
            return jsonResponse(stateProvider())
        default:
            return response(status: "404 Not Found", body: "Not found")
        }
    }

    private func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2,
              let url = URL(string: "http://resolutionmapper.local\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        return HTTPRequest(method: parts[0], path: components.path, query: query)
    }

    private func jsonResponse<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
        return response(contentType: "application/json", body: body)
    }

    private func response(status: String = "200 OK", contentType: String = "text/plain", body: String) -> Data {
        let bodyData = Data(body.utf8)
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Connection: close\r
        \r

        """
        var data = Data(headers.utf8)
        data.append(bodyData)
        return data
    }

    private func htmlPage() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Resolution Mapper Remote</title>
          <style>
            :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
            * { box-sizing: border-box; }
            body {
              min-height: 100vh; margin: 0; padding: 22px;
              background: radial-gradient(circle at 20% 0%, #1c3b4a 0, transparent 34%), linear-gradient(145deg, #090b10, #141821 52%, #101114);
              color: white;
            }
            .shell { max-width: 520px; margin: 0 auto; }
            header { display: flex; align-items: center; gap: 14px; margin-bottom: 20px; }
            .mark { width: 52px; height: 52px; border-radius: 14px; background: linear-gradient(135deg, #37d8ff, #18e0b4); position: relative; box-shadow: 0 14px 42px #00ddff38; }
            .mark:before, .mark:after { content: ""; position: absolute; border: 3px solid #071018; border-radius: 5px; }
            .mark:before { width: 28px; height: 19px; left: 9px; top: 12px; }
            .mark:after { width: 24px; height: 17px; right: 6px; bottom: 9px; }
            h1 { font-size: 24px; line-height: 1.05; margin: 0; }
            p { margin: 4px 0 0; color: #aeb5c0; }
            section { background: #ffffff14; border: 1px solid #ffffff17; border-radius: 14px; padding: 16px; margin: 14px 0; box-shadow: inset 0 1px 0 #ffffff10; }
            .row { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
            .label { font-weight: 750; }
            .value { color: #bfc6d3; font-variant-numeric: tabular-nums; }
            input[type="range"] { width: 100%; accent-color: #27d8d2; }
            input[type="checkbox"] { width: 48px; height: 28px; accent-color: #27d8d2; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
            button {
              min-height: 54px; border: 0; border-radius: 12px; color: #071018;
              background: linear-gradient(135deg, #42d9ff, #20e5ba);
              font: inherit; font-weight: 800; box-shadow: 0 12px 26px #00e1ff22;
            }
            button.secondary { background: #ffffff18; color: white; box-shadow: none; border: 1px solid #ffffff18; }
            button:active { transform: translateY(1px); filter: brightness(.88); }
            .burst { position: fixed; width: 10px; height: 10px; border-radius: 999px; background: #ff5ca8; pointer-events: none; animation: pop .8s ease-out forwards; }
            @keyframes pop { to { opacity: 0; transform: translate(var(--x), var(--y)) scale(2.6); } }
          </style>
        </head>
        <body>
          <main class="shell">
            <header>
              <div class="mark" id="mark"></div>
              <div><h1>Resolution Mapper</h1><p>Mac comfort remote</p></div>
            </header>
            <section>
              <div class="row"><span class="label">Dim below minimum</span><input id="dimEnabled" type="checkbox"></div>
              <div class="row"><span class="value" id="dimValue">0%</span></div>
              <input id="dimAmount" type="range" min="0" max="85" value="35">
            </section>
            <section>
              <div class="row"><span class="label">Volume</span><span class="value" id="volumeValue">0%</span></div>
              <input id="volume" type="range" min="0" max="100" value="50">
            </section>
            <section>
              <div class="grid">
                <button class="secondary" data-action="previous">Prev</button>
                <button data-action="playPause">Play</button>
                <button class="secondary" data-action="next">Next</button>
                <button class="secondary" data-action="volumeDown">Vol -</button>
                <button class="secondary" data-action="mute">Mute</button>
                <button class="secondary" data-action="volumeUp">Vol +</button>
              </div>
            </section>
          </main>
          <script>
            const token = new URLSearchParams(location.search).get("token") || "";
            const dimEnabled = document.getElementById("dimEnabled");
            const dimAmount = document.getElementById("dimAmount");
            const dimValue = document.getElementById("dimValue");
            const volume = document.getElementById("volume");
            const volumeValue = document.getElementById("volumeValue");
            const api = (path, method = "POST") => fetch(path + (path.includes("?") ? "&" : "?") + "token=" + encodeURIComponent(token), { method });
            const updateLabels = () => {
              dimValue.textContent = dimAmount.value + "%";
              volumeValue.textContent = volume.value + "%";
            };
            let dimTimer, volumeTimer, taps = 0;
            async function loadState() {
              const res = await api("/api/state", "GET");
              if (!res.ok) return;
              const state = await res.json();
              dimEnabled.checked = state.dimmingEnabled;
              dimAmount.value = Math.round(state.dimmingAmount * 100);
              volume.value = state.volume;
              updateLabels();
            }
            function sendDim() {
              updateLabels();
              clearTimeout(dimTimer);
              dimTimer = setTimeout(() => api("/api/dim?enabled=" + (dimEnabled.checked ? "1" : "0") + "&amount=" + (Number(dimAmount.value) / 100)), 80);
            }
            function sendVolume() {
              updateLabels();
              clearTimeout(volumeTimer);
              volumeTimer = setTimeout(() => api("/api/volume?value=" + volume.value), 80);
            }
            dimEnabled.addEventListener("change", sendDim);
            dimAmount.addEventListener("input", sendDim);
            volume.addEventListener("input", sendVolume);
            document.querySelectorAll("[data-action]").forEach(button => button.addEventListener("click", () => api("/api/media?action=" + button.dataset.action)));
            document.getElementById("mark").addEventListener("click", event => {
              taps += 1;
              if (taps < 7) return;
              taps = 0;
              for (let i = 0; i < 18; i++) {
                const dot = document.createElement("i");
                dot.className = "burst";
                dot.style.left = event.clientX + "px";
                dot.style.top = event.clientY + "px";
                dot.style.setProperty("--x", (Math.cos(i / 18 * Math.PI * 2) * 120) + "px");
                dot.style.setProperty("--y", (Math.sin(i / 18 * Math.PI * 2) * 120) + "px");
                document.body.appendChild(dot);
                setTimeout(() => dot.remove(), 900);
              }
            });
            loadState();
          </script>
        </body>
        </html>
        """
    }

    private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(socketAddress.pointee.sa_len)
            let result = getnameinfo(
                socketAddress,
                length,
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let host = String(cString: hostname)
            if name == "en0" || name == "en1" {
                return host
            }
            address = address ?? host
        }

        return address
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
}
