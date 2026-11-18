/**
 * [INPUT]: Foundation and the `writeitdown://activate#key=<license key>` link the activation button on mac.html opens.
 * [OUTPUT]: ActivationLink.key(from:), the one validator for an incoming activation link.
 * [POS]: Pure parser at the URL-scheme boundary; the key never leaves the fragment, a log or an error message.
 * [PROTOCOL]: Keep the key pattern equal to writeitdown/buy.js `appKey`; update FirstLine/AGENTS.md when the contract changes.
 */
import Foundation

enum ActivationLink {
    static let scheme = "writeitdown"

    /// Returns the license key only for exactly `writeitdown://activate#key=<key>`: no path, query, user,
    /// port or second fragment item, and a key shaped like a Stripe Checkout session id. Anything else is nil.
    static func key(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "activate",
              url.path.isEmpty || url.path == "/", url.query == nil, url.user == nil,
              url.password == nil, url.port == nil,
              let fragment = url.fragment, fragment.hasPrefix("key="),
              let key = String(fragment.dropFirst(4)).removingPercentEncoding,
              key.count <= 100, key.hasPrefix("cs_test_") || key.hasPrefix("cs_live_"),
              key.dropFirst(8).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
              key.count > 8 else { return nil }
        return key
    }
}
