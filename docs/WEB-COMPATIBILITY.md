# Web runtime compatibility decisions

## Engine and export

The shipped build uses the official Godot 4.7.2 standard editor and single-threaded `web_nothreads_release.zip` template, Compatibility renderer, WebGL 2 and WebAssembly. The `.wasm` engine is unchanged. The output does not require cross-origin isolation or shared memory.

## Browser frame presentation

Real Playwright WebKit 26 testing on Linux exposed repeated startup errors:

`WebGL: INVALID_OPERATION: glBlitFramebuffer: Read and write color attachments cannot be the same image.`

Tracing the emitted runtime located the operation in Emscripten's `blitOffscreenFramebuffer` / `emscripten_webgl_commit_frame`, not in the GDScript scenery or collision simulation. [Godot's web display setup](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/display_server_web.cpp) requests explicit swap control. The emitted runtime consequently creates an offscreen framebuffer and copies it for presentation.

`tools/finalize_web.py` selects normal browser implicit presentation through two audited, unique context-creation tokens:

```diff
-explicitSwapControl:HEAP8[attributes+25]
+explicitSwapControl:false
-renderViaOffscreenBackBuffer:HEAP8[attributes+32]
+renderViaOffscreenBackBuffer:false
```

The browser compositor then presents the normal WebGL canvas. Disabling explicit swap prevents automatic enabling of the offscreen backbuffer; disabling the backbuffer explicitly also prevents an independent request for that path. The Emscripten commit-frame function returns its normal invalid-target status when no explicit-swap target exists; the engine does not depend on that return value. There is no extra framebuffer copy to fail. This does not intercept console messages or stub a GL call. The `.wasm` remains the official unchanged engine.

The transform fails if either expected token changes and supports re-finalizing an already transformed file. The build manifest records the presentation mode and transformed loader hash. A future engine/template update must re-audit the transform and rerun real browser journeys. Do not mechanically carry version-specific replacements into a different engine.

An earlier experiment selected the existing textured-quad copy fallback instead. Although its console became clean and the internal game state advanced, WebKit's visible canvas stayed frozen. That experiment was rejected and is absent from the delivered loader. Browser tests now compare the same heading-region pixels across menu, gameplay and results to catch that exact state-versus-display failure, in addition to the arithmetic and input assertions.

The isolated implicit-presentation probe completed real six-gate keyboard sessions and replay in both WebKit and Chromium with zero console, page, request or HTTP errors. Playing and results screenshots were also visually inspected. The final engine-specific outcomes against the actual rebuilt export are recorded in [07-QA-REPORT.md](07-QA-REPORT.md), with source/export fingerprints. Linux WebKit testing does not establish physical iOS/Safari behavior.

## High-density screens

The WebGL canvas backing buffer follows device pixel ratio. The game sets its logical content scale size from CSS viewport dimensions, with Godot's `CANVAS_ITEMS` scaling. A 390 CSS-pixel phone therefore uses the same layout at DPR 1 or 2 while retaining a sharp backing buffer. Tests calculate button sizes in CSS pixels and exercise actual touch events.

The browser's `resize` event also updates that logical size through a deferred Godot callback. Listening only to the main Control's `resized` signal was insufficient: a fixed logical viewport could remain unchanged while the backing canvas shrank, producing a letterboxed miniature of the desktop layout. Tests now check exact CSS/logical dimensions and actual button sizes after changing an already running browser viewport, in addition to loading a new phone-sized context.

## Browser save acknowledgement

The first export used normal Godot `FileAccess` persistence. An immediate reload after results could restore the previous active checkpoint: the in-memory filesystem write had succeeded but the asynchronous IndexedDB update had not completed. The original failure is retained in the QA record.

The final browser adapter uses a versioned validated `localStorage` record with a backup of the previous value. It sets and reads back the synchronous browser value before returning success. Access/quota failures produce a visible error and leave JSON result export available. Native saves retain temporary-file validation and replacement. This is local convenience storage, not authenticated cloud storage or protection against the browser clearing data. Concurrent same-player tabs remain unsupported.

## Offline and test boundaries

After successful initial loading, the production shell registers an origin-scoped service worker. Only local game resources are cached. QA URLs do not register that worker so tests cannot silently use an older build. The browser suite separately verifies production offline reload and confirms the absence of QA state/commands on ordinary URLs.

The `?qa=1` state includes correct answers for deterministic test observation. It must never be used for server-authoritative grading. No production learner records or hosted identity are connected in this repository.
