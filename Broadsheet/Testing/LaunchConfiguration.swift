import Foundation

/// How this launch was configured.
///
/// The UI tests drive the real app, the real refresh pipeline, the real parsers,
/// and the real extractor. Only two things are swapped: the store is in memory so a
/// test never touches the reader's library, and the transport serves bundled
/// fixtures so the suite does not depend on four publishers being reachable.
/// Neither switch is reachable from the running app — both require a launch
/// argument that only the test runner passes.
public struct LaunchConfiguration: Equatable, Sendable {
    public static let inMemoryStoreArgument = "-broadsheet-in-memory-store"
    public static let stubbedNetworkArgument = "-broadsheet-stub-network"
    public static let demoModeArgument = "-broadsheet-demo-mode"

    public var usesInMemoryStore: Bool
    public var usesStubbedNetwork: Bool
    public var startsInDemoMode: Bool

    public init(usesInMemoryStore: Bool = false, usesStubbedNetwork: Bool = false, startsInDemoMode: Bool = false) {
        self.usesInMemoryStore = usesInMemoryStore
        self.usesStubbedNetwork = usesStubbedNetwork
        self.startsInDemoMode = startsInDemoMode
    }

    public static func from(arguments: [String]) -> LaunchConfiguration {
        LaunchConfiguration(
            usesInMemoryStore: arguments.contains(inMemoryStoreArgument),
            usesStubbedNetwork: arguments.contains(stubbedNetworkArgument),
            startsInDemoMode: arguments.contains(demoModeArgument)
        )
    }

    public static var current: LaunchConfiguration {
        from(arguments: ProcessInfo.processInfo.arguments)
    }
}
