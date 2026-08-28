import Foundation

public enum AppwinApiError: Error {
  case network(Error)
  case urlSession(URLError)
  case decodingFailed(Error)
  case encodingFailed(Error)
  case invalidUrl
  case http(status: Int)
}

extension AppwinApiError {
  /// End-user message, separating a client-side problem (connectivity) from a
  /// server-side one.
  public var userMessage: String {
    switch self {
    // Client side: no network, the request never left.
    case .network, .urlSession:
      return "Problème de connexion. Vérifiez votre réseau et réessayez."
    // Server side: it crashed.
    case .http(let status) where (500...599).contains(status):
      return "Le serveur a rencontré un problème. Réessayez dans un instant."
    // Server side: it refused.
    case .http:
      return "L'envoi a été refusé par le serveur."
    // Encoding, URL or decoding: should not happen in production.
    case .invalidUrl, .encodingFailed, .decodingFailed:
      return "Une erreur inattendue est survenue."
    }
  }
}

extension AppwinApiError {
  /// `true` when the request was cancelled (`NSURLErrorCancelled`): app
  /// backgrounded, screen closed, hot reload. Not a real failure, so swallow it
  /// rather than showing it to the user.
  public var isCancelled: Bool {
    switch self {
    case .network(let error):
      return (error as NSError).code == NSURLErrorCancelled
    case .urlSession(let error):
      return error.code == .cancelled
    default:
      return false
    }
  }
}

extension Error {
  /// `userMessage` when this is an `AppwinApiError`, a generic message
  /// otherwise. A raw `localizedDescription` never reaches the screen.
  public var appwinUserMessage: String {
    (self as? AppwinApiError)?.userMessage ?? "Une erreur est survenue. Réessayez."
  }

  /// Cancellation, whether already wrapped in `AppwinApiError` or still raw.
  public var isAppwinCancelled: Bool {
    if let apiError = self as? AppwinApiError { return apiError.isCancelled }
    return (self as NSError).code == NSURLErrorCancelled
  }
}
