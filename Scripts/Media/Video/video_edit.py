"""Joins clips in recording order, speeds them up and burns two-line block captions.

Optional: fast-forward stretches (walking between places), mute, and split into parts that fit a
platform's length limit, cut where nobody is talking.

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
from datetime import datetime
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
FAST_DEFAULT = 4.0


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


def local_time(stamp):
    if not stamp:
        return "unknown date"
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")


def clock(sec):
    return f"{int(sec // 60)}:{sec % 60:04.1f}"


def seconds(text):
    """Accepts 75, 75.5 or 1:15."""
    minutes, _, sec = text.rpartition(":")
    return float(minutes or 0) * 60 + float(sec)


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


def words_path(clip, work):
    # A clip downloaded by another project keeps its transcript there, so splitting one download
    # into several videos never transcribes a clip twice.
    if clip.parent.name == "raw" and clip.parent.parent.name == ".work":
        work = clip.parent.parent
    return work / f"{clip.stem}.words.json"


def transcribe(clip, work, lang):
    """Writes <clip>.words.json once; later edits to it (fixed words, removed lines) are kept."""
    words_file = words_path(clip, work)
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


def parse_fast(specs, n):
    """`--fast 2:1:10-1:40x6` fast-forwards clip 2 from 1:10 to 1:40 at 6x (x4 when omitted)."""
    fast = {i: [] for i in range(n)}
    for spec in specs:
        m = re.fullmatch(r"(\d+):([\d:.]+)-([\d:.]+)(?:x([\d.]+))?", spec)
        if not m or not 1 <= int(m.group(1)) <= n:
            sys.exit(f"Bad --fast {spec!r}: use CLIP:START-END[xFACTOR], clips numbered from 1")
        fast[int(m.group(1)) - 1].append((seconds(m.group(2)), seconds(m.group(3)), float(m.group(4) or FAST_DEFAULT)))
    return fast


def timeline(clips, speed, fast):
    """Per clip, the pieces it plays as: (start, end, speed, audible, output start)."""
    pieces, t = [], 0.0
    for i, clip in enumerate(clips):
        length, pos, own = duration(clip), 0.0, []
        for a, b, factor in sorted(fast[i]):
            a, b = max(a, pos), min(b, length)
            if b <= a:
                continue
            if a > pos:
                own.append((pos, a, speed, True))
            own.append((a, b, factor, False))
            pos = b
        if pos < length:
            own.append((pos, length, speed, True))
        clip_pieces = []
        for a, b, sp, audible in own:
            clip_pieces.append((a, b, sp, audible, t))
            t += (b - a) / sp
        pieces.append(clip_pieces)
    return pieces, t


def to_output(clip_pieces, sec):
    """Output time of a source second, or None inside a fast-forward (no captions there)."""
    for a, b, sp, audible, start in clip_pieces:
        if a <= sec < b:
            return start + (sec - a) / sp if audible else None
    return None


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


def caption_events(pieces, word_files):
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE, index=FONT_INDEX)
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    events = []
    for clip_pieces, words_file in zip(pieces, word_files):
        words = []
        for w in json.loads(words_file.read_text()):
            start, end = to_output(clip_pieces, w["start"]), to_output(clip_pieces, max(w["end"] - 0.01, w["start"]))
            if start is not None and end is not None:
                words.append({"start": start, "end": end, "text": w["text"]})
        for blk in blocks(words, draw, font):
            events.append([blk[0]["start"], blk[-1]["end"], [w["text"] for w in blk]])
    return events, font


def caption_track(events, font, total, work):
    """Writes a concat-demuxer list of full-frame PNGs (this ffmpeg may lack libass/drawtext)."""
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
        print(f"{clock(a):>7} {clock(b):>7}  {' '.join(ws)}")
    return track


def atempo(factor):
    # atempo accepts 0.5–2 per instance, so faster factors are chained.
    steps = []
    while factor > 2:
        steps.append("atempo=2")
        factor /= 2
    return ",".join(steps + [f"atempo={factor:.4f}"])


def render(clips, pieces, track, total, mute, out):
    fc, labels = [], []
    for i, clip_pieces in enumerate(pieces):
        k = len(clip_pieces)
        fc.append(f"[{i}:v]split={k}" + "".join(f"[vs{i}_{j}]" for j in range(k)))
        if not mute:
            fc.append(f"[{i}:a]asplit={k}" + "".join(f"[as{i}_{j}]" for j in range(k)))
        for j, (a, b, sp, audible, _) in enumerate(clip_pieces):
            fc.append(f"[vs{i}_{j}]trim=start={a:.3f}:end={b:.3f},setpts=(PTS-STARTPTS)/{sp},fps={FPS},"
                      f"crop='min(iw,ih*9/16)':ih,scale={W}:{H}:flags=lanczos,setsar=1[v{i}_{j}]")
            labels.append(f"[v{i}_{j}]")
            if not mute:
                # Fast-forwarded stretches play silent: sped-up voices only distract.
                silence = "" if audible else ",volume=0"
                fc.append(f"[as{i}_{j}]atrim=start={a:.3f}:end={b:.3f},asetpts=PTS-STARTPTS,"
                          f"{atempo(sp)}{silence},aresample=48000[a{i}_{j}]")
                labels.append(f"[a{i}_{j}]")
    n = len(labels) // (1 if mute else 2)
    fc.append("".join(labels) + f"concat=n={n}:v=1:a={0 if mute else 1}" + ("[vc]" if mute else "[vc][ac]"))
    if track:
        fc.append(f"[{len(clips)}:v]format=rgba,fps={FPS}[cap];[vc][cap]overlay=0:0:eof_action=pass,format=yuv420p[vout]")
    else:
        fc.append("[vc]format=yuv420p[vout]")
    maps = ["-map", "[vout]"]
    audio = ["-an"]
    if not mute:
        fc.append("[ac]loudnorm=I=-15:TP=-1.5:LRA=11,aresample=48000[aout]")
        maps += ["-map", "[aout]"]
        audio = ["-c:a", "aac", "-b:a", "160k"]
    inputs = [arg for c in clips for arg in ("-i", str(c))]
    if track:
        inputs += ["-f", "concat", "-safe", "0", "-i", str(track)]
    log(f"Rendering {out.name} ({clock(total)})")
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc), *maps, "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-profile:v", "high", "-pix_fmt", "yuv420p",
         *audio, "-movflags", "+faststart", str(out)])


def split_points(total, limit, events):
    """Boundaries for parts of similar length, none over `limit`, in the silence before a caption block."""
    gaps = [b[0] - 0.05 for a, b in zip(events, events[1:]) if b[0] - a[1] > 0.15]
    starts = [e[0] - 0.05 for e in events]
    points, cur = [], 0.0
    while total - cur > limit:
        target = cur + (total - cur) / -(-(total - cur) // limit)
        window = lambda xs: [x for x in xs if cur + limit / 3 < x <= cur + limit]
        candidates = window(gaps) or window(starts) or [min(target, cur + limit)]
        cut = min(candidates, key=lambda x: abs(x - target))
        points.append(cut)
        cur = cut
    return points


def split(out, total, points, mute):
    parts, edges = [], [0.0] + points + [total]
    for k, (a, b) in enumerate(zip(edges, edges[1:]), 1):
        dest = out.with_name(f"{out.stem}-part{k}.mp4")
        audio = ["-an"] if mute else ["-c:a", "aac", "-b:a", "160k"]
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.3f}", "-to", f"{b:.3f}", "-i", str(out),
             "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-profile:v", "high", "-pix_fmt", "yuv420p",
             *audio, "-movflags", "+faststart", str(dest)])
        log(f"{dest.name}: {clock(a)}–{clock(b)} ({b - a:.0f}s)")
        parts.append(dest)
    return parts


# Small enough to send through chat apps and upload limits.
def preview(out, mute):
    dest = out.with_name(f"{out.stem}-preview.mp4")
    audio = ["-an"] if mute else ["-c:a", "aac", "-b:a", "96k"]
    for crf in (26, 30, 34):
        run(["ffmpeg", "-v", "error", "-y", "-i", str(out), "-vf", "scale=720:1280:flags=lanczos",
             "-c:v", "libx264", "-preset", "medium", "-crf", str(crf), *audio,
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
    ap.add_argument("--mute", action="store_true", help="no audio and no captions (music is added when posting)")
    ap.add_argument("--fast", action="append", default=[], metavar="CLIP:START-END[xF]",
                    help="fast-forward a stretch, silent and without captions; repeatable")
    ap.add_argument("--max-length", type=float, help="also split into parts of at most this many seconds")
    ap.add_argument("--list", action="store_true", help="only list the clips with recording time and length")
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
    for k, c in enumerate(clips, 1):
        log(f"{k}. {c.name}  {local_time(recorded_at(c))}  {clock(duration(c))}")
    if args.list:
        return

    captions = not (args.no_captions or args.mute)
    pieces, total = timeline(clips, args.speed, parse_fast(args.fast, len(clips)))
    events, track = [], None
    if captions:
        word_files = [transcribe(c, work, args.lang) for c in clips]
        if args.transcribe_only:
            for f in word_files:
                print(f)
            return
        events, font = caption_events(pieces, word_files)
        track = caption_track(events, font, total, work)

    out = project / f"{args.name}.mp4"
    render(clips, pieces, track, total, args.mute, out)
    outputs = [out]
    if args.max_length and total > args.max_length:
        outputs = split(out, total, split_points(total, args.max_length, events), args.mute)
        # The parts are the deliverable; the joined file would only double the disk use.
        out.unlink()
    for o in outputs:
        print(o)
        if args.preview:
            print(preview(o, args.mute))


if __name__ == "__main__":
    main()
