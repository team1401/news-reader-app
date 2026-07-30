import SwiftUI

@main
struct BroadsheetApp: App {
    @State private var model: AppModel
    /// Set only if the durable store could not be opened. The reader is told
    /// rather than silently given a library that will not survive relaunch.
    @State private var storeWarning: String?

    init() {
        let configuration = LaunchConfiguration.current
        let opened = BroadsheetApp.openStore(configuration: configuration)

        let transport: (any HTTPTransport)? = configuration.usesStubbedNetwork
            ? UITestFixtures.transport()
            : nil

        let model = AppModel(store: opened.store, transport: transport)
        if configuration.startsInDemoMode {
            model.isDemoMode = true
        }

        _model = State(initialValue: model)
        _storeWarning = State(initialValue: opened.warning)
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeWarning: storeWarning)
                .environment(model)
                .task {
                    model.bootstrap()
                    // Eager analysis so every card already carries its label.
                    await model.analyzeVisible()
                }
        }
    }

    /// Opens the durable container, falling back to an in-memory one only if the
    /// disk store cannot be opened at all — and saying so when it happens.
    static func openStore(configuration: LaunchConfiguration) -> (store: BroadsheetStore, warning: String?) {
        if configuration.usesInMemoryStore {
            if let store = try? BroadsheetStore(inMemory: true) {
                return (store, nil)
            }
        }
        do {
            return (try BroadsheetStore(inMemory: false), nil)
        } catch {
            let store = try! BroadsheetStore(inMemory: true)
            return (
                store,
                "Broadsheet could not open its library on this device (\(error.localizedDescription)). It is running from memory, so nothing you read or save now will survive a relaunch."
            )
        }
    }
}

struct RootView: View {
    var storeWarning: String?

    var body: some View {
        TabView {
            Tab("Today", systemImage: "newspaper") {
                TodayView()
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            Tab("Search", systemImage: "magnifyingglass") {
                SearchView()
            }
        }
        .tint(BSColor.accent)
        .overlay(alignment: .top) {
            if let storeWarning {
                Text(storeWarning)
                    .font(.footnote)
                    .padding(BSSpacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BSColor.warning.opacity(0.18))
            }
        }
    }
}
