import Foundation
import SafariServices
import os.log

final class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let notificationName = Notification.Name("com.bobkitchen.ModelMeter.geminiUsageSnapshot")

    func beginRequest(with context: NSExtensionContext) {
        NSLog("ModelMeter/Gemini extension native message received")
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        let posted = postSnapshotIfPossible(message)
        NSLog("ModelMeter/Gemini extension native message result posted=%@", posted ? "true" : "false")

        let response = NSExtensionItem()
        let responseBody: [String: Any] = [
            "ok": posted,
            "receivedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if #available(macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseBody]
        } else {
            response.userInfo = ["message": responseBody]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func postSnapshotIfPossible(_ message: Any?) -> Bool {
        guard var payload = message as? [String: Any] else {
            NSLog("ModelMeter/Gemini extension ignored non-dictionary message: %@", String(describing: message))
            return false
        }
        if payload["type"] as? String == "diagnostic" {
            NSLog(
                "ModelMeter/Gemini diagnostic event=%@ source=%@ details=%@",
                payload["event"] as? String ?? "unknown",
                payload["source"] as? String ?? "unknown",
                String(describing: payload["details"] ?? [:])
            )
            return true
        }
        let source = payload["source"] as? String ?? "safari-web-extension"
        guard let items = payload["items"] as? [[String: Any]], !items.isEmpty else {
            NSLog("ModelMeter/Gemini extension ignored payload without items source=%@ keys=%@", source, payload.keys.sorted().joined(separator: ","))
            os_log(.default, "Model Meter Gemini message ignored: %@", String(describing: message))
            return false
        }

        payload["capturedAt"] = ISO8601DateFormatter().string(from: Date())
        if payload["source"] == nil {
            payload["source"] = source
        }
        NSLog("ModelMeter/Gemini extension posting snapshot source=%@ items=%ld", source, items.count)

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            NSLog("ModelMeter/Gemini extension could not serialize snapshot source=%@", source)
            return false
        }

        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: json,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
