# Security Policy

`mac-lifeline` opens a remote-access path into other people's computers. Security reports are taken
seriously and welcomed.

## Reporting a vulnerability

**Please do not open a public issue for security problems.** Instead, use GitHub's private
[**Report a vulnerability**](https://github.com/curtismercier/mac-lifeline/security/advisories/new)
flow (Security → Advisories), or email the maintainer privately.

Include, as best you can:

- What the issue is and which component (tunnel container, `mac-setup.sh`, a cleanup tool).
- How to reproduce it.
- The impact you see (e.g. "a leaked tunnel key could reach X").

You'll get an acknowledgement; fixes for confirmed issues are prioritized.

## Scope &amp; design assumptions

The threat model is documented in the README's [Security model](README.md#security-model). In short:

- A **leaked Mac tunnel key** is assumed possible and is designed to be inert against your VPS
  (tunnel-only user, no shell, single permitted listen address, no local forwarding).
- The container is unprivileged, host-network-free, and mount-free by design.
- **Known trade-off:** the Mac→VPS hop currently uses trust-on-first-use host-key handling
  (`StrictHostKeyChecking=no`) so it connects unattended. Host-key pinning is on the roadmap. Reports that
  sharpen this are welcome.

## What is *not* a vulnerability

- The weak example values in config blocks (`YOUR_VPS_IP_OR_HOST`, sample ports) — replace them.
- Antivirus flagging the reverse tunnel as suspicious — that's a heuristic false positive; see the README.
</content>
