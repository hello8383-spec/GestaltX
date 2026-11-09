// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI
import UniformTypeIdentifiers

struct SharedFile: Identifiable { let id = UUID(); let url: URL }

struct ContentView: View {
    @StateObject private var model = GestaltManager()
    @State private var importsFile = false
    @State private var sharesFile: SharedFile?
    @State private var showsChanges = false
    @State private var asksRespring = false
    @State private var asksWipe = false
    @State private var selectedTab = 0
    @State private var didStart = false
    @State private var didAutoRead = false
    #if targetEnvironment(simulator)
    @State private var previewCategory: CapabilityCategory?
    #endif
    @AppStorage("GestaltX.acceptedWelcome.v1") private var acceptedWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { tools }
                .tabItem { Label(L("Tools"), systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { FieldsView() }
                .tabItem { Label(L("Fields"), systemImage: "slider.horizontal.3") }.tag(1)
            NavigationStack { BackupsView(share: { sharesFile = SharedFile(url: $0) }) }
                .tabItem { Label(L("Backups"), systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { AboutView() }
                .tabItem { Label(L("About"), systemImage: "info.circle") }.tag(3)
        }
        .environmentObject(model)
        .tint(.blue)
        #if targetEnvironment(simulator)
        .sheet(item: $previewCategory) { category in
            NavigationStack { CategoryView(category: category) }.environmentObject(model)
        }
        #endif
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.propertyList, .xml, .data]) { result in
            switch result {
            case .success(let url): Task { await model.open(url) }
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { !acceptedWelcome && !isPreviewSession }, set: { _ in })) {
            WelcomeView { acceptedWelcome = true }
        }
        .sheet(item: $sharesFile) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showsChanges) { ChangeReviewView().environmentObject(model) }
        .fullScreenCover(isPresented: $model.isRespringing) { NeoSpringView() }
        .alert(L("GestaltX"), isPresented: Binding(get: { model.message != nil && !showsChanges }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert(L("Respring now?"), isPresented: $asksRespring) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Respring")) { model.isRespringing = true }
        } message: { Text(L("This will attempt to restart SpringBoard using NeoSpring.")) }
        .alert(L("Delete all MobileGestalt fields?"), isPresented: $asksWipe) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete All"), role: .destructive) { model.stageWipeMobileGestalt() }
        } message: { Text(L("This stages deletion of every CacheExtra field in MobileGestalt. The device file is only changed after you review and apply. A backup is created automatically before writing.")) }
        .onChange(of: acceptedWelcome) { _, accepted in
            if accepted && !isPreviewSession { Task { await autoRead() } }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await model.reloadBackups()
            #if targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--preview-document"), arguments.indices.contains(flag + 1) {
                await model.open(URL(fileURLWithPath: arguments[flag + 1]))
            }
            if let flag = arguments.firstIndex(of: "--preview-tab"), arguments.indices.contains(flag + 1), let tab = Int(arguments[flag + 1]) {
                selectedTab = tab
            }
            if arguments.contains("--preview-review") {
                if !arguments.contains("--preview-facetime-audio") { model.choices["pencil"] = .enable }
                showsChanges = true
            }
            if arguments.contains("--preview-facetime-audio") {
                model.stageFaceTimeAudio(.enable)
            }
            if let flag = arguments.firstIndex(of: "--preview-category"), arguments.indices.contains(flag + 1) {
                previewCategory = CapabilityCategory(rawValue: arguments[flag + 1])
            }
            if arguments.contains("--preview-document") || arguments.contains("--preview-tab") { return }
            #endif
            if acceptedWelcome { await autoRead() }
        }
    }

    private var isPreviewSession: Bool {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--preview-tab") || arguments.contains("--preview-document")
        #else
        return false
        #endif
    }

    private func autoRead() async {
        guard !didAutoRead else { return }
        didAutoRead = true
        await model.connect(showErrorAlert: false)
    }

    private var tools: some View {
        Form {
            Section(L("Device")) {
                LabeledContent(L("Model"), value: model.hasDocument ? model.displayedName : UIDevice.current.model)
                LabeledContent("iOS", value: "\(UIDevice.current.systemVersion) (\(VersionSupport.label))")
                LabeledContent(L("Status"), value: L(model.hasDocument ? (model.sourceIsDevice ? "Connected" : "Local File") : (model.isBusy ? "Reading…" : "Not Loaded")))
                if let document = model.working {
                    LabeledContent("CacheExtra", value: String(document.extra.count))
                }
            }
            Section {
                Button { Task { await model.connect() } } label: {
                    Label(L(model.isBusy ? "Reading…" : model.hasDocument ? "Read Again" : "Read MobileGestalt"), systemImage: "arrow.clockwise")
                }.disabled(model.isBusy || model.changeCount > 0)
                Button { importsFile = true } label: { Label(L("Import Plist"), systemImage: "doc.badge.plus") }
                    .disabled(model.isBusy || model.changeCount > 0)
            }
            Section("MobileGestalt") {
                ForEach(CapabilityCategory.allCases) { category in
                    NavigationLink { CategoryView(category: category) } label: {
                        Label(L(category.rawValue), systemImage: category.symbol)
                    }
                    .disabled(!model.hasDocument || model.isBusy)
                }
            }
            Section(L("Actions")) {
                Button { showsChanges = true } label: {
                    HStack {
                        Label(L("Apply Changes"), systemImage: "checkmark")
                        Spacer()
                        if model.changeCount > 0 { Text(String(model.changeCount)).foregroundStyle(.secondary) }
                    }
                }.disabled(model.changeCount == 0 || model.isBusy)
                Button(L("Discard Changes"), role: .destructive) { model.clearStaged() }
                    .disabled(model.changeCount == 0 || model.isBusy)
                Button(role: .destructive) { asksWipe = true } label: {
                    Label(L("Wipe MobileGestalt"), systemImage: "trash")
                }
                .disabled(!model.hasDocument || model.isBusy)
                Button { Task { await model.backup() } } label: { Label(L("Create Backup"), systemImage: "externaldrive.badge.plus") }
                    .disabled(!model.hasDocument || model.isBusy)
                Button {
                    if let url = model.exportDocument() { sharesFile = SharedFile(url: url) }
                } label: { Label(L("Export Plist"), systemImage: "square.and.arrow.up") }
                    .disabled(!model.hasDocument || model.isBusy)
                Button { asksRespring = true } label: { Label(L("Respring"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                    .disabled(model.isBusy)
            }
            if model.needsRespring {
                Section { Label(L("Some changes require a device restart."), systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            }
            Section { NavigationLink { SessionLogView() } label: { Label(L("Log"), systemImage: "text.alignleft") } }
        }
        .navigationTitle("GestaltX")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.isBusy { ProgressView() } } }
    }
}

struct CategoryView: View {
    let category: CapabilityCategory
    @EnvironmentObject private var model: GestaltManager
    var body: some View {
        Form {
            if category == .display {
                Section {
                    Picker(L("Dynamic Island Layout"), selection: $model.subtype) {
                        Text(L("Keep Current")).tag(0)
                        Text("iPhone 14 Pro · 2556").tag(2556)
                        Text("iPhone 14 Pro Max · 2796").tag(2796)
                        Text("iPhone 16 Pro · 2622").tag(2622)
                        Text("iPhone 16 Pro Max · 2868").tag(2868)
                    }
                    .onChange(of: model.subtype) { _, value in if value != 0 { model.choices["dynamicIsland"] = .keep } }
                }
            }
            if category == .device {
                Section(L("Device Identity")) {
                    Toggle(L("Change Model Name"), isOn: $model.changesName)
                    if model.changesName {
                        TextField(L("Model Name"), text: $model.modelName).autocorrectionDisabled()
                        Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if category == .intelligence {
                Section {
                    Picker(L("Region Code"), selection: $model.regionCodeID) {
                        ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
                    }
                    if model.regionCodeID != "keep" { Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Usually, changing the region code is enough. There is no need to change Sales Region."))
                        Text(L("* If you previously changed Sales Region, restore your device's original sales region and apply it first."))
                    }
                }
                Section {
                    Picker(L("Sales Region"), selection: $model.regionID) {
                        ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
                    }
                    if model.regionID != "keep" { Text(L("Restart the device after changing the region.")).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text(L("Changing the sales-region suffix may cause verification tools to report a mismatch with factory information."))
                }
            }
            Section {
                ForEach(Capability.all.filter { $0.category == category }) { capability in
                    VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: Binding(
                        get: { model.choices[capability.id] ?? .keep },
                        set: {
                            model.choices[capability.id] = $0
                            if capability.id == "dynamicIsland" && $0 != .keep { model.subtype = 0 }
                        }
                    )) {
                        ForEach(PresetChoice.allCases) { Text(L($0.title)).tag($0) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(L(capability.title))
                            if capability.caution {
                                Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                                    .accessibilityLabel(L("Experimental"))
                            }
                        }
                    }.pickerStyle(.menu)
                    HStack(alignment: .firstTextBaseline) {
                        if (model.choices[capability.id] ?? .keep) != .keep {
                            Text(L(capability.effectHint)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(L("Revert")) { Task { await model.restoreCapability(capability) } }
                            .font(.caption).buttonStyle(.borderless)
                            .disabled(!model.canRestore(capability))
                    }
                    }
                }
                if category == .device { FaceTimeAudioPresetRow() }
            } header: {
                Text(L("Presets"))
            }
            if category == .ipad || category == .advanced {
                Section { Text(L("Experimental settings. Back up before applying.")).font(.footnote).foregroundStyle(.secondary) }
            }
            if model.changeCount > 0 {
                Section { NavigationLink(L("Review Changes")) { ChangeReviewView(isSheet: false) } }
            }
        }
        .navigationTitle(L(category.rawValue)).disabled(model.isBusy)
    }
}

struct FaceTimeAudioPresetRow: View {
    @EnvironmentObject private var model: GestaltManager

    private var support: Result<FaceTimeAudioFlags, Error> {
        Result {
            guard let document = model.preview else { throw GestaltFailure("Load a document first.") }
            return try FaceTimeAudioCache.flags(in: document)
        }
    }

    var body: some View {
        switch support {
        case .success:
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("FaceTime Audio"), selection: Binding(
                    get: { model.faceTimeAudioChoice },
                    set: { model.stageFaceTimeAudio($0) }
                )) {
                    ForEach(FaceTimeAudioChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("facetime-audio-choice")
                HStack(alignment: .firstTextBaseline) {
                    if model.faceTimeAudioChoice != .keep {
                        Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(L("Revert")) { Task { await model.restoreFaceTimeAudio() }
                        .font(.caption).buttonStyle(.borderless)
                        .disabled(!model.canRestoreFaceTimeAudio)
                        .accessibilityIdentifier("facetime-audio-revert")
                    }
                }
            }
        case .failure(let error):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L("FaceTime Audio")) { Text(L("Unsupported")).foregroundStyle(.secondary) }
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
