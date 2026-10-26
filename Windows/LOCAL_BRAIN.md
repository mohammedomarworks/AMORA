# AMORA Local Brain on Windows

Windows uses genuine on-device `llama.cpp` inference. Local Brain never silently switches to a cloud provider. Setup is explicit and needs internet access; subsequent inference uses the installed model and a private loopback connection on this PC. No Python, developer tools, external model server, or API key is required by this integration.

## Source of truth and implementation choice

The audit covered Mac `Sources/AMORA/LocalBrain/AmoraLocalBrainProvider.swift`, `AmoraLlamaCppRuntime.swift`, `AmoraModelManager.swift`, the model catalog and gateway, `Package.swift`, and the local-brain/prewarm/local-agent tests. Mac uses an in-process native runtime and Metal acceleration. Windows uses a managed, hidden CPU runtime process with a Windows job object. The process boundary isolates native inference faults from WinUI and permits decisive cancellation and memory release without a third-party .NET binding.

The Windows artifact is the official **llama.cpp b11901 CPU x64 ZIP**, 24,228,082 bytes, SHA-256 `039951745399d7c1228b1e882d6e41b24d393f1795e3a6e176162bfb8193500a`. Its [release](https://github.com/ggml-org/llama.cpp/releases/tag/b11901), [server options](https://github.com/ggml-org/llama.cpp/blob/b11901/tools/server/README.md), and [MIT license](https://github.com/ggml-org/llama.cpp/blob/b11901/LICENSE) establish the dependency and attribution. Updating this pin requires reviewing changed flags and rerunning actual inference and cancellation acceptance. Windows ARM64, x86, GPU acceleration, and broad CPU compatibility are not verified or advertised by this implementation.

| Model | Download size | SHA-256 | Reason |
| --- | ---: | --- | --- |
| Qwen2.5-1.5B-Instruct Q4_K_M | 1,117,320,736 bytes | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` | Actual Mac default |
| Qwen2.5-0.5B-Instruct Q4_K_M | 491,400,032 bytes | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` | Actual Mac compact option; bounded Windows verification fixture |

Both models come from the official [Qwen 1.5B GGUF](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) and [Qwen 0.5B GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) repositories and use Apache 2.0. Full MIT/Apache license notices are embedded in the app and copied alongside installed assets; the upstream ZIP's OpenMP license is retained. Models and runtime are downloaded directly from those sources, not bundled into the AMORA ZIP.

## User-controlled setup

1. Open Local Brain and choose a model. Its size and license are displayed before installation.
2. Install downloads the pinned runtime and selected model to `%LOCALAPPDATA%/AMORA/LocalBrain`. Partial downloads remain temporary and are removed on cancellation/failure. SHA-256 and exact sizes must match before publication.
3. Use this model explicitly selects Local Brain for conversation without changing stored cloud credentials. Selecting a model in the picker alone does not change the active provider.
4. Start verifies the runtime ZIP, each extracted native file, and the model, checks available physical memory, and loads the model. Chat also starts an already installed model when needed; it never installs implicitly.
5. Cancel stops the current operation. During native inference it terminates the owned runtime. Stop releases loaded memory and retains installed assets. Delete removes only the selected catalog model and stops it first if loaded; it does not remove conversation or persistent memory data.

Setup reports storage/network/integrity/memory errors honestly. A failed setup does not become a successful ready state. The selected model is persistent; chat history remains ephemeral. Setup is not performed at application startup.

## Privacy, lifecycle, and limits

- The runtime binds only `127.0.0.1` on an ephemeral port. Each launch uses a new random authentication key in the process environment, never the command line or logs. HTTP redirects and proxies are disabled for inference.
- All ambient `LLAMA*` configuration is cleared. Native agent tools, web UI, MCP proxy, slots endpoint, network model downloads, runtime logging, and on-disk prompt caching are disabled. AMORA never supplies runtime shell tools or arbitrary model paths from model output.
- A kill-on-close Windows job owns the child process. Normal stop, app disposal, cancelled generation, and native failure cleanup release it. HTTP cancellation alone is not treated as proof that native inference stopped.
- Requests are serialized. Context uses the most recent eight turns with a bounded character budget; the native tokenizer enforces the 2,048-token window with output reservation. Generation uses at most 256 output tokens, temperature 0.3, top-p 0.85, and a 90-second deadline, matching the principal Mac generation limits. ChatML delimiters in user/history text are escaped. Hidden thinking blocks are removed from visible text.
- Local approved-memory conversation turns can remain in local history. The cloud router continues filtering memory-derived turns. Automatic retrieval/injection of the entire memory store is not implemented.
- This milestone implements local conversation, setup/readiness, cancellation, and lifecycle. The Mac multi-step Local Agent planning/tool loop, prewarming, GPU acceleration, and full local-agent parity remain separate gaps. Deterministic Windows commands continue through the existing bounded engine; model text cannot enable native tools.
- A small model may answer incorrectly. Its successful output proves real inference, not broad model quality or full parity.

## Verification

`LocalBrainTests` uses injected assets/runtime and a cloud-denying HTTP handler to exercise checksum rejection, unsafe archive rejection, context boundaries, no implicit setup/cloud fallback, memory checks, cancellation/restart, deletion ordering, and late UI callbacks. These tests do not download models.

`NativeLocalBrainIntegrationTests` is deliberately skipped unless `AMORA_LOCAL_BRAIN_TEST_ROOT` names a prepared fixture directory containing `runtime.zip`, `runtime-b11901/`, and the compact model file. The test uses the production asset verifier, runtime, and service; it loads the real model, asks a synthetic arithmetic question, checks readiness, and stops the child. Run it explicitly on Windows x64:

```powershell
$env:AMORA_LOCAL_BRAIN_TEST_ROOT = 'C:\absolute\path\to\verified-fixture'
dotnet test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release -p:Platform=x64 --filter Category=NativeLocalBrain
Remove-Item Env:AMORA_LOCAL_BRAIN_TEST_ROOT
```

Initial runtime-only acceptance downloaded the 24 MB official runtime and 491 MB compact model, verified both checksums, and obtained `5` from `What is 2 + 3? Answer with the number only.` through the hidden offline loopback runtime. Evidence: `outputs/evidence/localbrain-initial-runtime.json` in the collaboration workspace. This is distinct from production-service and visible-app acceptance; consult the current milestone report for subsequently completed build/test/UI evidence. No cloud requests or real personal conversation were used in that initial fixture.

The subsequent production-service run passed **1/1 native integration test** with no skips (`outputs/evidence/test-results/parity2-native-localbrain.trx`, 3.248 seconds). It verified the official installed artifacts, loaded the actual compact model through `LocalBrainService`/`LlamaServerRuntime`, returned exactly `5`, cancelled another generation after 100 ms, confirmed the child stopped, and confirmed the stopped state. No `llama-server` process remained after the test. The focused non-native suite passed **21/21** (`parity2-localbrain-unit.trx`). Both commands used `-c Release -p:Platform=x64 --no-build`; native verification additionally set the fixture environment variable and `--filter Category=NativeLocalBrain`. Visible app acceptance and the final full regression count remain separately recorded in the current milestone report.

The later integrated acceptance (`outputs/evidence/test-results/parity2-ui.trx`) passed **635/635**, including the expanded **23 Local Brain unit cases** and **one native test** (3.350 seconds). Native acceptance now additionally runs cached Install with a handler that rejects every download, limits reported free storage to 4 MB, and verifies the embedded MIT/Apache notices were written. This found and fixed a real defect: setup previously reserved space for a second full model download even when the artifact was already verified. Only missing artifacts and necessary extraction are now reserved. Unexpected native process exit also invalidates Ready immediately, covered by regression. These observations supersede the earlier narrower service run; visible app acceptance remains a separate claim.
