//
//  OpenRouterModels.swift
//  Generated on 2026-07-26 19:17:45
//
//  Free vision models: 8
//  Cheap vision models: 175
//  Free text-only models: 10
//

import Foundation

enum OpenRouterModel: String, CaseIterable {
    // Default model (paid)
    case defaultModel = "anthropic/claude-3.5-sonnet"

    // Vision models (free or very cheap)
    case nvidia_nemotron_3_5_content_safety_free = "nvidia/nemotron-3.5-content-safety:free"
    case nvidia_nemotron_3_nano_omni_30b_a3b_reasoning_free = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
    case google_gemma_4_26b_a4b_it_free = "google/gemma-4-26b-a4b-it:free"
    case google_gemma_4_31b_it_free = "google/gemma-4-31b-it:free"
    case google_lyria_3_pro_preview = "google/lyria-3-pro-preview"
    case google_lyria_3_clip_preview = "google/lyria-3-clip-preview"
    case openrouter_free = "openrouter/free"
    case nvidia_nemotron_nano_12b_v2_vl_free = "nvidia/nemotron-nano-12b-v2-vl:free"

    var displayName: String {
        switch self {
        case .defaultModel:
            return "Claude 3.5 Sonnet (Default - Paid)"
        case .nvidia_nemotron_3_5_content_safety_free:
            return "NVIDIA: Nemotron 3.5 Content Safety (free) (FREE)"
        case .nvidia_nemotron_3_nano_omni_30b_a3b_reasoning_free:
            return "NVIDIA: Nemotron 3 Nano Omni (free) (FREE)"
        case .google_gemma_4_26b_a4b_it_free:
            return "Google: Gemma 4 26B A4B  (free) (FREE)"
        case .google_gemma_4_31b_it_free:
            return "Google: Gemma 4 31B (free) (FREE)"
        case .google_lyria_3_pro_preview:
            return "Google: Lyria 3 Pro Preview (FREE)"
        case .google_lyria_3_clip_preview:
            return "Google: Lyria 3 Clip Preview (FREE)"
        case .openrouter_free:
            return "Free Models Router (FREE)"
        case .nvidia_nemotron_nano_12b_v2_vl_free:
            return "NVIDIA: Nemotron Nano 12B 2 VL (free) (FREE)"
        }
    }

    var maxCompletionTokens: Int {
        switch self {
        case .defaultModel:
            return 60
        case .nvidia_nemotron_3_5_content_safety_free:
            return 8192
        case .nvidia_nemotron_3_nano_omni_30b_a3b_reasoning_free:
            return 65536
        case .google_gemma_4_26b_a4b_it_free:
            return 32768
        case .google_gemma_4_31b_it_free:
            return 32768
        case .google_lyria_3_pro_preview:
            return 65536
        case .google_lyria_3_clip_preview:
            return 65536
        case .openrouter_free:
            return 60
        case .nvidia_nemotron_nano_12b_v2_vl_free:
            return 128000
        }
    }

    var isVisionCapable: Bool {
        return true  // All models in this enum support vision
    }

    var isFree: Bool {
        switch self {
        case .defaultModel:
            return false
        case .nvidia_nemotron_3_5_content_safety_free:
            return true
        case .nvidia_nemotron_3_nano_omni_30b_a3b_reasoning_free:
            return true
        case .google_gemma_4_26b_a4b_it_free:
            return true
        case .google_gemma_4_31b_it_free:
            return true
        case .google_lyria_3_pro_preview:
            return true
        case .google_lyria_3_clip_preview:
            return true
        case .openrouter_free:
            return true
        case .nvidia_nemotron_nano_12b_v2_vl_free:
            return true
        }
    }

    var estimatedCostPer1KTokens: Double {
        switch self {
        case .defaultModel:
            return 0.036  // Approximate for Claude 3.5 Sonnet
        case .nvidia_nemotron_3_5_content_safety_free:
            return 0.0
        case .nvidia_nemotron_3_nano_omni_30b_a3b_reasoning_free:
            return 0.0
        case .google_gemma_4_26b_a4b_it_free:
            return 0.0
        case .google_gemma_4_31b_it_free:
            return 0.0
        case .google_lyria_3_pro_preview:
            return 0.0
        case .google_lyria_3_clip_preview:
            return 0.0
        case .openrouter_free:
            return 0.0
        case .nvidia_nemotron_nano_12b_v2_vl_free:
            return 0.0
        }
    }
}
