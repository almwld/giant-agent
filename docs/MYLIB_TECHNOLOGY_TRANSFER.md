# Mylib technology inventory and Giant Agent transfer

## Source inspected

- Repository: `almwld/Mylib`
- Main commit: `ede401bf7b30d95ba776889fbe90bd873b195946`
- Tree: `f8718f79aa1327b4c92b523ebf939306fc084243`
- Primary tool registry evidence: `Kimi_Agent_Sources/Zd/B.java`
- Tool block wire contract: `Kimi_Agent_Sources/Dc/I6.java`
- Create-subagent metadata: `Kimi_Agent_Sources/Dc/C0665x7.java`
- Chat-scoped status event: `Kimi_Agent_Sources/Uc/C2011a3.java`
- Status enum mapping: `Kimi_Subagent_Runtime_Contents/Kimi_Subagent_Runtime_Refs/dex_parts/out2/sources/ld/C3867t.java`

The extracted registry contains 60 operation identifiers. The protobuf ToolBlock includes a distinct `toolCallId`, name, arguments, status, task/subagent metadata, MCP/plugin data and typed content. The subagent status event carries `chatId`, `agentId`, status and nullable progress percentage. The observed status vocabulary is `STATUS_UNSPECIFIED`, `STATUS_IDLE`, `STATUS_PENDING`, `STATUS_RUNNING` and `STATUS_TERMINATED`.

## Transfer policy

Mylib contains decompiled Android/Kotlin sources and extracted assets from Kimi and other applications. The transfer is an independent Flutter/Dart implementation of the observed contracts and useful behaviours. Third-party APK binaries, native libraries, proprietary assets, credentials and decompiled implementation code are not copied into Giant Agent. In particular, Compose resources, app-specific `.so` files, `.tflite` models, Rive animations and embedded Python wheels are not interchangeable Flutter dependencies and require separate licensing, ABI and runtime validation.

## Kimi tool inventory (60 identifiers)

