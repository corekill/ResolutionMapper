import Darwin
import Foundation
import Network

struct RemoteDimmingDisplay: Codable {
    let id: UInt32
    let name: String
    let amount: Double
    let selected: Bool
}

struct RemoteControlState: Codable {
    let dimmingEnabled: Bool
    let selectedDimmingDisplayID: UInt32?
    let dimmingDisplays: [RemoteDimmingDisplay]
    let volume: Int
}

struct RemoteDevice: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let authorizedAt: Date
}

struct PendingRemotePairing {
    let deviceID: String
    let name: String
    let code: String
}

private struct PairingStartResponse: Codable {
    let authorized: Bool
    let code: String?
}

private struct PairingStatusResponse: Codable {
    let authorized: Bool
}

@MainActor
final class RemoteControlServer {
    private let stateProvider: () -> RemoteControlState
    private let dimmingHandler: (UInt32?, Bool, Double) -> Void
    private let volumeHandler: (Int) -> Void
    private let volumeDeltaHandler: (Int) -> Void
    private let mediaHandler: (RemoteMediaAction) -> Void
    private let isDeviceAuthorized: (String) -> Bool
    private let pairingRequestHandler: (PendingRemotePairing?) -> Void
    private let queue = DispatchQueue(label: "local.codex.resolutionmapper.remote")
    private var listener: NWListener?
    private var port: UInt16
    private var pendingPairings: [String: PendingRemotePairing] = [:]

    var onEndpointChanged: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    init(
        preferredPort: UInt16 = 49491,
        stateProvider: @escaping () -> RemoteControlState,
        dimmingHandler: @escaping (UInt32?, Bool, Double) -> Void,
        volumeHandler: @escaping (Int) -> Void,
        volumeDeltaHandler: @escaping (Int) -> Void,
        mediaHandler: @escaping (RemoteMediaAction) -> Void,
        isDeviceAuthorized: @escaping (String) -> Bool,
        pairingRequestHandler: @escaping (PendingRemotePairing?) -> Void
    ) {
        self.port = preferredPort
        self.stateProvider = stateProvider
        self.dimmingHandler = dimmingHandler
        self.volumeHandler = volumeHandler
        self.volumeDeltaHandler = volumeDeltaHandler
        self.mediaHandler = mediaHandler
        self.isDeviceAuthorized = isDeviceAuthorized
        self.pairingRequestHandler = pairingRequestHandler
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
        clearPairingRequests()
    }

    func pairingURLString() -> String {
        "http://\(Self.localIPv4Address() ?? "localhost"):\(port)/pair"
    }

    func approvePairingCode(_ code: String) -> RemoteDevice? {
        let normalizedCode = code.filter(\.isNumber)
        guard let match = pendingPairings.values.first(where: { $0.code == normalizedCode }) else {
            return nil
        }

        pendingPairings.removeValue(forKey: match.deviceID)
        pairingRequestHandler(pendingPairings.values.first)

        return RemoteDevice(
            id: match.deviceID,
            name: match.name,
            authorizedAt: Date()
        )
    }

