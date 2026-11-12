import SwiftUI

struct ImportFeedbackView: View {
    let feedback: ImportFeedback
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(feedback.message).textSelection(.enabled).accessibilityIdentifier("import.result.message")
                    if !feedback.result.failures.isEmpty {
                        Button("复制错误信息") { UIPasteboard.general.string = feedback.message }
                            .buttonStyle(.bordered).accessibilityIdentifier("import.copyError")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle(feedback.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.accessibilityIdentifier("import.result.done") } }
        }.presentationDetents([.medium, .large])
    }
}