| # | Source identifier | Giant Agent mapping |
|---:|---|---|
| 1 | `default` | Internal model/tool routing; not exposed as a user tool. |
| 2 | `lbs_tool` | Not transferred: no location provider or permission-backed location service is configured. |
| 3 | `fetch_urls` | Not yet transferred: a safe bounded HTTP fetch adapter with redirect/SSRF controls is still required. |
| 4 | `generate_slides_outline` | Implemented using the selected shared model; returns structured JSON and is verified. |
| 5 | `visit` | Not yet transferred as browser automation; workspace WebView is a preview, not a remote browser controller. |
| 6 | `click` | Not yet transferred; requires a browser-session DOM/controller contract. |
| 7 | `input` | Not yet transferred; requires a browser-session DOM/controller contract. |
| 8 | `find` | Partial concept only; local workspace/file search is separate from browser DOM search. |
| 9 | `scrollup` | Not yet transferred; requires a browser-session controller. |
| 10 | `scrolldown` | Not yet transferred; requires a browser-session controller. |
| 11 | `python` | Implemented through the embedded Chaquopy runtime. |
| 12 | `todo_read` | Implemented using durable TaskManager records scoped to the current conversation. |
| 13 | `todo_write` | Implemented as a durable pending task; it does not auto-start execution. |
| 14 | `ipython` | Not claimed: the existing Python facade does not prove a persistent IPython kernel/session. |
| 15 | `shell` | Implemented through Gain PTY with explicit command approval. |
| 16 | `read_file` | Implemented through the constrained native workspace bridge. |
| 17 | `edit_file` | Mapped to verified `write_file`; only existing allowed text/code files can be changed. |
| 18 | `write_file` | Implemented through the constrained native workspace bridge. |
| 19 | `browser_click` | Not yet transferred; browser controller is absent. |
| 20 | `browser_find` | Not yet transferred; browser controller is absent. |
| 21 | `browser_input` | Not yet transferred; browser controller is absent. |
| 22 | `browser_visit` | Not yet transferred; browser controller is absent. |
| 23 | `browser_state` | Not yet transferred; browser controller is absent. |
| 24 | `browser_scroll_up` | Not yet transferred; browser controller is absent. |
| 25 | `browser_scroll_down` | Not yet transferred; browser controller is absent. |
| 26 | `browser_screenshot` | Not yet transferred; no capture-capable agent browser session exists. |
| 27 | `screenshot_web_full_page` | Not yet transferred; requires browser capture and stitching support. |
| 28 | `find_asset_bbox` | Not yet transferred; requires a connected vision/asset-localization provider. |
| 29 | `crop_and_replicate_assets_in_image` | Not yet transferred; requires a real image-editing provider. |
| 30 | `web_search` | Implemented through WebSearchService (DuckDuckGo HTML results). |
| 31 | `image_search` | Not yet transferred as image search; ordinary web search is not represented as image search. |
| 32 | `search_image_by_text` | Not yet transferred; requires an image-search provider. |
| 33 | `search_image_by_image` | Not yet transferred; requires reverse-image-search provider support. |
| 34 | `generate_image` | Not yet transferred; media registry is an adapter boundary and has no image provider registered by default. |
| 35 | `generate_speech` | Implemented as on-device TTS playback; it does not claim to create a downloadable audio file. |
| 36 | `generate_sound_effects` | Not yet transferred; no sound-effects generation engine/provider is connected. |
| 37 | `get_available_voices` | Implemented using voices exposed by the device TTS engine. |
| 38 | `get_data_source` | Implemented as a safe list of configured MCP servers (credentials excluded). |
| 39 | `get_data_source_desc` | Implemented by initializing a selected MCP server and reading its tools/resources. |
| 40 | `deploy_website` | Not transferred: current GitHub connector is read-only; deployment requires an explicitly authorized provider. |
| 41 | `website_version_manager` | Not transferred: no write-capable deployment/version provider is connected. |
| 42 | `website_version_manager_rollback` | Not transferred: rollback must be backed by a real deployment history and explicit authorization. |
| 43 | `gen_purchase_url` | Not transferred: no commerce/payment provider or verified purchase URL contract exists. |
| 44 | `memory_space_insert` | Implemented in local SQLite with an audit entry. |
| 45 | `memory_space_update` | Implemented in local SQLite with previous/new values recorded. |
| 46 | `memory_space_delete` | Implemented in local SQLite with a deletion audit entry. |
| 47 | `memory_space_edits` | Implemented as readback of current facts and the local edit journal. |
| 48 | `slides_generator` | Implemented as a self-contained HTML slide deck in the workspace, not a PPTX export. |
| 49 | `slides_generator_bnn` | Not transferred: specialized contract/format was not established from the available evidence. |
| 50 | `task` | Mapped to the existing durable TaskManager/AgentService lifecycle; no second task runtime is created. |
| 51 | `create_subagent` | Implemented with request-scoped child identity and durable lifecycle events. |
| 52 | `spawn_subagent` | Implemented inline through the existing shared ModelService/LlamaService runtime; child recursion is blocked. |
| 53 | `delete_subagent` | Implemented as a soft dismissal; running children cannot be erased. |
| 54 | `check_subagent_status` | Implemented with status/result readback. |
| 55 | `send_message` | Implemented with a request-scoped mailbox. |
| 56 | `wait_for_message` | Implemented with bounded 1–30 second mailbox wait. |
| 57 | `ask_user` | Implemented through an explicit chat-screen dialog; cancellation is an explicit result. |
| 58 | `update_goal` | Implemented as request-scoped goal state plus a timeline event. |
| 59 | `show_widget` | Not yet transferred: no typed widget renderer/interaction contract has been validated. |
| 60 | `dmail` | Not mapped to email or messaging: the exact DMail semantics are not established by the inspected registry alone. |

## Giant Agent foundations reused (no duplicate runtime)

- One shared `LlamaService.instance` / `ModelService`; local child execution is serialized. Cloud OpenRouter execution remains on the existing streaming provider.
- MCP Streamable HTTP client with structured content/resource results and explicit approval for non-read-only remote tools.
- Per-invocation `tool_call_id` and cancellation registry.
- Durable SQLite task/request/event/subagent journal and restart recovery.
- Existing Gain PTY bridge, explicit terminal approval, Python runtime and workspace path constraints.
- Existing local memory, TTS, OCR, WebView workspace preview and output collection.

## Dynamic subagent contract implemented in this transfer

- Child IDs are request-scoped in storage (`<request>_dynamic_<local-id>`) while the model-facing local ID remains short.
- Events carry both `chat_id`/`session_id` and stable `agent_id`/`task_id`, internal status, Kimi-compatible `wire_status` and nullable `progress_percent`.
- Dependencies must refer to existing children and must be completed before spawn.
- Maximum six dynamic children per request; no child may create another child.
- Local model child work runs inline through the existing runtime. This intentionally avoids concurrent access to one mutable JNI model context.
- Delete is soft dismissal; a running child cannot be silently erased.
- Message waits are bounded; no unbounded background waiter is created.
- Ask-user cancellation and missing UI are explicit; no answer is fabricated.

## Validation boundary

The code and tests in this branch are implementation work, not proof of a successful Android build. GitHub Actions must pass parser tests, unit tests, `flutter analyze`, all APK ABI builds, Gain PTY JNI checks and artifact uploads before the transfer can be called build-verified. Device testing is still required for TTS playback, browser/media providers, terminal approval and local GGUF execution.
