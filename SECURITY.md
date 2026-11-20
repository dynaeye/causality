**English** · [简体中文](SECURITY.zh-Hans.md)

# Security

## Reporting a problem

If you find a security problem, mail the maintainer instead of opening a public issue — the address is in the commit history. Say what you did to trigger it, which version it affects, and how you think it could be exploited. Once the fix ships, you can be credited by name in that release.

## Keys

- AI API keys are read from three places, in this order: environment variables → the Release keychain → `~/Library/Application Support/Causality/credentials.plist` in Debug builds (directory 0700, file 0600). None of them end up in a project package or in the repository.
- A `.causal` package holds story data and image paths relative to the package. No credentials.
- Before you open an issue or a pull request, check your logs and screenshots for keys, tokens, and personal paths.

## Supported versions

The current version is 1.0.1. The signed release is the supported build; the Debug build of the latest commit is work in progress and can change without notice.
