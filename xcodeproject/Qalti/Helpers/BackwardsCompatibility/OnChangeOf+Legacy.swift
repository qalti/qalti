//
//  LegacyOnChangeOf.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 11.03.2025.
//

import SwiftUI

extension View {

    public func legacy_onChange<V>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View where V : Equatable {
        if #available(macOS 14.0, iOS 17.0, *) {
            return self.onChange(of: value, initial: true) { oldValue, newValue in
                action(newValue)
            }
        } else {
            return self.onChange(of: value, perform: action)
        }

    }

}
