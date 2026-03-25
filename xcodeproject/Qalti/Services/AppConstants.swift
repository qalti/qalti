//
//  AppConstants.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 19.06.2025.
//

enum AppConstants {

    static var shouldLogAgentActions: Bool {
        return false
    }

    static var defaultControlPort = 9847
    static var defaultScreenshotPort = 9848

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

}
