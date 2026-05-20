# AuroraKeychain

macOS keychain wrapper for Aurora's API-key storage. Reads are gated behind
Touch ID (with password fallback) via `LAContext`.

## Why this module exists

Aurora needs a place to store provider API keys (Anthropic today, OpenRouter
later) locked behind the user's biometrics — same UX as `git` storing
credentials, `aws` storing tokens. The macOS keychain is the right place for
that; this module is the thin wrapper that knows how to talk to it.

## The unsigned-binary constraint

The production-grade keychain protection on macOS is `kSecAttrAccessControl`
with `.userPresence` — the OS enforces biometric authentication at read time,
inside `SecItemCopyMatching` itself.

That path requires a **signed binary** with a hardened runtime and a
`keychain-access-groups` entitlement. Aurora ships as a Swift package
consumed by unsigned binaries (`swift build` output, SwiftPM test bundles),
so the OS-enforced path is unavailable.

We work around the constraint with the **LAContext approach**:

1. Items are stored with plain `kSecAttrAccessible` (no entitlements needed).
2. `get()` calls `LAContext.evaluatePolicy` itself before doing the keychain
 read, so the Touch ID / password prompt still appears.

User-visible UX is identical. The protection is enforced by our code rather
than the OS — see the TOCTOU caveat below.

## TOCTOU caveat

Because the keychain item carries no OS-enforced access control, a hostile
process running as the user could call `SecItemCopyMatching` directly between
our `evaluatePolicy` check and our own read, and skip the prompt entirely.
Protection lives in our code path, not at the keychain layer.

Acceptable for a local dev tool. It's the reason this approach should be
migrated away from once Aurora ships signed — see "Migration path" below.

## File layout

Four Swift files, plus this README. Internally, the code is split into three
**stages**: pure query builders, pure status interpreters, and I/O
orchestration. The orchestration stage is the only one that actually calls
into `SecItem*` / `LAContext`; the other two are pure functions composed
into it.

| File | Stage | Contents | I/O? | Access |
|---|---|---|---|---|
| `Keychain.swift` | **Stage 3** — I/O orchestration | `set`, `get`, `exists`, `clear`; private `authenticateForRead` (LAContext gate) | Yes |
`public` |
| `Keychain+Queries.swift` | **Stage 1** — pure query builders | `makeIdentityQuery`, `makeAddQuery`, `makeUpdateAttributes`, `makeReadQuery`,
`makeExistsQuery` | No | `internal` |
| `Keychain+Interpreters.swift` | **Stage 2** — pure status interpreters | `interpretUpdate`, `interpretAdd`, `interpretRead`, `interpretExists`,
`UpdateOutcome` | No | `internal` |
| `Keychain+Errors.swift` | shared | `KeychainError` cases and `errorDescription` | No | `public` |

Stages 1 and 2 are pure: identical inputs produce identical outputs, no OS
calls. `AuroraKeychainTests` covers every branch of every interpreter and
the shape of every query builder, without ever touching the keychain. Stage 3
is the only file with I/O; it's covered by a small set of integration tests
against the real keychain (UUID-namespaced service per test).

> The pattern (separating pure helpers from I/O orchestration) was developed
> in `aur_dev/labs/001_keychain`. The lab's side-by-side comparison shows the
> same behavior in both inline and split forms.

## Access discipline

The cross-module contract is intentionally narrow:

- **`public`** — `Keychain` (the namespace enum), its four Stage 3 functions,
and `KeychainError`. Everything other Aurora modules can depend on.
- **`internal`** — Stage 1 builders and Stage 2 interpreters. They exist as
testing seams; `AuroraKeychainTests` reaches them via `@testable import
AuroraKeychain`. Other modules can't (and shouldn't) call them directly.

Keeping the helpers `internal` means we can rename or restructure them
without breaking any caller outside this module.

## Public surface

Four functions on `Keychain`:

```swift
try Keychain.set(service:account:value:)            // store / overwrite
try await Keychain.get(service:account:prompt:)     // read (prompts biometry)
  Keychain.exists(service:account:)               // probe (no biometry)
  Keychain.clear(service:account:)                // delete (idempotent)

prompt: is the user-facing string shown in the Touch ID dialog
(e.g. "Aurora needs your Anthropic API key").

Errors flow through Keychain.KeychainError:

- .storeFailed(OSStatus) — SecItemAdd / SecItemUpdate returned non-success.
- .readFailed(OSStatus)  — SecItemCopyMatching returned non-success.
- .userCancelled         — user dismissed the Touch ID prompt.
- .biometryUnavailable   — no biometry or passcode configured.
- .locked                — keychain is locked (errSecInteractionNotAllowed).

Migration path (signed binary)

If Aurora ever ships signed (Apple Developer ID + hardened runtime +
keychain-access-groups entitlement):

1. In Keychain+Queries.swift, replace the kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly line in makeAddQuery with
a SecAccessControl object built via SecAccessControlCreateWithFlags,
keyed under kSecAttrAccessControl.
2. Delete the authenticateForRead(prompt:) call and the LAContext gate
in Keychain.swift. The OS will present the biometric prompt during
SecItemCopyMatching itself.
3. The TOCTOU window closes — enforcement becomes intrinsic to the read.

Design decisions recorded elsewhere

- Stage 2 interpreters — Result vs throws + custom enum (../../../../aur_dev/specs/discussions/2026-05-20_keychain-interpreters-result-vs-throws.md)
— why throws + UpdateOutcome won over Result<Success, Failure>.

References
- Apple docs: Keychain Services (https://developer.apple.com/documentation/security/keychain_services)
- Apple docs: LAContext (https://developer.apple.com/documentation/localauthentication/lacontext)

