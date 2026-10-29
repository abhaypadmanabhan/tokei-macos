import Foundation

/// Credentialed usage requests never enter a disk cache or leave their original HTTPS host.
public enum UsageHTTPSession {
    public static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return "Tokei/\(version)"
    }

    static func make(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: UsageRedirectDelegate(), delegateQueue: nil)
    }
}

private final class UsageRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url,
              let destination = request.url,
              original.scheme?.lowercased() == "https",
              destination.scheme?.lowercased() == "https",
              let host = original.host?.lowercased(),
              destination.host?.lowercased() == host,
              destination.user == nil, destination.password == nil
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
