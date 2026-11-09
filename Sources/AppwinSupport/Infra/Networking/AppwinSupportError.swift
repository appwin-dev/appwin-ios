//
//  AppwinSupportError.swift
//  AppwinSupport
//
//  Created by Eliott on 22/05/2026.
//

public enum AppwinSupportError: Error {
  case appIdNotSet(String)
  /// `initialize(appId:)` was not called before a login or identify.
  case notInitialized
  /// A required argument is empty or invalid, such as a blank externalId.
  case invalidArgument(String)
}

