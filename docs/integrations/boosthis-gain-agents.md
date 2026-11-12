# Boosthis Gain Agents connection

This repository's Boosthis integration currently has two distinct layers:

1. **Developer-side MCP connection** — configured by the root `.mcp.json` file in this repository.
2. **In-app Flutter/Android instrumentation** — not implemented yet. The original one-time Boosthis setup instructions available to the project did not include the Flutter/Android SDK package URL, initialization snippet, or event API. Do not guess a vendor SDK, package name, or event schema.

## Project endpoint

- Project: `Gain agents`
- Project identifier: `24a987fb`
- MCP endpoint: `https://www.boosthis.com/mcp/gain-agents-24a987fb`
- Required environment variable: `BOOSTHIS_PROJECT_KEY`

## Configure the MCP client

For Codex CLI, register the project endpoint with the exact server name used in `.mcp.json`:

```sh
codex mcp add boosthis-gain-agents-24a987fb --url https://www.boosthis.com/mcp/gain-agents-24a987fb
```

If the server offers an OAuth login flow, start it with:

```sh
codex mcp login boosthis-gain-agents-24a987fb
```

The repository `.mcp.json` entry is the equivalent project-level configuration. Do not pass the project key as a command-line argument; keep credential material out of shell history and process listings.

## Configure the key locally

Set the project key in the environment of the MCP-capable developer tool. Never put the key in `.mcp.json`, source files, CI logs, or commits.

macOS/Linux (current shell):

```sh
export BOOSTHIS_PROJECT_KEY='YOUR_ROTATED_PROJECT_KEY'
```

PowerShell (current session):

```powershell
$env:BOOSTHIS_PROJECT_KEY = 'YOUR_ROTATED_PROJECT_KEY'
```

Restart the MCP-capable tool after setting the variable. The key that was previously pasted into chat must be rotated in Boosthis before use.

## Verification checklist

1. Confirm the MCP client expands `${BOOSTHIS_PROJECT_KEY}` from its process environment.
2. Confirm the server responds to MCP initialization and tool discovery.
3. Record the discovered tool names and input schemas without exposing credentials.
4. Invoke only a read-only project/status tool first, if one is provided.
5. Save a sanitized connection report (endpoint, server identity, tool names, result status); never save request headers or key material.

## What is still required for app instrumentation

Obtain the original Boosthis one-time setup page or official Flutter/Android integration instructions, including:

- exact Flutter package or Android artifact and version;
- official installation command / Gradle coordinates;
- initialization code and required configuration fields;
- event names, parameter schemas, and lifecycle hooks;
- privacy/consent and data-retention requirements.

Only after those are available should a separate app-side implementation add the SDK, typed event adapter, lifecycle instrumentation, tests, and Android release verification. This document deliberately marks that boundary rather than inventing a non-existent API.


## Vendor-published Flutter kit facts (reviewed 2026-11-12)

The public Boosthis documentation confirms that a Flutter kit exists, but deliberately does not publish the private per-project install command or archive URL. Those are generated on the project's own Project Keys → key → Setup page. The public Help page says the archive is downloaded from that page (or its one-line command), unpacked, and wired using the snippet generated for that key. Do not substitute a guessed pub.dev package or invent a package name.

Before approving app instrumentation, account for these documented behaviours:

- The Flutter kit's key is embedded in the shipped application. Boosthis says this key is scoped so it can register installs and submit fabricated readings, but cannot read project measurements or access billing, teams, or other projects. It is not a server secret.
- Initialisation registers the install automatically; the public docs state there is no end-user consent prompt before that first registration.
- The Flutter kit observes requests made through Dart's default HTTP client (including package:http and Dio's default adapter). It adds three trace headers to every watched outbound host unless `BOOSTHIS_DISABLED=1` is set at build time. This is a cross-host propagation concern and must be reviewed against the app's third-party API traffic.
- Detailed request spans depend on the project's Full telemetry setting. The optional Dio add-on is separate and must not be added without an explicit need.
- The kit's `forget()` path stops reporting and erases its install state. A release archive includes `BOOSTHIS_CHECKSUMS.txt`; verify it with `sha256sum -c BOOSTHIS_CHECKSUMS.txt`. Boosthis also documents signed release verification and publishes its release signing key.

References:
- https://www.boosthis.com/help
- https://www.boosthis.com/docs/connect-your-ai
- https://www.boosthis.com/docs/before-you-install
- https://www.boosthis.com/docs/what-boosthis-collects

## Integration gate

The implementation can proceed as soon as the generated Setup-page install command/archive and snippet are available. That exact material is project-specific and sits behind the account's Setup page; public documentation does not expose it. Until then the safe completed scope is the MCP connection configuration and the two unrelated Dart compile fixes. Do not ship a speculative SDK integration or silently enable outbound trace headers to third-party hosts.
