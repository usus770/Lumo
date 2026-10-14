// SafariExtension/SafariExtensionHandler.swift
// Scaffold handler for Safari Web Extension native messaging.

import Foundation
import SafariServices

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems[0] as! NSExtensionItem
        let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any]
        
        NSLog("[SafariExtensionHandler] Received message: \(String(describing: message))")
        
        // Forward message to Lumo app via local loopback endpoint
        if let payload = message {
            Task {
                guard let url = URL(string: "http://127.0.0.1:19847/api/now-playing") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let data = try? JSONSerialization.data(withJSONObject: payload) {
                    request.httpBody = data
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "received"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
