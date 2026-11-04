"""Joins clips in recording order, speeds them up and burns two-line block captions.

Called by video-edit.sh inside its virtualenv. Every step caches its result in the project's
.work folder, so running again only redoes what changed: fix a word in <clip>.words.json and run
the same command to render again without transcribing.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1080, 1920, 30
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".mkv"}
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
WHISPER_MODEL = "mlx-community/whisper-large-v3-turbo"

FONT_PATH = os.environ.get("KINGS_VIDEO_FONT", "/System/Library/Fonts/Avenir Next.ttc")
FONT_INDEX = int(os.environ.get("KINGS_VIDEO_FONT_INDEX", "0"))  # 0 = Avenir Next Bold
FONT_SIZE = 60
LINE_H = 76
MAX_W = W - 160
CAP_CENTER_Y = 1380

# A new block starts after a pause this long, and a block stays on screen until the next one
# when the silence between them is shorter than HOLD_GAP, so captions don't blink.
BREAK_GAP = 0.8
HOLD_GAP = 0.6
PREVIEW_LIMIT = 30 * 1024 * 1024


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def run(cmd):
    subprocess.run(cmd, check=True)


def probe(path, entries):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", entries, "-of", "json", str(path)],
                         capture_output=True, text=True).stdout
    return json.loads(out or "{}")


def is_video(path):
    info = probe(path, "stream=codec_type:format=duration")
    has_video = any(s.get("codec_type") == "video" for s in info.get("streams", []))
    return has_video and float(info.get("format", {}).get("duration", 0) or 0) > 0


def duration(path):
    return float(probe(path, "format=duration")["format"]["duration"])


def recorded_at(path):
    tags = probe(path, "format_tags=creation_time").get("format", {}).get("tags", {})
    return tags.get("creation_time", "")


# curl, not urllib: python.org builds ship without CA certificates.
# Quick Share pages embed one signed URL per shared file; images in the share are thumbnails.
def download_quickshare(url, raw):
    page = subprocess.run(["curl", "-sL", "-A", UA, url], capture_output=True, text=True).stdout
    links = sorted(set(re.findall(r'links/[A-Za-z0-9]+/contents/[0-9a-f]{32}\?signature=[^"& ]+&storageType=file', page)))
    if not links:
        sys.exit(f"No files found at {url} (expired link?)")
    files = []
    for link in links:
        dest = raw / (re.search(r"contents/([0-9a-f]{32})", link).group(1) + ".mp4")
        if not dest.exists():
            log(f"Downloading {dest.name}")
            run(["curl", "-sSL", "-A", UA, "-o", str(dest), "https://quickshare.samsungcloud.com/ls/public/v1/" + link])
        if is_video(dest):
            files.append(dest)
        else:
            dest.unlink()
    return files


def collect_inputs(inputs, raw):
    files = []
    for item in inputs:
        if item.startswith("http"):
            files += download_quickshare(item, raw)
        elif Path(item).is_dir():
            files += [p for p in Path(item).iterdir() if p.suffix.lower() in VIDEO_EXT]
        else:
            files.append(Path(item))
    files = [Path(f).resolve() for f in files]
    return sorted(files, key=lambda p: (recorded_at(p), p.name))


def transcribe(clip, work, lang):
    """Writes <clip>.words.json once; later edits to it (fixed words, removed lines) are kept."""
    words_file = work / f"{clip.stem}.words.json"
    if words_file.exists():
        return words_file
    import mlx_whisper

    log(f"Transcribing {clip.name}")
    result = mlx_whisper.transcribe(str(clip), path_or_hf_repo=WHISPER_MODEL, language=lang,
                                    word_timestamps=True)
    words = [{"start": round(w["start"], 2), "end": round(w["end"], 2), "text": w["word"].strip()}
             for s in result["segments"] for w in s.get("words", []) if w["word"].strip()]
    # One word per line, so fixing a word or deleting a hallucinated tail is a one-line edit.
    lines = ",\n".join("  " + json.dumps(w, ensure_ascii=False) for w in words)
    words_file.write_text(f"[\n{lines}\n]\n")
    return words_file


def line_count(words, draw, font):
    lines, line = 1, ""
    for w in words:
        test = f"{line} {w}".strip()
        if line and draw.textlength(test, font=font) > MAX_W:
            lines, line = lines + 1, w
        else:
            line = test
    return lines


def blocks(words, draw, font):
    """Greedy two-line blocks; ends early at long pauses and sentence ends."""
    res, cur = [], []
    for w in words:
        if cur and w["start"] - cur[-1]["end"] > BREAK_GAP:
            res.append(cur)
            cur = []
        elif cur and line_count([x["text"] for x in cur + [w]], draw, font) > 2:
            # Prefer closing the block at the last punctuation in its second half.
            cut = max((i for i, x in enumerate(cur) if x["text"][-1] in ",.?!"), default=-1)
            if len(cur) // 2 <= cut < len(cur) - 1:
                res.append(cur[:cut + 1])
                cur = cur[cut + 1:]
            else:
                res.append(cur)
                cur = []
        cur.append(w)
        if w["text"][-1] in ".?!" and len(cur) >= 5:
            res.append(cur)
            cur = []
    if cur:
        res.append(cur)
    return res


def render_caption(words, path, font):
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lines, line = [], ""
    for w in words:
        test = f"{line} {w}".strip()
        if line and draw.textlength(test, font=font) > MAX_W:
            lines.append(line)
            line = w
        else:
            line = test
    lines.append(line)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d, sd = ImageDraw.Draw(img), ImageDraw.Draw(shadow)
    y = CAP_CENTER_Y - LINE_H * len(lines) / 2
    for ln in lines:
        x = (W - d.textlength(ln, font=font)) / 2
        sd.text((x + 3, y + 5), ln, font=font, fill=(0, 0, 0, 170), stroke_width=8, stroke_fill=(0, 0, 0, 170))
        d.text((x, y), ln, font=font, fill=(255, 255, 255), stroke_width=7, stroke_fill=(0, 0, 0))
        y += LINE_H
    Image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(5)), img).save(path)


def caption_track(clips, word_files, speed, work):
    """Writes a concat-demuxer list of full-frame PNGs (this ffmpeg may lack libass/drawtext)."""
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE, index=FONT_INDEX)
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    events, offset = [], 0.0
    for clip, words_file in zip(clips, word_files):
        words = json.loads(words_file.read_text()) if words_file else []
        for blk in blocks(words, draw, font):
            events.append([offset + blk[0]["start"] / speed, offset + blk[-1]["end"] / speed,
                           [w["text"] for w in blk]])
        offset += duration(clip) / speed
    total = offset
    for a, b in zip(events, events[1:]):
        a[1] = b[0] if b[0] - a[1] < HOLD_GAP else a[1] + 0.3
    if events:
        events[-1][1] = min(events[-1][1] + 0.4, total)

    caps = work / "caps"
    caps.mkdir(exist_ok=True)
    for old in caps.glob("*.png"):
        old.unlink()
    blank = caps / "blank.png"
    Image.new("RGBA", (W, H), (0, 0, 0, 0)).save(blank)
    entries, t = [], 0.0
    for i, (a, b, ws) in enumerate(events):
        png = caps / f"c{i:03d}.png"
        render_caption(ws, png, font)
        a = max(a, t)
        if a > t:
            entries.append((blank, a - t))
        entries.append((png, b - a))
        t = b
    # The concat demuxer ignores the last entry's duration, so a short blank closes the list.
    entries += [(blank, max(total - t, 0.1)), (blank, 0.04)]
    track = caps / "caps.txt"
    track.write_text("".join(f"file '{p}'\nduration {d:.4f}\n" for p, d in entries))
    for a, b, ws in events:
        print(f"{a:6.2f}-{b:6.2f}  {' '.join(ws)}")
    return track, total


def render(clips, track, total, speed, out):
    n = len(clips)
    fc = []
    for i in range(n):
        fc.append(f"[{i}:v]setpts=PTS/{speed},fps={FPS},crop='min(iw,ih*9/16)':ih,"
                  f"scale={W}:{H}:flags=lanczos,setsar=1[v{i}]")
        fc.append(f"[{i}:a]atempo={speed},aresample=48000[a{i}]")
    fc.append("".join(f"[v{i}][a{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=1[vc][ac]")
    if track:
        fc.append(f"[{n}:v]format=rgba,fps={FPS}[cap];[vc][cap]overlay=0:0:eof_action=pass,format=yuv420p[vout]")
    else:
        fc.append("[vc]format=yuv420p[vout]")
    fc.append("[ac]loudnorm=I=-15:TP=-1.5:LRA=11,aresample=48000[aout]")
    inputs = [arg for c in clips for arg in ("-i", str(c))]
    if track:
        inputs += ["-f", "concat", "-safe", "0", "-i", str(track)]
    log(f"Rendering {out.name} ({total:.0f}s)")
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
         "-map", "[vout]", "-map", "[aout]", "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(out)])


# Small enough to send through chat apps and upload limits.
def preview(out):
    dest = out.with_name(f"{out.stem}-preview.mp4")
    for crf in (26, 30, 34):
        run(["ffmpeg", "-v", "error", "-y", "-i", str(out), "-vf", "scale=720:1280:flags=lanczos",
             "-c:v", "libx264", "-preset", "medium", "-crf", str(crf), "-c:a", "aac", "-b:a", "96k",
             "-movflags", "+faststart", str(dest)])
        if dest.stat().st_size < PREVIEW_LIMIT:
            break
    return dest


def main():
    ap = argparse.ArgumentParser(prog="kings video-edit")
    ap.add_argument("inputs", nargs="*", help="video files, folders or Quick Share links")
    ap.add_argument("--name", required=True, help="project name: output folder and file name")
    ap.add_argument("--out", default=os.environ.get("KINGS_VIDEO_DIR", str(Path.home() / "Desktop")))
    ap.add_argument("--speed", type=float, default=1.25)
    ap.add_argument("--lang", default="pt")
    ap.add_argument("--no-captions", action="store_true")
    ap.add_argument("--transcribe-only", action="store_true", help="stop after writing the .words.json files")
    ap.add_argument("--preview", action="store_true", help="also write a 720p copy under 30 MB")
    args = ap.parse_args()

    project = Path(args.out).expanduser() / args.name
    work = project / ".work"
    raw = work / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    clips_file = work / "clips.json"

    # Without inputs, the project's previous clip list is reused (re-render after fixing words).
    if args.inputs:
        clips = collect_inputs(args.inputs, raw)
        clips_file.write_text(json.dumps([str(c) for c in clips], indent=2))
    elif clips_file.exists():
        clips = [Path(c) for c in json.loads(clips_file.read_text())]
    else:
        sys.exit("No inputs, and no earlier run of this project to reuse")
    if not clips:
        sys.exit("No videos found in the inputs")
    log("Clips in order: " + ", ".join(c.name for c in clips))

    word_files = [None] * len(clips)
    if not args.no_captions:
        word_files = [transcribe(c, work, args.lang) for c in clips]
        if args.transcribe_only:
            for f in word_files:
                print(f)
            return
    track, total = (None, sum(duration(c) for c in clips) / args.speed) if args.no_captions \
        else caption_track(clips, word_files, args.speed, work)

    out = project / f"{args.name}.mp4"
    render(clips, track, total, args.speed, out)
    print(out)
    if args.preview:
        print(preview(out))


if __name__ == "__main__":
    main()
