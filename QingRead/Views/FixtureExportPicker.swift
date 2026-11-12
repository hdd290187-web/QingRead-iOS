#if DEBUG
import SwiftUI
import UIKit

// Creates fixture items via the real LocalStorage File Provider UI. This is
// test setup only; imports are always performed through BookDocumentPicker.
struct FixtureExportPicker: UIViewControllerRepresentable {
    let source: URL
    let completion: (Result<[URL], Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [source], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<[URL], Error>) -> Void
        init(completion: @escaping (Result<[URL], Error>) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(.success(urls)) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(.failure(CocoaError(.userCancelled))) }
    }
}
#endif
