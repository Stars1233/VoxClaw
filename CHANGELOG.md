# Changelog

All notable changes to VoxClaw are documented here. Earlier releases are on the
[GitHub releases page](https://github.com/malpern/VoxClaw/releases).

## v1.4.1

### Added
- **Liquid Glass overlay background** — an optional teleprompter background that
  uses the system Liquid Glass material (tinted by your chosen color), so it
  inherits macOS 27's translucency and readability. Toggle it in overlay
  appearance settings; off by default.

## v1.4.0

In-app auto-update via Sparkle.

### Added
- **Automatic updates** — VoxClaw now updates itself with [Sparkle](https://sparkle-project.org).
  New versions are downloaded and installed in place; downloads are notarized and
  EdDSA-signed end to end.
- **"Check for Updates…"** menu item to check on demand.

Note: this is the first Sparkle-enabled build, so install it once manually
(download below). From here on, future updates arrive automatically.

## v1.3.0

The ElevenLabs release — tight word-highlight sync, per-agent voices, and
politer multi-agent behavior.

### Added
- **ElevenLabs voice engine** with the tightest word-highlight sync of any engine,
  driven by ElevenLabs' server-side character timestamps (no more estimated timing).
- **Per-request engine override** — `POST /read` accepts `"engine": "apple" | "openai" | "elevenlabs"`
  to choose the engine per call, independent of the global setting.
- **Distinct voice per agent** — pass `project_id` + `agent_id` and each concurrent
  agent is auto-assigned its own voice from the engine's pool.
- **Hook installer safety** — `setup-claude-code.sh` now runs `bash -n` on each hook
  and refuses to install one with a syntax error, so a broken hook can't overwrite a working one.

### Changed
- **Calmer ElevenLabs delivery by default** — style exaggeration off and balanced
  stability, so it reads naturally instead of like a sports announcer.
- **Current ElevenLabs model** — migrated to `eleven_flash_v2_5` (the previous
  `eleven_turbo_v2_5` is deprecated).
- **Click-anywhere speed slider** — click anywhere on the track to jump to that
  speed; previously only the thumb was draggable.
- **Agent-aware hooks** — the Claude Code and Codex hooks now send the agent session
  id so each agent is tracked independently.

### Fixed
- **ElevenLabs highlight sync** — the timestamp parser now reads the API's current
  `character_*_seconds` schema; it had been silently falling back to estimated timing.
- **Multi-agent interrupts** — prompting one agent no longer cuts off another agent
  that is still speaking. Acks are scoped to `(project, agent)`, so concurrent agents
  queue politely instead of stopping each other.
