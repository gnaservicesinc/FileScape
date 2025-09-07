import Foundation

struct SecurityScope {
    private(set) var url: URL? = nil
    private(set) var active: Bool = false

    mutating func begin(for url: URL) {
        stop()
        active = url.startAccessingSecurityScopedResource()
        self.url = url
    }

    mutating func ensure(for url: URL) {
        if self.url == url, active == false {
            active = url.startAccessingSecurityScopedResource()
        }
    }

    mutating func stop() {
        if active, let url = url {
            url.stopAccessingSecurityScopedResource()
        }
        active = false
    }
}

