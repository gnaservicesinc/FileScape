//
//  FileScapApp.swift
//  FileScap
//
//  Created by Andrew Smith on 9/6/25.
//

import SwiftUI

@main
struct FileScapeApp: App {
    @StateObject private var vm = ExplorerViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
    }
}
