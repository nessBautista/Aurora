# AuroraConfig

Provider-keyed credential resolution. Walks the priority chain
`env > keychain > .env > missing` for each provider and copies the found key
into the process environment so downstream code can `getenv(...)` blindly.

*Public surface lives in `Public/`; implementation details in `Implementation/`.*

## Public API

```swift
Config.Provider                                  // enum { .anthropic, .openrouter }
Config.KeySource                                 // enum { .env, .keychain, .envFile, .missing }

try Config.setAPIKey(for:_:)                     // store in keychain
    Config.clearAPIKey(for:)                     // remove from keychain (idempotent)
    Config.keySource(for:)                       // live: where would this come from now?
    Config.originalKeySource(for:)               // snapshot: where did it come from BEFORE load ran?
    Config.resolveActiveProvider(override:envRaw:storedSelection:)  // pure selection precedence
    Config.loadEnvironment()                     // load .env + snapshot key sources (PROMPT-FREE)
await Config.loadKey(for:)                        // authenticate ONE provider's key (Touch ID)
```

`loadEnvironment()` is prompt-free (touches no keychain) — call it first, then
resolve the active provider, then `loadKey(for:)` for *only* that provider.
Splitting the load this way means `chat` prompts Touch ID for the one provider
it actually uses, not every stored provider.

`setAPIKey` throws `Keychain.KeychainError`. Other functions don't throw —
`loadKey` swallows keychain errors so a Touch ID cancel falls through rather
than aborting.

## Priority chain

| Tier | Source | Notes |
|---|---|---|
| 1 | Process env | Wins if already set. Skips the keychain prompt. |
| 2 | macOS keychain | Touch ID gated. Errors fall through to tier 3. |
| 3 | `.env` at `$(pwd)/.env` | Plain-text parser; never sourced. |
| 4 | `.missing` | Sentinel. Caller decides what to do. |

Each tier checks "is this var already in env?" before writing, so the
ordering emerges from composition. No explicit switch over the four cases.

## Files

| File | Holds | Access |
|---|---|---|
| `Config.swift` | Namespace, `Provider`, `KeySource`, `resolveKeySource` (pure), I/O orchestration | `public` (six functions + types) + `internal` helpers |
| `EnvLoader.swift` | `loadEnvFile` + private `warnMalformed` | `internal` |
| `OpRead.swift` | `opRead` — 1Password CLI invocation | `internal` |

Only the cross-module contract is `public`. Pure helpers and orphan I/O
functions are `internal`, reached from tests via `@testable import AuroraConfig`.

## `originalKeySource` — what it solves

`loadKey(for:)` calls `setenv` to copy a key into the process env. After it
runs, `keySource(for:)` will *always* report `.env` for that key — because
the var is in the env block now, regardless of where it came from.

`loadEnvironment()` snapshots the pre-load answer into a private dictionary
before any `setenv` call. `originalKeySource(for:)` reads from that
snapshot, so UI banners can honestly say "from keychain (Touch ID)" rather
than "from env" after `loadKey` ran.

## `.env` parser safety

`loadEnvFile` reads the file as text and passes values to `setenv` as
literal bytes. **No shell is invoked anywhere in the call path.** A line
like `EVIL=$(rm -rf ~)` stores the literal 14-character string in the env,
not an executed command. Verified by
`LoadEnvFileTests.testCommandSubstitutionStoredAsLiteralString` (canary file
+ literal-bytes assertion).

Discipline mirrors the bash reference parser in
`Aurora/scripts/bump-tap.sh`: regex-gated key shape
(`[A-Za-z_][A-Za-z0-9_]*`), matched-quote stripping, existing env wins,
malformed lines logged to stderr.

## `op://` references

`.env` values starting with `op://` are resolved by shelling out to
1Password's `op read` CLI. `op` is located via `/usr/bin/env`, which walks
`$PATH` — any install layout works as long as `op` is on the user's PATH.
On failure, `fatalError` includes `op`'s actual stderr in the panic text.

The reference is passed as a separate `argv[]` entry to `env`, never
interpolated into a shell command line — so a hostile reference can't
trigger command substitution; the worst case is `op` rejecting it as
malformed.


