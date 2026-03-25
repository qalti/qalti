//
//  StabilizedMarkdownView.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import SwiftUI
import MarkdownUI

struct StabilizedMarkdownView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        let (stable, pending) = MarkdownStreamer.splitContent(from: text, isStreaming: isStreaming)

        VStack(alignment: .leading, spacing: 0) {
            if !stable.isEmpty {
                Markdown(stable)
                    .markdownTheme(.docC)
                    .textSelection(.enabled)
            }

            if !pending.isEmpty {
                Markdown(MarkdownStreamer.cleanPendingText(pending))
                    .markdownTheme(.docC)
                    .textSelection(.enabled)
            }
        }
        .animation(.linear(duration: 0.1), value: stable)
    }
}
