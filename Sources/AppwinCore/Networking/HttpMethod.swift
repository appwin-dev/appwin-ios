import Foundation

public enum HttpMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case delete = "DELETE"
  case patch = "PATCH"
}
