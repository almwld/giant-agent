# Boosthis Gain Agents connection

This repository's Boosthis integration currently has two distinct layers:

1. **Developer-side MCP connection** — configured by the root `.mcp.json` file in this repository.
2. **In-app Flutter/Android instrumentation** — not implemented yet. The original one-time Boosthis setup instructions available to the project did not include the Flutter/Android SDK package URL, initialization snippet, or event API. Do not guess a vendor SDK, package name, or event schema.

## Project endpoint

- Project: `Gain agents`
- Project identifier: `24a987fb`
- MCP endpoint: `https://www.boosthis.com/mcp/gain-agents-24a987fb`
- Required environment variable: `BOOSTHIS_PROJECT_KEY`

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
