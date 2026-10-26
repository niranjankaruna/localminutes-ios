import Foundation
import CryptoKit

/// Explicit formats preserve prior behavior; automatic validates actual GGUF
/// architecture/template metadata against the supported canonical envelopes.
public enum LocalSummaryChatFormat: Equatable, Sendable {
    case qwen, qwen3, qwen3Instruct2507, phi3, phi4Mini, gemma3, gemma4, automatic

    /// These fingerprints come from the exact reviewed GGUF headers, not model
    /// names or a heuristic substring in arbitrary Jinja. The C template helper
    /// does not interpret Jinja and cannot faithfully render Phi-4 Mini/Gemma 4.
    /// Only these bounded, text-only canonical profiles are accepted.
    static func validated(architecture: String, template: String,
                          requested: LocalSummaryChatFormat) throws -> LocalSummaryChatFormat {
        guard !template.isEmpty, template.utf8.count <= 65_536, !template.utf8.contains(0) else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        let digest = SHA256.hash(data: Data(template.utf8)).map { String(format: "%02x", $0) }.joined()
        let resolved: LocalSummaryChatFormat
        switch (architecture, digest) {
        case ("qwen2", "d5495a1e5db0611132a97e46a65dbb64a642a499421228b9c8b93229097fa9a4"): resolved = .qwen
        case ("qwen3", "57f1fd00f0013a2be96aa79b857391f27e23df5b5f847072b524c897e24d0361"): resolved = .qwen3
        case ("qwen3", "c979e0e71a3e21b8f208e6ab120d5cb29327885f29d2a8b18fda67a723798e18"): resolved = .qwen3Instruct2507
        case ("phi3", "268b6082ceb7176dc6ed80557a2f7837f9f0339592fbee677d405a553af15f88"): resolved = .phi3
        case ("phi3", "46bcd040271c497ee454c7ff577615abf2853ba2971b472e417468ac2bf47f52"): resolved = .phi4Mini
        case ("gemma3", "7de1c58e208eda46e9c7f86397df37ec49883aeece39fb961e0a6b24088dd3c4"): resolved = .gemma3
        case ("gemma4", "0a2c8073c878ab1da004bee933a998606537bbb62016310352c7285c3f01c5b5"): resolved = .gemma4
        default: throw LocalSummaryRuntimeError.invalidModel
        }
        // An old unprofiled installation may use only its original two formats.
        guard requested == resolved || (requested == .automatic && (resolved == .qwen || resolved == .phi3)) else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        return resolved
    }

    func format(systemPrompt: String, userPrompt: String, maximumUTF8Bytes: Int = 65_536) throws -> String {
        guard maximumUTF8Bytes > 0 else { throw SummaryPromptFormattingError.invalidByteLimit }
        guard systemPrompt.utf8.count <= maximumUTF8Bytes, userPrompt.utf8.count <= maximumUTF8Bytes else {
            throw SummaryPromptFormattingError.promptTooLong
        }
        let envelope: String
        switch self {
        case .qwen:
            envelope = try SummaryPromptFormatter.format(systemPrompt: systemPrompt, userPrompt: userPrompt,
                                                         maximumUTF8Bytes: maximumUTF8Bytes)
        case .qwen3Instruct2507:
            envelope = try SummaryPromptFormatter.format(systemPrompt: Self.escape(systemPrompt), userPrompt: Self.escape(userPrompt),
                                                         maximumUTF8Bytes: maximumUTF8Bytes)
        case .qwen3:
            // Exact official enable_thinking=false prefill. Grammar sampling can
            // start with JSON immediately, without asking it to emit reasoning.
            envelope = try SummaryPromptFormatter.format(systemPrompt: Self.escape(systemPrompt), userPrompt: Self.escape(userPrompt),
                                                         maximumUTF8Bytes: maximumUTF8Bytes)
                + "<think>\n\n</think>\n\n"
        case .phi3:
            envelope = try Phi3SummaryPromptFormatter.format(systemPrompt: systemPrompt, userPrompt: userPrompt,
                                                             maximumUTF8Bytes: maximumUTF8Bytes)
        case .phi4Mini:
            envelope = "<|system|>\(Self.escape(systemPrompt))<|end|>"
                + "<|user|>\(Self.escape(userPrompt))<|end|><|assistant|>"
        case .gemma3:
            // Gemma 3 has no system role. Its reviewed template folds the policy
            // into the first user turn; the tokenizer adds the single BOS token.
            let system = Self.escape(systemPrompt)
            let user = Self.escape(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            envelope = "<start_of_turn>user\n\(system)\n\n\(user)<end_of_turn>\n<start_of_turn>model\n"
        case .gemma4:
            // Google's canonical text-only template, enable_thinking=false,
            // no tools, system + user messages, add_generation_prompt=true.
            let system = Self.escape(systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            let user = Self.escape(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            envelope = "<|turn>system\n\(system)<turn|>\n<|turn>user\n\(user)<turn|>\n<|turn>model\n"
        case .automatic: throw LocalSummaryRuntimeError.invalidModel
        }
        guard envelope.utf8.count <= maximumUTF8Bytes else { throw SummaryPromptFormattingError.promptTooLong }
        return envelope
    }

    private static func escape(_ value: String) -> String {
        // Escape reviewed control markers inside evidence without changing
        // ordinary less-than comparisons or HTML tags in meeting content.
        var escaped = value.replacingOccurrences(of: "<|", with: "<\u{200B}|")
        for marker in ["<turn|>", "<channel|>", "<tool|>", "<tool_call|>", "<tool_response|>",
                       "<start_of_turn>", "<end_of_turn>", "<start_of_image>", "<end_of_image>",
                       "<bos>", "<eos>", "<pad>", "<s>", "</s>", "<think>", "</think>"] {
            escaped = escaped.replacingOccurrences(of: marker, with: "<\u{200B}" + marker.dropFirst())
        }
        return escaped
    }
}

public enum Phi3SummaryPromptFormatter {
    /// The pinned Phi GGUF template handles user/assistant turns only. Fold the
    /// policy into that user content; native add_special supplies its BOS token.
    public static func format(systemPrompt: String, userPrompt: String,
                              maximumUTF8Bytes: Int = 65_536) throws -> String {
        guard maximumUTF8Bytes > 0 else { throw SummaryPromptFormattingError.invalidByteLimit }
        guard systemPrompt.utf8.count <= maximumUTF8Bytes,
              userPrompt.utf8.count <= maximumUTF8Bytes else {
            throw SummaryPromptFormattingError.promptTooLong
        }
        let system = escape(systemPrompt)
        let user = escape(userPrompt)
        let envelope = "<|user|>\n\(system)\n\n\(user)<|end|>\n<|assistant|>\n"
        guard envelope.utf8.count <= maximumUTF8Bytes else { throw SummaryPromptFormattingError.promptTooLong }
        return envelope
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "<|", with: "<\u{200B}|")
            .replacingOccurrences(of: "<s>", with: "<\u{200B}s>")
    }
}
