//
//  AppDelegate.swift
//  iOS (App)
//
//  Created by Justin Garcia on 2026/07/30.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-umete-screenshot-demo") {
            ScreenshotDemo.seed()
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

}

#if DEBUG
/// Made-up answers for the App Store screenshots (AppStoreScreenshots/), loaded by a
/// debug build launched with `-umete-screenshot-demo`. They replace whatever is saved,
/// skip onboarding, and turn iCloud sync off so nothing reaches a real account.
enum ScreenshotDemo {
    static func seed() {
        CloudSync.isEnabled = false
        OnboardingStore.isComplete = true
        func text(_ label: String, _ value: String, autocomplete: String = "", type: String? = nil, extra: [String: Any] = [:]) -> [String: Any] {
            var answer: [String: Any] = [
                "answerID": UUID().uuidString, "userLabel": label, "accessibleName": label, "label": label,
                "kind": "text", "inputType": "text", "value": value
            ]
            if !autocomplete.isEmpty { answer["autocomplete"] = autocomplete }
            if let type { answer["answerType"] = type }
            return answer.merging(extra) { $1 }
        }
        func aggregate(_ type: String, _ label: String, _ value: [String: Any]) -> [String: Any] {
            ["answerID": UUID().uuidString, "answerType": type, "userLabel": label, "accessibleName": label,
             "label": label, "kind": "aggregate", "inputType": "", "value": value.merging(["version": 1]) { $1 }]
        }
        // Addresses and contacts first: the Saved Data list shows about six answers before it scrolls.
        let answers: [[String: Any]] = [
            aggregate("address", "Home", [
                "addressLine1": "1-2-3 Jingumae", "locality": "Shibuya-ku", "administrativeArea": "Tokyo",
                "postalCode": "150-0001", "countryCode": "JP", "countryName": "Japan"
            ]),
            aggregate("contact", "Dr. Anita Patel", [
                "category": "doctor", "name": "Dr. Anita Patel", "role": "Cardiologist", "phone": "03-5555-0200"
            ]),
            aggregate("contact", "Dr. Sakura Ito", [
                "category": "doctor", "name": "Dr. Sakura Ito", "role": "Primary care", "phone": "03-1234-5678"
            ]),
            aggregate("contact", "Taro Yamada", [
                "category": "emergencyContact", "name": "Taro Yamada", "role": "Brother", "phone": "080-1111-2222"
            ]),
            text("Passport number", "TK1234567"),
            text("First name", "Hanako", autocomplete: "given-name"),
            text("Last name", "Yamada", autocomplete: "family-name"),
            text("Email", "hanako@example.com", autocomplete: "email", extra: ["inputType": "email"]),
            text("Phone", "90-1234-5678", autocomplete: "tel", type: "phone", extra: ["inputType": "tel", "countryCode": "81"]),
            text("Date of birth", "1990-04-12", autocomplete: "bday", type: "date"),
            text("Gender", "Female", type: "gender"),
            text("Frequent flyer number", "NH1234567890")
        ]
        try? AnswerStore.save(answers, markingChanges: false)
    }
}
#endif
