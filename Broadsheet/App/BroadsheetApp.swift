import SwiftUI

@main
struct BroadsheetApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    // Eager analysis so every card already carries its label.
                    await model.analyzeIfNeeded()
                }
        }
    }
}

struct RootView: View {
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
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
