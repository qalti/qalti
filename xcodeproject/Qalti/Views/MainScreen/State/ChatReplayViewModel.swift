//
//  ChatReplayViewModel.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 18.11.25.
//

import SwiftUI

@MainActor
final class ChatReplayViewModel: ObservableObject {
    @Published var isUserScrolledToBottom = true
    @Published var scrollViewHeight: CGFloat = 0
    @Published var contentHeight: CGFloat = 0
}
