import SwiftUI

struct ContentView: View {
    @StateObject private var vm = BrowserViewModel()

    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: RemoteFile?
    @State private var renameText = ""
    @State private var deleteTargets: [RemoteFile] = []
    @State private var showingDeleteConfirm = false

    var body: some View {
        Group {
            switch vm.deviceState {
            case .adbMissing: adbMissingView
            case .noDevice: waitingView
            case .unauthorized: unauthorizedView
            case .ready: browserView
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { vm.start() }
        .alert("Something went wrong", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Empty states

    private var adbMissingView: some View {
        placeholder(
            icon: "exclamationmark.triangle",
            title: "adb not found",
            message: "DroidDrive needs the Android platform tools.\nInstall them in Terminal, then relaunch:\n\nbrew install android-platform-tools"
        )
    }

    private var waitingView: some View {
        placeholder(
            icon: "cable.connector",
            title: "Waiting for your Android device…",
            message: """
            1. Connect your phone with a USB cable.
            2. On the phone, enable Developer options \
            (Settings → About phone → tap “Build number” 7 times).
            3. In Settings → Developer options, turn on “USB debugging”.
            """
        )
    }

    private var unauthorizedView: some View {
        placeholder(
            icon: "lock.shield",
            title: "Check your phone",
            message: "Unlock your phone and tap “Allow” on the\n“Allow USB debugging?” prompt to trust this Mac."
        )
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            ProgressView()
                .controlSize(.small)
                .opacity(vm.deviceState == .adbMissing ? 0 : 1)
        }
        .padding(40)
    }

    // MARK: - Browser

    private var browserView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            breadcrumb
            Divider()
            fileTable
        }
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { busyBanner }
        .sheet(isPresented: $showingNewFolder) { newFolderSheet }
        .sheet(item: $renameTarget) { file in renameSheet(file) }
        .confirmationDialog(
            deleteTargets.count == 1
                ? "Delete “\(deleteTargets.first?.name ?? "")” from the phone?"
                : "Delete \(deleteTargets.count) items from the phone?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                let targets = deleteTargets
                Task { await vm.delete(targets) }
            }
        } message: {
            Text("This permanently removes the files from your Android device.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "smartphone")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                if vm.devices.count > 1 {
                    Picker("", selection: Binding(
                        get: { vm.selectedSerial ?? "" },
                        set: { vm.selectDevice($0) }
                    )) {
                        ForEach(vm.devices) { device in
                            Text(device.displayName).tag(device.serial)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(vm.currentDevice?.displayName ?? "Android device")
                        .font(.headline)
                }
                if !vm.storageSummary.isEmpty {
                    Text(vm.storageSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(vm.pathComponents.enumerated()), id: \.element.path) { index, part in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(part.name) { vm.navigate(to: part.path) }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(part.path == vm.currentPath ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.quaternary.opacity(0.3))
    }

    private var fileTable: some View {
        Table(vm.files, selection: $vm.selection) {
            TableColumn("Name") { file in
                HStack(spacing: 8) {
                    Image(systemName: file.iconName)
                        .foregroundStyle(file.isDirectory ? .cyan : .secondary)
                        .frame(width: 18)
                    Text(file.name)
                }
            }
            .width(min: 250, ideal: 380)
            TableColumn("Size") { file in
                Text(file.displaySize).foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Modified") { file in
                Text(file.modified).foregroundStyle(.secondary)
            }
            .width(140)
        }
        .contextMenu(forSelectionType: RemoteFile.ID.self) { ids in
            let items = vm.files.filter { ids.contains($0.id) }
            if !items.isEmpty {
                Button("Download to Mac…") { pickDownloadDestination(for: items) }
                if items.count == 1, let item = items.first {
                    Button("Rename…") {
                        renameText = item.name
                        renameTarget = item
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deleteTargets = items
                    showingDeleteConfirm = true
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let file = vm.files.first(where: { $0.id == id }) {
                vm.open(file)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                vm.goUp()
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(vm.currentPath == "/")
            .help("Go to enclosing folder")
        }
        ToolbarItemGroup {
            Button {
                Task { await vm.loadDirectory() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                showingNewFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("New folder on the phone")

            Button {
                pickUploadFiles()
            } label: {
                Label("Upload", systemImage: "square.and.arrow.up")
            }
            .help("Copy files from this Mac to the phone")

            Button {
                pickDownloadDestination(for: vm.selectedFiles)
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            .disabled(vm.selection.isEmpty)
            .help("Copy the selected items to this Mac")
        }
    }

    private var busyBanner: some View {
        Group {
            if let message = vm.busyMessage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
        .animation(.default, value: vm.busyMessage)
    }

    // MARK: - Sheets & panels

    private var newFolderSheet: some View {
        VStack(spacing: 16) {
            Text("New folder in \(vm.currentPath)").font(.headline)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { submitNewFolder() }
            HStack {
                Button("Cancel") {
                    showingNewFolder = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") { submitNewFolder() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newFolderName.isEmpty)
            }
        }
        .padding(24)
    }

    private func submitNewFolder() {
        let name = newFolderName
        showingNewFolder = false
        newFolderName = ""
        guard !name.isEmpty else { return }
        Task { await vm.createFolder(named: name) }
    }

    private func renameSheet(_ file: RemoteFile) -> some View {
        VStack(spacing: 16) {
            Text("Rename “\(file.name)”").font(.headline)
            TextField("New name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { submitRename(file) }
            HStack {
                Button("Cancel") { renameTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { submitRename(file) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.isEmpty)
            }
        }
        .padding(24)
    }

    private func submitRename(_ file: RemoteFile) {
        let newName = renameText
        renameTarget = nil
        Task { await vm.rename(file, to: newName) }
    }

    private func pickUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to copy to \(vm.currentPath)"
        panel.prompt = "Upload"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let urls = panel.urls
            Task { await vm.upload(urls: urls) }
        }
    }

    private func pickDownloadDestination(for items: [RemoteFile]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = "Choose where to save \(items.count == 1 ? "“\(items[0].name)”" : "\(items.count) items")"
        panel.prompt = "Download Here"
        if panel.runModal() == .OK, let destination = panel.url {
            Task { await vm.download(items, to: destination) }
        }
    }
}