    func clearPairingRequests() {
        pendingPairings.removeAll()
        pairingRequestHandler(nil)
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let rawPort = listener?.port?.rawValue {
                port = rawPort
            }
            onEndpointChanged?(pairingURLString())
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

        switch (request.method, request.path) {
        case ("GET", "/pair"):
            return response(contentType: "text/html", body: pairingPage())
        case ("GET", "/api/pair/start"):
            return jsonResponse(startPairing(request))
        case ("GET", "/api/pair/status"):
            let deviceID = request.query["device"] ?? ""
            return jsonResponse(PairingStatusResponse(authorized: isDeviceAuthorized(deviceID)))
        case ("GET", "/"):
            return response(contentType: "text/html", body: remotePage())
        default:
            break
        }

        guard let deviceID = request.query["device"], isDeviceAuthorized(deviceID) else {
            return jsonResponse(status: "403 Forbidden", ["error": "not_authorized"])
        }

        switch (request.method, request.path) {
        case ("GET", "/api/state"):
            return jsonResponse(stateProvider())
        case ("POST", "/api/dim"):
            let enabled = request.query["enabled"] == "1" || request.query["enabled"] == "true"
            let amount = Double(request.query["amount"] ?? "") ?? selectedDimmingAmount()
            let displayID = UInt32(request.query["displayID"] ?? "")
            dimmingHandler(displayID, enabled, amount)
            return jsonResponse(stateProvider())
        case ("POST", "/api/volume"):
            if let delta = Int(request.query["delta"] ?? "") {
                volumeDeltaHandler(delta)
            } else if let value = Int(request.query["value"] ?? "") {
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

    private func startPairing(_ request: HTTPRequest) -> PairingStartResponse {
        guard let deviceID = request.query["device"], !deviceID.isEmpty else {
            return PairingStartResponse(authorized: false, code: nil)
        }

        if isDeviceAuthorized(deviceID) {
            pendingPairings.removeValue(forKey: deviceID)
            return PairingStartResponse(authorized: true, code: nil)
        }

        if let pending = pendingPairings[deviceID] {
            pairingRequestHandler(pending)
            return PairingStartResponse(authorized: false, code: pending.code)
        }

        let pairing = PendingRemotePairing(
            deviceID: deviceID,
            name: sanitizedDeviceName(request.query["name"]),
            code: makePairingCode()
        )
        pendingPairings[deviceID] = pairing
        pairingRequestHandler(pairing)
        return PairingStartResponse(authorized: false, code: pairing.code)
    }

    private func selectedDimmingAmount() -> Double {
        let state = stateProvider()
        return state.dimmingDisplays.first(where: { $0.selected })?.amount ?? 0
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

    private func jsonResponse<T: Encodable>(status: String = "200 OK", _ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
        return response(status: status, contentType: "application/json", body: body)
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

    private func remotePage() -> String {
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
            body { min-height: 100vh; margin: 0; padding: 22px; background: radial-gradient(circle at 20% 0%, #1c3b4a 0, transparent 34%), linear-gradient(145deg, #090b10, #141821 52%, #101114); color: white; }
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
            select { width: 100%; min-height: 42px; border: 1px solid #ffffff18; border-radius: 10px; color: white; background: #ffffff14; padding: 0 10px; font: inherit; margin-bottom: 12px; }
            input[type="range"] { width: 100%; accent-color: #27d8d2; }
            input[type="checkbox"] { width: 48px; height: 28px; accent-color: #27d8d2; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
            button { min-height: 54px; border: 0; border-radius: 12px; color: #071018; background: linear-gradient(135deg, #42d9ff, #20e5ba); font: inherit; font-weight: 800; box-shadow: 0 12px 26px #00e1ff22; }
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
              <select id="dimDisplay"></select>
              <div class="row"><span class="value" id="dimValue">0%</span></div>
              <input id="dimAmount" type="range" min="0" max="85" value="0">
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
                <button class="secondary" data-volume-delta="-5">Vol -</button>
                <button class="secondary" data-action="mute">Mute</button>
                <button class="secondary" data-volume-delta="5">Vol +</button>
              </div>
            </section>
          </main>
          <script>
            const deviceKey = "resolutionMapperDeviceId";
            const device = localStorage.getItem(deviceKey);
            if (!device) location.replace("/pair");
            const dimEnabled = document.getElementById("dimEnabled");
            const dimDisplay = document.getElementById("dimDisplay");
            const dimAmount = document.getElementById("dimAmount");
            const dimValue = document.getElementById("dimValue");
            const volume = document.getElementById("volume");
            const volumeValue = document.getElementById("volumeValue");
            let state = null, dimTimer, volumeTimer, taps = 0;
            const api = (path, method = "POST") => fetch(path + (path.includes("?") ? "&" : "?") + "device=" + encodeURIComponent(device), { method });
            const selectedDisplay = () => state?.dimmingDisplays?.find(display => String(display.id) === String(dimDisplay.value));
            function applyState(next) {
              state = next;
              dimEnabled.checked = state.dimmingEnabled;
              dimDisplay.innerHTML = "";
              state.dimmingDisplays.forEach(display => {
                const option = document.createElement("option");
                option.value = display.id;
                option.textContent = display.name;
                dimDisplay.appendChild(option);
              });
              const selected = state.dimmingDisplays.find(display => display.selected) || state.dimmingDisplays[0];
              if (selected) dimDisplay.value = selected.id;
              updateSelectedDim();
              volume.value = state.volume;
              updateLabels();
            }
            function updateSelectedDim() {
              const display = selectedDisplay();
              if (display) dimAmount.value = Math.round(display.amount * 100);
              updateLabels();
            }
            function updateLabels() {
              dimValue.textContent = dimAmount.value + "%";
              volumeValue.textContent = volume.value + "%";
            }
            async function loadState() {
              const res = await api("/api/state", "GET");
              if (res.status === 403) {
                location.replace("/pair");
                return;
              }
              if (!res.ok) return;
              applyState(await res.json());
            }
            function sendDim() {
              updateLabels();
              clearTimeout(dimTimer);
              dimTimer = setTimeout(async () => {
                const res = await api("/api/dim?enabled=" + (dimEnabled.checked ? "1" : "0") + "&displayID=" + encodeURIComponent(dimDisplay.value) + "&amount=" + (Number(dimAmount.value) / 100));
                if (res.ok) applyState(await res.json());
              }, 80);
            }
            function sendVolume() {
              updateLabels();
              clearTimeout(volumeTimer);
              volumeTimer = setTimeout(async () => {
                const res = await api("/api/volume?value=" + volume.value);
                if (res.ok) applyState(await res.json());
              }, 80);
            }
            dimEnabled.addEventListener("change", sendDim);
            dimDisplay.addEventListener("change", updateSelectedDim);
            dimAmount.addEventListener("input", sendDim);
            volume.addEventListener("input", sendVolume);
            document.querySelectorAll("[data-volume-delta]").forEach(button => button.addEventListener("click", async () => {
              const res = await api("/api/volume?delta=" + button.dataset.volumeDelta);
              if (res.ok) applyState(await res.json());
            }));
            document.querySelectorAll("[data-action]").forEach(button => button.addEventListener("click", async () => {
              const res = await api("/api/media?action=" + button.dataset.action);
              if (res.ok) applyState(await res.json());
              setTimeout(loadState, 250);
            }));
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

    private func pairingPage() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Pair Resolution Mapper</title>
          <style>
            :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
            body { min-height: 100vh; margin: 0; display: grid; place-items: center; padding: 24px; background: linear-gradient(145deg, #080a0f, #151923); color: white; }
            main { width: min(420px, 100%); background: #ffffff14; border: 1px solid #ffffff18; border-radius: 16px; padding: 24px; text-align: center; }
            h1 { margin: 0 0 8px; font-size: 26px; }
            p { color: #aeb5c0; margin: 0 0 18px; }
            .code { font-size: 52px; font-weight: 900; letter-spacing: 8px; font-variant-numeric: tabular-nums; padding: 16px; border-radius: 14px; background: #ffffff16; margin: 18px 0; }
            .small { font-size: 14px; }
          </style>
        </head>
        <body>
          <main>
            <h1>Pair Phone</h1>
            <p>Enter this code in Resolution Mapper on your Mac.</p>
            <div class="code" id="code">----</div>
            <p class="small" id="state">Waiting for Mac authorization...</p>
          </main>
          <script>
            const key = "resolutionMapperDeviceId";
            let device = localStorage.getItem(key);
            if (!device) {
              device = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2);
              localStorage.setItem(key, device);
            }
            const name = navigator.userAgent.includes("iPhone") ? "iPhone" : navigator.userAgent.includes("Android") ? "Android phone" : "Phone";
            const code = document.getElementById("code");
            const state = document.getElementById("state");
            async function start() {
              const res = await fetch("/api/pair/start?device=" + encodeURIComponent(device) + "&name=" + encodeURIComponent(name));
              const data = await res.json();
              if (data.authorized) {
                location.replace("/");
                return;
              }
              code.textContent = data.code || "----";
              poll();
            }
            async function poll() {
              const res = await fetch("/api/pair/status?device=" + encodeURIComponent(device));
              const data = await res.json();
              if (data.authorized) {
                state.textContent = "Authorized.";
                location.replace("/");
                return;
              }
              setTimeout(poll, 1200);
            }
            start();
          </script>
        </body>
        </html>
        """
    }

    private func sanitizedDeviceName(_ rawName: String?) -> String {
        let trimmed = (rawName ?? "Phone").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(48)).isEmpty ? "Phone" : String(trimmed.prefix(48))
    }

    private func makePairingCode() -> String {
        var code: String
        repeat {
            code = String(Int.random(in: 1000...9999))
        } while pendingPairings.values.contains(where: { $0.code == code })
        return code
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
