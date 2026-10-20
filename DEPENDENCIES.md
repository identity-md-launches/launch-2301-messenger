# Vendored dependencies

These ordinary source files are included for builds without network access. No submodules or package installation are required. Upstream sources are unmodified. SHA256SUMS in each dependency directory records the included files.

OpenZeppelin/openzeppelin-contracts v5.1.0
Source: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
Archive SHA-256: 8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686
Files: 6

foundry-rs/forge-std v1.9.6
Source: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.6
Archive SHA-256: 53d2b498183cb7dc62cf726cc6c1a222ad728b0d87976a877ca1f3ed3707b1c6
Files: 26

OpenZeppelin includes only the ERC-20 import closure and its MIT license. Forge Standard Library includes src/ and both upstream licenses (MIT or Apache-2.0); it is used only by tests.
