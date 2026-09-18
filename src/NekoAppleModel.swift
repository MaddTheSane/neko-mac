//  NekoAppleModel.swift
//
//  The bridge to Apple's on-device model.
//
//  FoundationModels is a Swift-only framework — it ships no headers — so this
//  is the one file in the project that has to be Swift. It exposes a plain
//  Objective-C class, which the rest of the app talks to like anything else.
//
//  The model is the same one behind Apple Intelligence: it runs on the Mac, it
//  costs nothing, it needs no key, and it works offline. It exists only on
//  macOS 26 and later, on hardware that supports Apple Intelligence, with the
//  feature switched on — hence every check below.

import Foundation
import FoundationModels

public final class NekoAppleModel: NSObject {

    private var work: Task<Void, Never>?

    /// Whether the model can answer right now.
    @objc public class func isAvailable() -> Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Why it cannot, in words the preferences can show. nil when it can.
    @objc public class func unavailableReason() -> String? {
        guard #available(macOS 26.0, *) else {
            return NSLocalizedString("Needs macOS 26 or newer", comment: "")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let why):
            switch why {
            case .deviceNotEligible:
                return NSLocalizedString("This Mac does not support Apple Intelligence", comment: "")
            case .appleIntelligenceNotEnabled:
                return NSLocalizedString("Turn Apple Intelligence on in System Settings", comment: "")
            case .modelNotReady:
                return NSLocalizedString("The model is still downloading", comment: "")
            @unknown default:
                return NSLocalizedString("The model is not available", comment: "")
            }
        @unknown default:
            return NSLocalizedString("The model is not available", comment: "")
        }
    }

    /// Answers, or explains itself. The completion always arrives on the main
    /// thread, exactly once, and never after `cancel()`.
    @objc public func ask(_ question: String,
                          instructions: String,
                          completion: @escaping (String?, String?) -> Void) {
        guard #available(macOS 26.0, *) else {
            completion(nil, NekoAppleModel.unavailableReason())
            return
        }
        cancel()
        work = Task { [weak self] in
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: question)
                if Task.isCancelled { return }
                await MainActor.run { completion(response.content, nil) }
            } catch {
                if Task.isCancelled { return }
                let message = error.localizedDescription
                await MainActor.run { completion(nil, message) }
            }
            self?.work = nil
        }
    }

    /// Answers piece by piece: `partial` receives the whole answer so far, as
    /// often as the model produces more, and `completion` closes it. The first
    /// words arrive in a fraction of the time the full answer takes, which is
    /// the difference between a cat that is thinking and a cat that is stuck.
    @objc public func askStreaming(_ question: String,
                                  instructions: String,
                                  partial: @escaping (String) -> Void,
                                  completion: @escaping (String?, String?) -> Void) {
        guard #available(macOS 26.0, *) else {
            completion(nil, NekoAppleModel.unavailableReason())
            return
        }
        cancel()
        work = Task { [weak self] in
            do {
                let session = LanguageModelSession(instructions: instructions)
                var latest = ""
                for try await snapshot in session.streamResponse(to: question) {
                    if Task.isCancelled { return }
                    latest = snapshot.content
                    let sofar = latest
                    await MainActor.run { partial(sofar) }
                }
                if Task.isCancelled { return }
                let whole = latest
                await MainActor.run { completion(whole, nil) }
            } catch {
                if Task.isCancelled { return }
                let message = error.localizedDescription
                await MainActor.run { completion(nil, message) }
            }
            self?.work = nil
        }
    }

    @objc public func cancel() {
        work?.cancel()
        work = nil
    }
}
