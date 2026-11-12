import Foundation
import UIKit
import Combine

@MainActor
final class DocumentImportController: ObservableObject {
    @Published var pickerPresented = false
    @Published private(set) var awaitingImport = false
    @Published private(set) var status: String?
    @Published private(set) var lastFeedback: ImportFeedback?
    @Published var feedback: ImportFeedback?
    private var feedbackTask: Task<Void, Never>?
    #if DEBUG
    @Published var fixtureExportActive = false
    @Published var fixtureExportStatus: String?
    #endif

    func openPicker() {
        guard !pickerPresented, !awaitingImport else { return }
        status = nil; feedback = nil; pickerPresented = true
    }
    func consume(_ result: Result<[URL], Error>, library: LibraryStore) {
        pickerPresented = false
        switch result {
        case .success(let urls):
            for url in urls { ImportDiagnostics.event("picker-selected", stage: .picker, url: url) }
            awaitingImport = true; status = "已选择文件，正在导入…"
            Task {
                let result = await library.importFiles(from: urls)
                awaitingImport = false
                publish(result)
            }
        case .failure(let error):
            if Self.isCancellation(error) { cancelled(); return }
            let url = URL(fileURLWithPath: "/文件选择器")
            let failure = ImportDiagnostics.failure(error, stage: .picker, url: url)
            publish(ImportBatchResult(failures: [failure]))
        }
    }
    func openURL(_ url: URL, library: LibraryStore) {
        consume(.success([url]), library: library)
    }
    func cancelled() {
        pickerPresented = false; awaitingImport = false; status = "已取消导入"
        feedbackTask?.cancel(); feedback = nil
        lastFeedback = nil
    }
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) ||
            (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
    }
    private func publish(_ result: ImportBatchResult) {
        let item = ImportFeedback(result: result)
        lastFeedback = item
        status = item.title
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            // Keep the inline result even if presentation is interrupted by the
            // system picker animation; wait until UIKit has dismissed the picker.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            for _ in 0..<30 {
                if !pickerPresented && !Self.hasPresentedDocumentPicker() { feedback = item; return }
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
            }
        }
    }
    private static func hasPresentedDocumentPicker() -> Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            var controller = window.rootViewController
            while let current = controller {
                if current is UIDocumentPickerViewController || current.isBeingDismissed { return true }
                controller = current.presentedViewController
            }
        }
        return false
    }
}
