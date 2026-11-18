# Leo memory cryptography dependency notices

The v0.26.0 memory privacy work adds the following direct cryptography dependencies:

| Package | Version | License declaration | Use in Leo |
|---|---:|---|---|
| `cryptography` (Dart) | `2.9.0` | Apache-2.0 | AES-256-GCM encrypted portable memory backup and PBKDF2-HMAC-SHA256 passphrase key derivation |
| `aes-gcm` (Rust) | `0.10.3` | MIT OR Apache-2.0 | Authenticated AES-256-GCM encryption of memory payload fields |
| `base64` (Rust) | `0.22.1` | MIT OR Apache-2.0 | Encoding authenticated ciphertext envelopes |
| `hmac` (Rust) | `0.12.1` | MIT OR Apache-2.0 | HMAC-SHA256 keyed record fingerprint implementation |
| `hkdf` (Rust) | `0.12.4` | MIT OR Apache-2.0 | Derives a separate subkey for memory deduplication fingerprints, isolating HMAC from the AES-GCM key |
| `rand` (Rust) | `0.8.5` | MIT OR Apache-2.0 | Operating-system random source (`OsRng`) for per-field nonces |

Leo elects to distribute the Apache-2.0 license text in `licenses/Apache-2.0.txt` for the above dual-licensed Rust crates and the Dart package. Upstream license declarations were checked against the package metadata/source pages during v0.26.0 review. Transitive dependency notices must be regenerated from resolved lockfiles in CI before a binary release; this source package does not contain generated `Cargo.lock` or `pubspec.lock` files.
