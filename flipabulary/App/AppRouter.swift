import Foundation
import Observation
import SwiftUI

enum AppRoute: Hashable {
    case stacks
    case stackSettings(UUID)
    case stackRules(UUID)
    case learningRules
    case settings
    case widgets
    case reminders
    case importExport
    case statistics(UUID?)
}

enum EditorTarget: Identifiable, Hashable {
    case new(stackID: UUID?)
    case edit(UUID)

    var id: String {
        switch self {
        case .new(let stackID): "new-\(stackID?.uuidString ?? "all")"
        case .edit(let id): "edit-\(id.uuidString)"
        }
    }

    var cardID: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

struct ReviewLaunch: Identifiable, Hashable {
    let id: UUID
}

struct ScopePickerState: Identifiable, Hashable {
    let id = UUID()
    var stacks: [StackDisplayModel]
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var editorTarget: EditorTarget?
    var supportVisible = false
    var reviewLaunch: ReviewLaunch?
    var scopePicker: ScopePickerState?
    var toast: ToastMessage?
    var showResumePrompt = false

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }

    func showToast(_ text: String) {
        let message = ToastMessage(text: text)
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if toast?.id == message.id {
                toast = nil
            }
        }
    }

    func presentEditor(_ target: EditorTarget) {
        editorTarget = target
    }
}
