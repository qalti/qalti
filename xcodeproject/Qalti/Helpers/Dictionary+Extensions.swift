//
//  Dictionary+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

extension Dictionary where Key == String, Value == Any {
    subscript(path: [String]) -> Any? {
        get {
            guard !path.isEmpty else { return nil }
            if path.count == 1 { return self[path[0]] }
            guard let subDict = self[path[0]] as? [String: Any] else { return nil }
            return subDict[Array(path[1...])]
        }
        set {
            guard !path.isEmpty else { return }
            if path.count == 1 {
                self[path[0]] = newValue
                return
            }
            var subDict = self[path[0]] as? [String: Any] ?? [:]
            subDict[Array(path[1...])] = newValue
            self[path[0]] = subDict
        }
    }
}
