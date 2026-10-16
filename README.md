# Cleancut

A tiny macOS app for YouTube voiceovers recorded on a laptop mic. Drop an audio or video file and Cleancut:

1. **Cleans the voice** with [Desert Ant Clear](https://desertant.com/docs/clear/) (Studio voice, mastered to YouTube's −14 LUFS).
2. **Transcribes** the clean audio with [Desert Ant Voz](https://desertant.com/docs/voz/), with timestamps.
3. **Copy for AI** puts the transcript and a chapters prompt on your clipboard. Paste it into any AI and you get YouTube chapters back.

Everything runs on-device. Nothing is uploaded.

## Output

Files are written next to the file you dropped:

| File | What |
|---|---|
| `Name.clean.wav` | Cleaned audio, 48 kHz mono. Drop it into your editor. |
| `Name.transcript.txt` | `[1:23] One line per sentence`, for the AI. |
| `Name.transcript.srt` | Captions you can upload to YouTube. |

The window has an Original/Clean A/B player (press Space to play or pause) that keeps your position when you switch.

## Requirements

- macOS 15 or later (Apple silicon recommended)
- Xcode 26 or later to build
- About 480 MB of models, downloaded from Hugging Face on first run and cached afterwards

## Build

```bash
open Cleancut.xcodeproj
```

Then press Run. The project is generated from `project.yml`. After changing it, run `xcodegen generate` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)).

Tests: `xcodebuild test -scheme Cleancut -destination 'platform=macOS'`

## Privacy

Audio and transcripts never leave your Mac. The Desert Ant SDK's usage reporting is switched off (`DesertAnt.usageDisabled = true` in `CleancutApp.swift`). The only network traffic is the one-time model download.

## License

Cleancut is MIT. The Desert Ant SDK and models are under the [Desert Ant Labs Source-Available License](https://github.com/Desert-Ant-Labs/desert-ant-core), free up to 100k monthly active devices.
