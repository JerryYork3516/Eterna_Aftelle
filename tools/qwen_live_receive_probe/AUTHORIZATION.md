# Online probe authorization

These are DEBUG/test tools, not the production app. A test upload still needs a bounded user-approved batch. macOS Keychain permission is separate from upload consent and from Codex command approval.

## Build once, reuse the same executable

Both runners cache binaries in ignored `.build/qwen-live-probes/`. The cache key includes the source contents, compiler/version, SDK, compilation arguments, builder and signing identity. Unchanged input reuses the exact executable; changed input builds a new version. Every reuse verifies its signature. Each run retains isolated diagnostics and a `probe` symlink to its actual executable.

For stable identity across versions, set `AFTELLE_PROBE_SIGNING_IDENTITY` to the SHA-1 fingerprint of an existing valid code-signing certificate (not a password or API Key). The continuous tool has identifier `com.eterna.aftelle.tests.qwen.continuous`; the receive tool has a separate identifier. The certificate fingerprint is public metadata. Do not grant every application access to the keychain item.

```sh
# Set AFTELLE_PROBE_SIGNING_IDENTITY locally to the chosen certificate fingerprint first.
bash tools/qwen_live_receive_probe/run-continuous.sh --build-only
```

Build-only does not read the Qwen credential or start a Provider connection. Signing can itself require local access to the certificate's private key; the signing command has a 30-second watchdog and fails rather than silently falling back to an unsigned build. No signing certificate is created and no Keychain ACL is modified by these scripts. Without a signing identity, builds remain ad hoc; caching then only stabilizes an unchanged binary, not identity across changed versions.

## One attended authorization step, no audio upload

With the signing variable set, while the user is present:

```sh
bash tools/qwen_live_receive_probe/run-continuous.sh --authorize-keychain --allow-keychain-interaction --seconds 30
```

This reads only the configured Qwen credential through Keychain, records status codes (never the value), releases the in-process cached reference, and exits before creating any Provider transport. If macOS offers a persistent permission choice, the user must review the requesting test program and specific Qwen item. Success of this command only proves that access was granted for this call, not that future unattended access is guaranteed.

## Unattended runs

Before any audio upload, check actual access with the signed tool in a fresh process:

```sh
bash tools/qwen_live_receive_probe/run-continuous.sh --check-keychain --seconds 15
```

This mode rejects interactive permission and audio-upload flags. It only attempts a noninteractive credential read, discards the result and exits before any Provider connection. A failure means an attended Keychain authorization/unlock is still needed; do not retry in interactive mode while the user is away.

Run an explicitly approved `--live` batch with the same signing identity, approved PCM and time/round limits, **without** `--allow-keychain-interaction`. The default policy prohibits Keychain UI; denied/locked/missing access produces `credentialUnavailable` rather than waiting for a password. There is still an outer process watchdog.

A successful read is reused only in that reader's memory during the bounded test; concurrent reads are serialized and different key references are isolated. Failed reads are not cached. The continuous test releases its cache when it ends; a new process must pass Keychain access again. This is not guaranteed secure erasure of Swift/String memory. Credentials are never exported to files, environment variables, logs or command arguments. Existing production Provider/Runtime ownership and all barge-in acceptance rules are unchanged.

Persistent unattended access must be verified after the attended step and may be interrupted by a locked keychain, certificate changes/revocation or changed access policy. Do not claim a no-popup online PASS from offline tests alone.
