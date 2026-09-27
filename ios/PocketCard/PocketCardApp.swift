import SwiftUI

@main
@MainActor
struct PocketCardApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var wallet = WalletCoordinator()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(model)
                .environmentObject(wallet)
                .tint(.teal)
                .background(WindowPrivacyShield(active:phase != .active).frame(width:0,height:0))
                .onChange(of:phase) { _, value in
                    if value == .active { model.reload(); wallet.refresh() }
                }
        }
    }
}
