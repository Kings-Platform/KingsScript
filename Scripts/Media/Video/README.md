# Video edit

`kings video-edit` turns raw phone or smart-glasses clips into one vertical video for Stories or
Reels: clips joined in recording order, sped up, and captions transcribed on the machine and
burned in. Nothing is cut — boring stretches can be fast-forwarded instead, and a long result can
be split into parts that fit a platform's length limit.

#### Index

- [Usage](#usage)
- [Options](#options)
- [Fixing captions](#fixing-captions)
- [Output format](#output-format)

## Usage

```bash
# Files, folders or Samsung Quick Share links, in any order — clips are sorted by recording time
kings video-edit ~/Downloads/clip1.mp4 ~/Downloads/clip2.mp4 --name Trip
kings video-edit https://quickshare.samsungcloud.com/AbC123 --name Trip --preview

# Fast-forward a walk in clip 1 and split into parts of up to a minute (Stories)
kings video-edit chalet.mp4 --name Chalet --fast 1:0:12-0:40x6 --max-length 60
```

To turn one download into several videos, list it once and pass the files from its `.work/raw/`
to separate projects — their transcripts are reused, not redone.

The project lands in `~/Desktop/<name>/` (`KINGS_VIDEO_DIR` in `config.env` changes the base):
`<name>.mp4`, `<name>-preview.mp4` with `--preview`, and a `.work/` folder with the downloads,
transcripts and caption images. The caption blocks are printed with their times, for review.

The first run creates a virtualenv in `~/.kingsScripts/venvs/video` and downloads the Whisper model
(`mlx-community/whisper-large-v3-turbo`, about 1.6 GB).

## Options

| Option | Meaning |
|---|---|
| `--name NAME` | Project folder and file name (required) |
| `--speed X` | Playback speed, default `1.25` — audio pitch is kept |
| `--lang CODE` | Spoken language for Whisper, default `pt` |
| `--no-captions` | Join and speed up only |
| `--mute` | No audio and no captions — for footage that gets music when posted (combine with `--speed 1` to keep the real pace) |
| `--fast CLIP:START-END[xF]` | Fast-forwards that stretch of clip number `CLIP` (from 1, as `--list` numbers them) at `F`x, default 4; silent and without captions. Times in source seconds or `m:ss`. Repeatable |
| `--max-length S` | Splits the result into `<name>-partN.mp4` (replacing `<name>.mp4`) of similar length, none over `S` seconds, each cut in a pause before a caption block |
| `--list` | Only prints the clips in order, with recording date and length |
| `--transcribe-only` | Stop after writing the transcripts, to fix them before the first render |
| `--preview` | Also write a 720p copy under 30 MB |
| `--out DIR` | Base folder instead of `KINGS_VIDEO_DIR` |

## Fixing captions

Each clip gets `.work/<clip>.words.json`, one word per line with its time:

```json
[
  {"start": 0.0, "end": 0.42, "text": "Esse"},
  {"start": 0.42, "end": 0.61, "text": "daqui"},
```

Fix a misheard word in `text`, or delete the lines of a sentence Whisper invented at the end of a
clip (a common hallucination over silence). Then run with just the name — the clip list and the
transcripts are reused, only the render runs again:

```bash
kings video-edit --name Trip
```

Deleting a `.words.json` transcribes that clip again.

## Output format

| | |
|---|---|
| Frame | 1080×1920, center crop of the source, 30 fps |
| Video | H.264 high, CRF 20 |
| Audio | AAC 160 kbps, loudness normalized to −15 LUFS |
| Fast-forward | Same picture pipeline, audio silenced, no captions |
| Captions | Up to two lines per block, white bold with black outline, lower third; a block ends at a pause over 0.8 s or a sentence end, and stays up across pauses under 0.6 s |

Captions are full-frame PNGs overlaid through ffmpeg's concat demuxer, so `ffmpeg` builds without
`libass` or `drawtext` (Homebrew's default) work.
