# Third-party notices

## Aura Autopilot — Godot addon

The complete Godot addon in `addons/autopilot/` is from
[ramenvr/autopilot](https://github.com/ramenvr/autopilot), commit
`1818cc337b20762cd50102bc774a8e45eb7c4dc7`, source directory
`plugin/godot/addons/autopilot/`.

Copyright belongs to the upstream authors. The addon is distributed under the
Apache License, Version 2.0; its complete license is included at
`addons/autopilot/LICENSE`. The upstream GDScript, metadata, icons, and font files
are unmodified. `addons/autopilot/UPSTREAM.json` records original file hashes and
the exact source revision. Godot may create additional import metadata locally.

The addon's bundled IBM Plex Sans, IBM Plex Mono, and JetBrains Mono fonts use the
SIL Open Font License 1.1. Their full licenses are retained in
`addons/autopilot/fonts/OFL-IBMPlexSans.txt`, `OFL-IBMPlexMono.txt`, and
`OFL-JetBrainsMono.txt`. They are used by the optional upstream editor dock.

The DDGodot-specific `tools/autopilot_bootstrap.gd` and
`tools/autopilot_local.py` are separate integration code. The latter is a
deterministic local test driver, not the upstream Jev or Aura inference runtime.
See `docs/AUTOPILOT-AUDIT.md` for the distinction.

## Python websockets

The optional native instrumentation test driver uses
[websockets](https://github.com/python-websockets/websockets), pinned to 16.0
in `tools/autopilot-requirements.txt`, under the BSD 3-Clause License. The package
is installed by the developer and is not bundled in the exported game.

## Godot Engine

Godot Engine and its official web export template are used under the MIT License.
Godot's third-party notices are available in the editor's About dialog and at
[godotengine.org/license](https://godotengine.org/license/). Build and runtime
version for this project: 4.7.2 stable.

## DejaVu Sans — game interface font

`assets/fonts/DejaVuSans.ttf` is the DejaVu Sans font supplied by Ubuntu's
`fonts-dejavu-core` package. It is bundled locally so mathematics symbols and
navigation arrows do not depend on a browser's installed fonts or a hosted font
service. DejaVu changes are public domain; the inherited Bitstream Vera font
license and copyright notices apply as reproduced in full at
`assets/fonts/LICENSE-DejaVu.txt`. The font is distributed without modification
and its original name is retained.
