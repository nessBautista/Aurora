# AuroraKeychain

macOS keychain wrapper for Aurora's API-key storage. Reads are gated behind
Touch ID (with password fallback) via `LAContext`.

*Public surface lives in `Public/`; implementation details in `Implementation/`.*

## Public API

```swift
Keychain                                         // namespace enum
Keychain.KeychainError                           // .storeFailed / .readFailed / .userCancelled / .biometryUnavailable / .locked

try     Keychain.set(service:account:value:)     // store / overwrite
try await Keychain.get(service:account:prompt:)  // read; prompts Touch ID
        Keychain.exists(service:account:)        // probe; no prompt
        Keychain.clear(service:account:)         // delete; idempotent
```

`get` is `async` because `LAContext.evaluatePolicy` suspends until the user
authenticates or cancels. `prompt:` is the user-facing string shown in the
Touch ID dialog (e.g. `"Aurora needs your Anthropic API key"`).

`set` throws on `SecItemAdd` / `SecItemUpdate` failure; `get` throws on
cancel, missing biometry, or `SecItemCopyMatching` failure. `exists` and
`clear` are non-throwing — `clear` treats "not found" as success.

## Files

| File | Stage | Holds | Access |
|---|---|---|---|
| `Keychain.swift` | **3** — I/O orchestration | `set`, `get`, `exists`, `clear`; private `authenticateForRead` (LAContext gate) | `public` |
| `Keychain+Queries.swift` | **1** — pure query builders | `makeIdentityQuery`, `makeAddQuery`, `makeUpdateAttributes`, `makeReadQuery`, `makeExistsQuery` | `internal` |
| `Keychain+Interpreters.swift` | **2** — pure status interpreters | `interpretUpdate`, `interpretAdd`, `interpretRead`, `interpretExists`, `UpdateOutcome` | `internal` |
| `Keychain+Errors.swift` | shared | `KeychainError` cases + `errorDescription` | `public` |

Only the cross-module contract is `public`. Stage 1/2 helpers are
`internal`; tests reach them via `@testable import AuroraKeychain`.

## Three stages, three roles

| Stage | Role | Semantics |
|---|---|---|
| 1 — Queries | Build the `[String: Any]` dict handed to `SecItem*` | Pure — same input, same dict, no OS calls |
| 2 — Interpreters | Map `OSStatus` to a typed outcome (success / not-found / throw) | Pure — no OS calls; testable branch-by-branch |
| 3 — Orchestration | Compose queries + interpreters + the actual `SecItem*` / `LAContext` calls | The only stage with I/O |

Stages 1 and 2 are covered by `AuroraKeychainTests` without touching the
keychain. Stage 3 is covered by a small integration suite against the real
keychain (UUID-namespaced service per test).

## The unsigned-binary constraint

The production-grade keychain protection on macOS is `kSecAttrAccessControl`
with `.userPresence` — the OS enforces biometrics inside
`SecItemCopyMatching` itself. That path requires a **signed binary** with
hardened runtime and a `keychain-access-groups` entitlement, which Aurora
doesn't have today (`swift build` output and SwiftPM test bundles are
unsigned).

Workaround: items are stored with plain `kSecAttrAccessible`, and
`Keychain.get` calls `LAContext.evaluatePolicy` itself before the read.
User-visible UX is identical; the gate moves from the kernel into our
code path.

## TOCTOU caveat

Because the stored item carries no OS-enforced access control, a hostile
process running as the user could call `SecItemCopyMatching` directly
between our `evaluatePolicy` check and our own read, and skip the prompt
entirely. Protection lives in our code path, not the keychain layer.

Acceptable for a local dev tool. Closes when we ship signed — see below.

## Migration path (signed binary)

If Aurora ever ships signed (Developer ID + hardened runtime +
`keychain-access-groups` entitlement):

1. In `Keychain+Queries.swift`, replace `kSecAttrAccessible:
   kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in `makeAddQuery` with a
   `SecAccessControl` built via `SecAccessControlCreateWithFlags`, keyed
   under `kSecAttrAccessControl`.
2. Delete the `authenticateForRead(prompt:)` call and the `LAContext`
   gate in `Keychain.swift`. The OS will present the biometric prompt
   during `SecItemCopyMatching` itself.

The TOCTOU window closes — enforcement becomes intrinsic to the read.

## References

- Apple — [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- Apple — [LAContext](https://developer.apple.com/documentation/localauthentication/lacontext)
