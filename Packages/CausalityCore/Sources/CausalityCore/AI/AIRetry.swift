import Foundation

/// 一次请求失败之后要不要再来一次，以及怎么把系统错误翻成作者看得懂的话。
/// 断开重连、HTTP/2 连接被复用后失效、Wi-Fi 切网都会表现为一条 URLError，
/// 这些情况重发一次几乎总能过，没必要把提示推到作者面前。
public enum AIRetry {
    /// 总共试几次（含第一次）。
    public static let maxAttempts = 3

    /// 第 attempt 次失败后等多久。attempt 从 0 开始。
    public static func delay(after attempt: Int) -> Duration {
        let millis = 600 * (1 << min(attempt, 3))
        return .milliseconds(millis)
    }

    public static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .secureConnectionFailed,
                 .badServerResponse,
                 .resourceUnavailable,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                return true
            default:
                return false
            }
        }
        if let aiError = error as? AIError {
            switch aiError {
            case .timeout, .transport:
                return true
            case let .http(status, _):
                return status >= 500
            default:
                return false
            }
        }
        return false
    }

    /// 把底层的 URLError 换成带下一步建议的 AIError。已是 AIError 的原样返回。
    public static func map(_ error: Error) -> AIError {
        if let aiError = error as? AIError { return aiError }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else {
            return .transport(error.localizedDescription)
        }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .networkConnectionLost:
            return .transport(CoreText.text("连接被中途断开（对方或中间网关关了这条流）。重发一次；反复出现就换一个模型或服务。"))
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .transport(CoreText.text("这台机器现在没有可用网络，或者流量被系统限制。检查 Wi-Fi / 代理后再发。"))
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .transport(CoreText.format("连不上 %@：域名解析或建立连接就失败了。多半要开代理，或者服务地址变了。", urlError.failingURL?.host() ?? CoreText.text("服务地址")))
        case .secureConnectionFailed:
            return .transport(CoreText.text("TLS 握手失败。如果走的是本地代理，检查代理的证书。"))
        case .badServerResponse:
            return .transport(CoreText.text("服务返回了无法解析的响应，通常是网关拦截或代理改写。"))
        default:
            return .transport(CoreText.format("%@（%lld）", urlError.localizedDescription, urlError.code.rawValue))
        }
    }
}
