//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI

struct TestView: View {
    @State var Host: JBHostDevice
    @State var Path = "/var/mobile/Containers/Data/Application"
    var body: some View {
        VStack {
            TextField("Path", text: $Path)
            .padding(.horizontal, 15)
            .frame(width: UIScreen.main.bounds.width - 80, height: 40)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(15)
            LogView()
            Button {
                print(Host.testAFC(Path)) 
            } label: {
                Text("Test")
                .font(.system(size: 20))
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: UIScreen.main.bounds.width - 80, height: 70)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(20)
        }
    }
}

struct LogView: View {
    @State var LogItems: [LogItem] = []
    let pipe = Pipe()
    let sema = DispatchSemaphore(value: 0)
    var body: some View {
        ScrollView {
            ScrollViewReader { scroll in
                VStack(alignment: .leading) {
                    ForEach(LogItems) { Item in
                        Text(Item.Message.lineFix())
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .id(Item.id)
                    }
                }
                .onChange(of: LogItems) { _ in
                    DispatchQueue.main.async {
                        scroll.scrollTo(LogItems.last?.id, anchor: .bottom)
                    }
                }
                .contextMenu {
                    Button {
                        var LogString = ""
                        for Item in LogItems {
                            LogString += Item.Message
                        }
                        UIPasteboard.general.string = LogString
                    } label: {
                        Label("Copy to clipboard", systemImage: "doc.on.doc")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(width: UIScreen.main.bounds.width - 80, height: 300)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(20)
        .onAppear {
            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if data.isEmpty  {
                    fileHandle.readabilityHandler = nil
                    sema.signal()
                } else {
                    LogItems.append(LogItem(Message: String(data: data, encoding: .utf8)!))
                }
            }
            setvbuf(stdout, nil, _IONBF, 0)
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        }
    }
}

struct LogItem: Identifiable, Equatable {
    var id = UUID()
    var Message: String
}

extension String {
    // If last char is a new line remove it
    func lineFix() -> String {
        return String(self.last == "\n" ? String(self.dropLast()) : self)
    }
}

fileprivate enum FileType: Int, Identifiable {
    var id: Int {
        self.rawValue
    }
    
    case pairing
    case supportImage
    case supportImageSignature
}

struct DeviceDetailsView: View {
    @EnvironmentObject private var main: Main
    @State private var fileSelectType: FileType?
    @State private var selectedPairing: URL?
    @State private var selectedSupportImage: URL?
    @State private var selectedSupportImageSignature: URL?
    @State private var apps: [JBApp] = []
    @State private var appToLaunchAfterMount: JBApp?
    
    let host: JBHostDevice
    
    private var favoriteApps: [JBApp] {
        let favorites = main.getFavorites(forHostIdentifier: host.identifier)
        return apps.filter { app in
            favorites.contains { favorite in
                app.bundleIdentifier == favorite
            }
        }.sorted { $0.bundleName < $1.bundleName }
    }
    
    private var notFavoriteApps: [JBApp] {
        let favorites = main.getFavorites(forHostIdentifier: host.identifier)
        return apps.filter { app in
            !favorites.contains { favorite in
                app.bundleIdentifier == favorite
            }
        }.sorted { $0.bundleName < $1.bundleName }
    }
    
    var body: some View {
        Group {
            NavigationLink {
                TestView(Host: host)
            } label: {
                Text("AFC")
            }
            if host == main.localHost && !main.hasLocalDeviceSupport {
                Text("Local device not supported.")
                    .font(.headline)
            } else if !host.isConnected {
                Text("Not paired.")
                    .font(.headline)
            } else if apps.isEmpty {
                Text("No apps found on device.")
                    .font(.headline)
            } else {
                List {
                    if !main.getFavorites(forHostIdentifier: host.identifier).isEmpty {
                        Section(header: Text("Favorites")) {
                            ForEach(favoriteApps) { app in
                                Button {
                                    launchApplication(app)
                                } label: {
                                    AppItemView(app: app, saved: true, hostIdentifier: host.identifier)
                                }.appContextMenu(host: host, app: app)
                            }
                        }
                    }
                    Section(header: Text("Installed")) {
                        ForEach(notFavoriteApps) { app in
                            Button {
                                launchApplication(app)
                            } label: {
                                AppItemView(app: app, saved: false, hostIdentifier: host.identifier)
                            }.appContextMenu(host: host, app: app)
                        }
                    }
                }
            }
        }.navigationTitle(host.name)
        .listStyle(PlainListStyle())
        .sheet(item: $fileSelectType) { type in
            switch type {
            case .pairing:
                FileSelectionView(urls: main.pairings, selectedUrl: $selectedPairing, title: Text("Select Pairing"))
            case .supportImage:
                FileSelectionView(urls: main.supportImages, selectedUrl: $selectedSupportImage, title: Text("Select Image"))
            case .supportImageSignature:
                FileSelectionView(urls: main.supportImages, selectedUrl: $selectedSupportImageSignature, title: Text("Select Signature"))
            }
        }.toolbar {
            HStack {
                Button {
                    fileSelectType = .pairing
                } label: {
                    Text("Pair")
                }
                Button {
                    fileSelectType = .supportImage
                } label: {
                    Text("Mount")
                }.disabled(!host.isConnected)
            }
        }.onAppear {
            #if WITH_VPN
            let supportVPN = main.localHost == host && main.hasLocalDeviceSupport && !main.isTunnelStarted
            #else
            let supportVPN = false
            #endif
            if supportVPN {
                main.startTunnel()
            } else {
                // BUG: sometimes SwiftUI doesn't like this...
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
                    loadDefaults()
                }
            }
        }.onChange(of: selectedPairing) { url in
            guard let selected = url else {
                return
            }
            loadPairing(for: selected)
        }.onChange(of: selectedSupportImage) { url in
            guard let supportImage = url else {
                return
            }
            let maybeSig = supportImage.appendingPathExtension("signature")
            if selectedSupportImageSignature == nil {
                if FileManager.default.fileExists(atPath: maybeSig.path) {
                    selectedSupportImageSignature = maybeSig
                } else {
                    fileSelectType = .supportImageSignature
                }
            }
        }.onChange(of :selectedSupportImageSignature) { url in
            guard let supportImage = selectedSupportImage else {
                return
            }
            guard let supportImageSignature = url else {
                return
            }
            mountImage(supportImage, signature: supportImageSignature)
        }.onChange(of: main.isTunnelStarted) { started in
            resetConnection {
                if started {
                    // BUG: sometimes SwiftUI doesn't like this...
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
                        loadDefaults()
                    }
                }
            }
        }.onChange(of: main.selectedLaunchAppId) { appId in
            guard apps.count > 0 else {
                return
            }
            guard let autoLaunchApp = try? main.processAutoLaunch(withApps: apps) else {
                return
            }
            launchApplication(autoLaunchApp)
        }
    }
    
    private func loadDefaults() {
        selectedPairing = main.loadPairing(forHostIdentifier: host.identifier)
        selectedSupportImage = main.loadDiskImage(forHostIdentifier: host.identifier)
        selectedSupportImageSignature = main.loadDiskImageSignature(forHostIdentifier: host.identifier)
        if selectedPairing == nil {
            fileSelectType = .pairing
        }
    }
    
    private func resetConnection(onComplete: @escaping () -> Void) {
        main.backgroundTask(message: NSLocalizedString("Disconnecting...", comment: "DeviceDetailsView")) {
            host.stopLockdown()
        } onComplete: {
            onComplete()
        }
    }
    
    private func loadPairing(for selected: URL) {
        var success = false
        main.backgroundTask(message: NSLocalizedString("Loading pairing data...", comment: "DeviceDetailsView")) {
            main.savePairing(nil, forHostIdentifier: host.identifier)
            try host.startLockdown(withPairingUrl: selected)
            try host.updateInfo()
            if host.startAFCService() {
                UIPasteboard.general.string = "Good"
            } else {
                UIPasteboard.general.string = "Not good"
            }
            success = true
        } onComplete: {
            selectedPairing = nil
            if success {
                refreshAppsList {
                    main.savePairing(selected, forHostIdentifier: host.identifier)
                }
            }
        }
    }
    
    private func refreshAppsList(onSuccess: @escaping () -> Void) {
        var autoLaunchApp: JBApp?
        main.backgroundTask(message: NSLocalizedString("Querying installed apps...", comment: "DeviceDetailsView")) {
            try host.updateInfo()
            apps = try host.installedApps()
            main.archiveSavedHosts()
            autoLaunchApp = try main.processAutoLaunch(withApps: apps)
            onSuccess()
        } onComplete: {
            if let app = autoLaunchApp {
                launchApplication(app)
            }
        }
    }
    
    private func mountImage(_ supportImage: URL, signature supportImageSignature: URL) {
        main.backgroundTask(message: NSLocalizedString("Mounting disk image...", comment: "DeviceDetailsView")) {
            main.saveDiskImage(nil, signature: nil, forHostIdentifier: host.identifier)
            try host.mountImage(for: supportImage, signatureUrl: supportImageSignature)
            main.saveDiskImage(supportImage, signature: supportImageSignature, forHostIdentifier: host.identifier)
        } onComplete: {
            selectedSupportImage = nil
            selectedSupportImageSignature = nil
            if let app = appToLaunchAfterMount {
                appToLaunchAfterMount = nil
                launchApplication(app)
            }
        }
    }
    
    private func launchApplication(_ app: JBApp) {
        var imageNotMounted = false
        main.backgroundTask(message: NSLocalizedString("Launching...", comment: "DeviceDetailsView")) {
            do {
                try host.launchApplication(app)
            } catch {
                let code = (error as NSError).code
                if code == kJBHostImageNotMounted {
                    imageNotMounted = true
                } else {
                    throw error
                }
            }
        } onComplete: {
            // BUG: SwiftUI shows .disabled() even after it's already done
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
                if imageNotMounted {
                    self.handleImageNotMounted(app: app)
                }
            }
        }
    }
    
    private func handleImageNotMounted(app: JBApp) {
        if main.supportImages.isEmpty {
            main.alertMessage = NSLocalizedString("Developer image is not mounted. You need DeveloperDiskImage.dmg and DeveloperDiskImage.dmg.signature imported in Support Files.", comment: "DeviceDetailsView")
        } else {
            fileSelectType = .supportImage
            appToLaunchAfterMount = app
        }
    }
}

struct AppContextMenuViewModifier: ViewModifier {
    @EnvironmentObject private var main: Main
    let host: JBHostDevice
    let app: JBApp
    
    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                UIPasteboard.general.url = main.encodeURL(forHost: host, launchingApp: app)
            } label: {
                Label("Copy Shortcut URL", systemImage: "link")
                    .labelStyle(DefaultLabelStyle())
            }
        }
    }
}

extension View {
    func appContextMenu(host: JBHostDevice, app: JBApp) -> some View {
        self.modifier(AppContextMenuViewModifier(host: host, app: app))
    }
}

struct DeviceDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceDetailsView(host: JBHostDevice(hostname: "", address: Data()))
    }
}
