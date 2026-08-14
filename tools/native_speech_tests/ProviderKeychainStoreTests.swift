import Foundation

nonisolated protocol ProviderCredentialReading: Sendable {
    func readCredential(for keyRef: String) throws -> String?
}

@main
private struct ProviderKeychainStoreTests {
    static func main() throws {
        var checks = 0

        let deepSeek = ProviderKeychainStore.location(
            for: ProviderKeychainStore.keyRef
        )
        expect(
            deepSeek?.service == "com.eterna.aftelle.provider.deepseek"
                && deepSeek?.account == "primary-text-llm",
            "DeepSeek mapping remains unchanged",
            checks: &checks
        )

        let stepFun = ProviderKeychainStore.location(
            for: ProviderKeychainStore.stepFunKeyRef
        )
        expect(
            stepFun?.service == "com.eterna.aftelle.provider.stepfun"
                && stepFun?.account == "stepfun_realtime_api_key",
            "StepFun mapping is independent",
            checks: &checks
        )
        expect(
            deepSeek?.service != stepFun?.service
                && deepSeek?.account != stepFun?.account,
            "Provider credentials cannot overlap",
            checks: &checks
        )
        let qwen = ProviderKeychainStore.location(
            for: ProviderKeychainStore.qwenKeyRef
        )
        expect(
            qwen?.service == "com.eterna.aftelle.provider.qwen"
                && qwen?.account == "qwen_realtime_credential",
            "Qwen workspace and API Key use an independent Keychain item",
            checks: &checks
        )
        expect(
            qwen?.service != stepFun?.service
                && qwen?.account != stepFun?.account,
            "Qwen and StepFun credentials cannot overlap",
            checks: &checks
        )
        expect(
            ProviderKeychainStore.location(
                for: "keychain://unsupported/reference"
            ) == nil,
            "unsupported reference is rejected",
            checks: &checks
        )

        let store = ProviderKeychainStore()
        expect(
            !store.exists(for: "keychain://unsupported/reference"),
            "unsupported reference never reports present",
            checks: &checks
        )
        let status = store.exists(for: ProviderKeychainStore.stepFunKeyRef)
            ? "PRESENT"
            : "MISSING"
        let qwenStatus = store.exists(for: ProviderKeychainStore.qwenKeyRef)
            ? "PRESENT"
            : "MISSING"
        print("provider_keychain_checks=\(checks)")
        print("stepfun_keychain_status=\(status)")
        print("qwen_keychain_status=\(qwenStatus)")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        checks: inout Int
    ) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
