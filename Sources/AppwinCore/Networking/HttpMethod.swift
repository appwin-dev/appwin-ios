import Foundation

public enum HttpMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
  case patch = "PATCH"
}
