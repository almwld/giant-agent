# MCP, tool-call identity and OpenRouter streaming contracts

This change introduces independent, testable transport contracts without creating
another model runtime or another Dart isolate.

## MCP result envelope
`McpToolResult` preserves ordered content blocks, text, image/audio/resource
payload fields, unknown extension fields, `isError`, `structuredContent`, and
metadata. `McpResourceLink` validates absolute resource URIs and retains MIME,
title, description and size. JSON persistence is lossless for fields represented
by the envelope. A text preview is explicitly a display projection, never the
canonical stored result.

## Tool call identity
`ToolCallRegistry` tracks each invocation by an independent `tool_call_id`,
separate from request and step identifiers. Cancellation is per invocation and
the lifecycle owner must call `finish` in a finally block. This is cooperative:
a native/platform operation already executing cannot be forcibly killed unless
its transport itself exposes cancellation. Callers must check cancellation at
safe boundaries and report interrupted rather than completed.

## SSE
`ServerSentEventParser` incrementally parses SSE framing, multi-line data,
comments, event names, IDs and retry hints. It does not create an inference
runtime. The OpenRouter adapter remains the sole remote provider and the
existing singleton ModelService/LlamaService remains the sole local runtime.

## Integration boundary
The current OpenRouter provider still has its existing non-streaming call path;
this commit adds transport primitives only. Do not mark end-to-end OpenRouter
streaming as complete until the provider's request path emits `stream: true`,
consumes this parser, forwards token deltas to the existing UI event bus,
and handles cancellation/terminal states with tests. Likewise, the typed MCP
envelope must be connected to a real MCP transport/registry before claiming
remote MCP server interoperability.
