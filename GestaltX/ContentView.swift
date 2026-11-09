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
            if acceptedWelcome { await autoRead() }
        }
    }

    private var isPreviewSession: Bool { false }

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
