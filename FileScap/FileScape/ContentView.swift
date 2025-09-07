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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            sceneArea
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

            Toggle("Hidden", isOn: $vm.includeHidden)
                .toggleStyle(.switch)
                .help("Include hidden files in scan")

            Spacer()

            if vm.isScanning { ProgressView().controlSize(.small) }

            if let url = vm.rootURL {
                Text(url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("No folder selected").foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var sceneArea: some View {
        ZStack {
            if vm.rootNode != nil {
                FileSceneView(scene: vm.scene) { path in
                    vm.select(byPath: path)
                }
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
        }
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
