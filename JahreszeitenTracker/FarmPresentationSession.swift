import Combine

// Shared by the menu and farm views; deliberately never encoded or persisted.
@MainActor
final class FarmPresentationSession: ObservableObject {
    @Published var showHiddenFarms = false
}
