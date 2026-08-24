import SwiftUI

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var deviceState: DeviceState = .noDevice
    @Published var devices: [Device] = []
    @Published var selectedSerial: String?
    @Published var currentPath = "/sdcard"
    @Published var files: [RemoteFile] = []
    @Published var selection = Set<RemoteFile.ID>()
    @Published var isLoading = false
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    @Published var storageSummary = ""

    private var adb: ADB?
    private var pollTask: Task<Void, Never>?

    var currentDevice: Device? {
        devices.first { $0.serial == selectedSerial }
    }

    var pathComponents: [(name: String, path: String)] {
        var result: [(String, String)] = [("/", "/")]
        var acc = ""
        for part in currentPath.split(separator: "/") {
            acc += "/\(part)"
            result.append((String(part), acc))
        }
        return result
    }

    func start() {
        adb = ADB.locate()
        guard adb != nil else {
            deviceState = .adbMissing
            return
        }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshDevices()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    // MARK: - Device detection

    func refreshDevices() async {
        guard let adb else { return }
        guard let result = try? await adb.run(["devices"]) else { return }

        var found: [Device] = []
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            found.append(Device(serial: String(parts[0]), state: String(parts[1])))
        }

        // Keep models we already fetched.
        for i in found.indices {
            if let existing = devices.first(where: { $0.serial == found[i].serial }) {
                found[i].model = existing.model
            }
        }
        devices = found

        if selectedSerial == nil || !found.contains(where: { $0.serial == selectedSerial }) {
            selectedSerial = found.first(where: { $0.state == "device" })?.serial ?? found.first?.serial
        }

        let previousState = deviceState
        if let device = currentDevice {
            deviceState = device.state == "device" ? .ready
                        : device.state == "unauthorized" ? .unauthorized
                        : .noDevice
        } else {
            deviceState = .noDevice
        }

        if deviceState == .ready && previousState != .ready {
            await onDeviceConnected()
        }
        if deviceState != .ready && previousState == .ready {
            files = []
            selection = []
            storageSummary = ""
        }
    }

    private func onDeviceConnected() async {
        guard let adb, let serial = selectedSerial else { return }
        if let result = try? await adb.run(["-s", serial, "shell", "getprop", "ro.product.model"]) {
            let model = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = devices.firstIndex(where: { $0.serial == serial }) {
                devices[i].model = model
            }
        }
        await refreshStorage()
        currentPath = "/sdcard"
        await loadDirectory()
    }

    func selectDevice(_ serial: String) {
        selectedSerial = serial
        Task {
            await refreshDevices()
            if deviceState == .ready { await onDeviceConnected() }
        }
    }

    private func refreshStorage() async {
        guard let adb, let serial = selectedSerial else { return }
        guard let result = try? await adb.run(["-s", serial, "shell", "df", "-h", "/sdcard"]) else { return }
        let lines = result.stdout.split(separator: "\n")
        if lines.count >= 2 {
            let fields = lines[1].split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 4 {
                storageSummary = "\(fields[2]) used · \(fields[3]) free"
            }
        }
    }

    // MARK: - Browsing

    func loadDirectory() async {
        guard let adb, let serial = selectedSerial, deviceState == .ready else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await adb.runChecked(
                ["-s", serial, "shell", "ls", "-lA", ADB.shellQuoted(currentPath)]
            )
            files = LsParser.parse(output: result.stdout, parentPath: currentPath)
            selection = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigate(to path: String) {
        currentPath = path.isEmpty ? "/" : path
        Task { await loadDirectory() }
    }

    func open(_ file: RemoteFile) {
        if file.isDirectory {
            navigate(to: file.path)
        } else {
            Task { await downloadAndOpen(file) }
        }
    }

    func goUp() {
        guard currentPath != "/" else { return }
        navigate(to: (currentPath as NSString).deletingLastPathComponent)
    }

    var selectedFiles: [RemoteFile] {
        files.filter { selection.contains($0.id) }
    }

    // MARK: - File operations

    func download(_ items: [RemoteFile], to directory: URL) async {
        guard let adb, let serial = selectedSerial else { return }
        for (index, item) in items.enumerated() {
            busyMessage = "Downloading \(item.name) (\(index + 1)/\(items.count))…"
            do {
                try await adb.runChecked(["-s", serial, "pull", item.path, directory.path])
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
                break
            }
        }
        busyMessage = nil
        NSWorkspace.shared.activateFileViewerSelecting(
            [directory.appendingPathComponent(items.first?.name ?? "")]
        )
    }

    private func downloadAndOpen(_ file: RemoteFile) async {
        guard let adb, let serial = selectedSerial else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidDrive", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        busyMessage = "Opening \(file.name)…"
        defer { busyMessage = nil }
        do {
            try await adb.runChecked(["-s", serial, "pull", file.path, tempDir.path])
            NSWorkspace.shared.open(tempDir.appendingPathComponent(file.name))
        } catch {
            errorMessage = "Could not open \(file.name): \(error.localizedDescription)"
        }
    }

    func upload(urls: [URL]) async {
        guard let adb, let serial = selectedSerial else { return }
        for (index, url) in urls.enumerated() {
            busyMessage = "Uploading \(url.lastPathComponent) (\(index + 1)/\(urls.count))…"
            do {
                try await adb.runChecked(["-s", serial, "push", url.path, currentPath + "/"])
            } catch {
                errorMessage = "Upload failed: \(error.localizedDescription)"
                break
            }
        }
        busyMessage = nil
        await loadDirectory()
    }

    func delete(_ items: [RemoteFile]) async {
        guard let adb, let serial = selectedSerial else { return }
        busyMessage = "Deleting…"
        do {
            for item in items {
                try await adb.runChecked(
                    ["-s", serial, "shell", "rm", "-rf", ADB.shellQuoted(item.path)]
                )
            }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        busyMessage = nil
        await loadDirectory()
        await refreshStorage()
    }

    func createFolder(named name: String) async {
        guard let adb, let serial = selectedSerial, !name.isEmpty else { return }
        let newPath = currentPath.hasSuffix("/") ? currentPath + name : currentPath + "/" + name
        do {
            try await adb.runChecked(["-s", serial, "shell", "mkdir", ADB.shellQuoted(newPath)])
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
        }
        await loadDirectory()
    }

    func rename(_ file: RemoteFile, to newName: String) async {
        guard let adb, let serial = selectedSerial, !newName.isEmpty, newName != file.name else { return }
        let dir = (file.path as NSString).deletingLastPathComponent
        let newPath = dir.hasSuffix("/") ? dir + newName : dir + "/" + newName
        do {
            try await adb.runChecked(
                ["-s", serial, "shell", "mv", ADB.shellQuoted(file.path), ADB.shellQuoted(newPath)]
            )
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
        }
        await loadDirectory()
    }
}
