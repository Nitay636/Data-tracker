import MessageUI
import SwiftUI
import UIKit

enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "DataTracker"
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    /// Set by the `DEVELOPER_CONTACT_EMAIL` build setting (Config/Local.xcconfig).
    static var developerEmail: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "DeveloperContactEmail") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (value?.contains("@") ?? false) ? value : nil
    }
}

/// Settings section where the user writes to the developer. Sends through Mail.
struct ContactDeveloperSection: View {
    @Binding var isFocused: Bool
    @FocusState private var editorFocused: Bool
    @State private var message = ""
    @State private var showComposer = false
    @State private var isSending = false
    @State private var result: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Contact the developer") {
            TextField("Bugs, ideas, anything…", text: $message, axis: .vertical)
                .lineLimit(3...8)
                .focused($editorFocused)
            Button {
                send()
            } label: {
                HStack {
                    Label("Send", systemImage: "paperplane.fill")
                    Spacer()
                    if isSending { ProgressView() }
                }
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            if let result {
                Text(result).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: editorFocused) { _, focused in isFocused = focused }
        .onChange(of: isFocused) { _, focused in if !focused { editorFocused = false } }
        .sheet(isPresented: $showComposer, onDismiss: { isSending = false }) {
            MailComposer(recipient: AppInfo.developerEmail ?? "", subject: subject, body: fullBody) { sent in
                if sent {
                    message = ""
                    result = "Thanks! Your message was sent."
                }
            }
            .ignoresSafeArea()
        }
    }

    private var subject: String { "\(AppInfo.name) \(AppInfo.version) feedback" }

    private var fullBody: String {
        "\(message)\n\n—\n\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build)), iOS \(UIDevice.current.systemVersion)"
    }

    private func send() {
        editorFocused = false
        result = nil
        guard let email = AppInfo.developerEmail else {
            result = "No contact address is set in this build."
            return
        }
        isSending = true
        if MFMailComposeViewController.canSendMail() {
            showComposer = true
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: fullBody)]
        guard let url = components.url else {
            isSending = false
            return
        }
        openURL(url) { opened in
            isSending = false
            result = opened ? nil : "No mail app is set up. Write to \(email)."
        }
    }
}

private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
            controller.dismiss(animated: true)
        }
    }
}
