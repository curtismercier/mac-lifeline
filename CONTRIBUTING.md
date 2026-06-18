# Contributing to mac-lifeline

Thanks for helping. This project stays useful because people who fix real Macs in the field send back
what they learn. Two kinds of contribution are especially valuable:

## 1. Adware signatures

The highest-leverage PR. If you find a new adware/junk family on a Mac, add its name pattern to the
`PAT='...'` list near the top of [`tools/clean-adware.command`](tools/clean-adware.command).

- Match on the **file/bundle name**, case-insensitive, as a `grep -E` alternation (`|`-separated).
- Keep patterns specific enough not to match legitimate software. When in doubt, scope tightly.
- In the PR description, say where you saw it (path) and what it was — that's the provenance others trust.

## 2. macOS version reports

The [Supported macOS](README.md#supported-macos) table marks older versions "likely / untested." If you
confirm the tunnel or the cleanup tools working (or failing) on a version not yet verified, open an issue
titled `macOS <version>: works / fails` with what you observed. We'll update the table.

## 3. Code

- **Shell:** target `bash` that runs on macOS 10.13's stock tools. No GNU coreutils assumptions
  (no `timeout`, no `readlink -f`). Run [`shellcheck`](https://www.shellcheck.net/) on anything you change.
- **Container:** keep it minimal and hardened — no new capabilities, no host mounts, no shell for the
  tunnel user. Any change to the security posture must keep the negative tests passing (see the
  [Security model](README.md#security-model)).
- **Keep it transparent.** The owner-facing tools print every action they take. Don't add anything that
  deletes or changes files silently.

## Pull requests

- One focused change per PR. Describe what and why.
- Don't include secrets, real IPs, hostnames, or client names — this repo is deliberately scrubbed of them.
- By contributing, you agree your work is released under the project's [MIT license](LICENSE).
</content>
