import SwiftUI
import AppKit

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup("TestTitle", id: "main_id") {
            Text("Hello")
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        for w in NSApp.windows {
                            print("Title: '\(w.title)', ID: '\(w.identifier?.rawValue ?? "nil")'")
                        }
                        exit(0)
                    }
                }
        }
    }
}
