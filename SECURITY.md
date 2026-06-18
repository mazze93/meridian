# Security Policy for Meridian

Meridian is a privacy-first, local-first calendar application. Because we operate without a cloud backend, our security model strictly focuses on local device integrity, CRDT synchronization safety, and peer-to-peer network boundaries over Tailscale.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Main / HEAD | :white_check_mark: |
| < 1.0.0 | :x:                |

## Threat Model & Scope

**In Scope for Reports:**
*   **CRDT Poisoning:** Vulnerabilities allowing a malicious peer to crash the application or corrupt the local Automerge document via crafted synchronization payloads.
*   **Sync Bypass:** Exploits that bypass Tailscale authentication or expose the local sync port to non-Tailnet IP addresses.
*   **Data Leakage:** Improper handling of local data that breaks Apple's App Sandbox boundaries.

**Out of Scope:**
*   Compromise of the underlying Tailscale network (report directly to Tailscale).
*   Physical device compromise or malware already present on the user's macOS/iOS device.
*   Denial of Service (DoS) attacks requiring massive local resource exhaustion.

## Reporting a Vulnerability

We take security seriously and enforce a strict non-disclosure policy prior to patching. Please **do not** open a public GitHub issue for any security vulnerability.

1. Email your findings to `security@mazzeleczzare.com`.
2. Encrypt your report using our public PGP key.
3. Provide a Proof of Concept (PoC) and step-by-step instructions to reproduce the issue.

You will receive an acknowledgment within 48 hours, followed by a timeline for a patch and coordinated disclosure.
