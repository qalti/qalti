//
//  performOnMain.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 28.10.2025.
//

import Foundation

func performOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}
