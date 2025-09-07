//
//  ContentView.swift
//  FileScap
//
//  Created by Andrew Smith on 9/6/25.
//

import SwiftUI
import SceneKit

struct ContentView: View {
    @EnvironmentObject var vm: ExplorerViewModel
    @State private var cameraFocusPath: String? = nil
    @State private var transitionHint: FileSceneView.TransitionHint? = nil
    @State private var flyTo: FileSceneView.FlyTarget? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            crumbsBar
            Divider()
            HStack(spacing: 0) {
                sceneArea
                if vm.showInfoPanel { infoPanel.frame(width: 300) }
            }
            Divider()
            detailsBar
        }
        .task(id: vm.rootURL) {
            if vm.rootURL != nil { await vm.rescan() }
        }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                transitionHint = .exit
                vm.goUp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { transitionHint = nil }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(vm.breadcrumbs().count <= 1)

            Button {
                vm.chooseFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                Task { await vm.rescan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(vm.rootURL == nil || vm.isScanning)

            // Rooms removed per feedback

            Toggle("Hidden", isOn: $vm.includeHidden)
                .toggleStyle(.switch)
                .help("Include hidden files in scan")

            Spacer()

            if vm.isScanning { ProgressView().controlSize(.small) }

            HStack(spacing: 8) {
                TextField("Search name", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onChange(of: vm.searchText) { _ in vm.rebuildScene() }

                Stepper(value: $vm.maxItems, in: 32...1024, step: 32, onEditingChanged: { _ in vm.rebuildScene() }) {
                    Text("Top \(vm.maxItems)")
                }
                .help("Limit number of blocks for performance")
                .onChange(of: vm.maxItems) { _ in vm.rebuildScene() }

                Button {
                    withAnimation { vm.showInfoPanel.toggle() }
                } label: {
                    Label("Info", systemImage: vm.showInfoPanel ? "sidebar.right" : "sidebar.right")
                }
            }
        }
        .padding(8)
    }

    private var crumbsBar: some View {
        HStack(spacing: 6) {
            if vm.breadcrumbs().isEmpty {
                Text("No folder selected").foregroundStyle(.secondary)
            } else {
                ForEach(Array(vm.breadcrumbs().enumerated()), id: \.offset) { idx, node in
                    if idx > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                    Button(node.displayName.isEmpty ? node.url.lastPathComponent : node.displayName) {
                        vm.goToBreadcrumb(index: idx)
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var sceneArea: some View {
        ZStack(alignment: .topTrailing) {
            if vm.rootNode != nil {
                FileSceneView(scene: vm.scene, focusPath: cameraFocusPath, transitionHint: transitionHint, onSelectPath: { path in
                    vm.select(byPath: path)
                }, onActivatePath: { path in
                    vm.select(byPath: path)
                    // fly fast to the target first, then enter
                    flyTo = FileSceneView.FlyTarget(path: path, fast: true)
                }, onBack: { vm.goUp() }, zoomModifier: vm.zoomKey.flag, flyTo: flyTo, onFlyComplete: {
                    if vm.selected != nil { transitionHint = .enter; vm.enterSelectedFolder(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { transitionHint = nil } }
                    flyTo = nil
                })
                .ignoresSafeArea(edges: .horizontal)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3.fill.square")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    Text("Choose a folder to visualize as a 3D city")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button("Choose Folder") { vm.chooseFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            legend
            if let msg = vm.overlayMessage {
                VStack {
                    Text(msg)
                        .font(.callout)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: .blue, label: "Video")
            legendItem(color: .green, label: "Image")
            legendItem(color: .teal, label: "Audio")
            legendItem(color: .red, label: "App")
            legendItem(color: .yellow, label: "Doc")
            legendItem(color: .purple, label: "Code")
            legendItem(color: .brown, label: "Archive")
            legendItem(color: .gray, label: "Other")
        }
        .font(.caption2)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Info").font(.headline)
                Spacer()
                Button { withAnimation { vm.showInfoPanel.toggle() } } label: { Image(systemName: "sidebar.trailing") }
                    .buttonStyle(.plain)
            }

            // Filters
            Text("Filters").font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(FileKind.allCases), id: \.self) { kind in
                    Toggle(isOn: Binding(get: { vm.enabledKinds.contains(kind) }, set: { v in
                        if v { vm.enabledKinds.insert(kind) } else { vm.enabledKinds.remove(kind) }
                        vm.rebuildScene()
                    })) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: kind.color)).frame(width: 8, height: 8)
                            Text(kind.displayName)
                        }
                    }
                }
            }

            Divider()

            // View controls
            Text("View").font(.subheadline)
            Toggle("Show labels", isOn: $vm.showInlineLabels).onChange(of: vm.showInlineLabels) { _ in vm.rebuildScene() }
            HStack {
                Text("Preview density").frame(width: 120, alignment: .leading)
                Slider(value: Binding(get: { Double(vm.previewLimit) }, set: { vm.previewLimit = Int($0); vm.rebuildScene() }), in: 0...40, step: 5)
                Text("\(vm.previewLimit)")
                    .frame(width: 30)
            }
            HStack {
                Text("Transparency").frame(width: 120, alignment: .leading)
                Slider(value: $vm.alphaScale, in: 0...1)
                    .onChange(of: vm.alphaScale) { _ in vm.rebuildScene() }
            }
            HStack {
                Text("Gap scale").frame(width: 120, alignment: .leading)
                Slider(value: $vm.gapScale, in: 0.5...2.0)
                    .onChange(of: vm.gapScale) { _ in vm.rebuildScene() }
            }

            Toggle("Exact package sizes", isOn: $vm.exactPackageSizes)
            HStack {
                Text("Zoom modifier").frame(width: 120, alignment: .leading)
                Picker("Zoom modifier", selection: $vm.zoomKey) {
                    ForEach(ExplorerViewModel.ZoomKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }

            if let s = vm.selected {
                Text(s.displayName).font(.headline)
                Text(s.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                HStack { Text("Type:"); Text(s.isDirectory ? "Folder" : (s.fileExtension?.uppercased() ?? "File")) }.font(.caption)
                HStack { Text("Size:"); Text(sizeString(s.sizeBytes)) }.font(.caption)
                if let mod = s.modificationDate { HStack { Text("Modified:"); Text(DateFormatter.localizedString(from: mod, dateStyle: .short, timeStyle: .short)) }.font(.caption) }
                if let acc = s.accessDate { HStack { Text("Accessed:"); Text(DateFormatter.localizedString(from: acc, dateStyle: .short, timeStyle: .short)) }.font(.caption) }
                Spacer()
            } else {
                Text("No selection").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var detailsBar: some View {
        HStack(spacing: 16) {
            if let s = vm.selected {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayName).font(.headline)
                    HStack(spacing: 12) {
                        Text(sizeString(s.sizeBytes))
                        Text(s.fileExtension?.uppercased() ?? (s.isDirectory ? "Folder" : "File"))
                        Text(s.url.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                Spacer()

                Button("Open") { vm.openSelected() }
                Button("Reveal in Finder") { vm.revealSelectedInFinder() }
                Button("Focus Camera") {
                    cameraFocusPath = vm.selected?.url.path
                    // Nudge signal by clearing after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        cameraFocusPath = nil
                    }
                }
                if s.isDirectory { Button("Enter Folder") { transitionHint = .enter; vm.enterSelectedFolder(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { transitionHint = nil } } }
                Button(role: .destructive) { vm.trashSelected() } label: { Text("Move to Trash") }
            } else {
                Text("Select a block to see details and actions")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
    }

    private func sizeString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

#Preview {
    ContentView().environmentObject(ExplorerViewModel())
}
