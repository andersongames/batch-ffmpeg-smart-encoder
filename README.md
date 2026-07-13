# Batch FFmpeg Smart Encoder

A highly resilient and automated Windows Batch script designed to recursively downscale videos to **720p (H.264/AAC)**. This script features pre-validation, post-encoding integrity checks, auto-correction retry loops, and precise event logging to prevent ghost failures or corrupted output files.

## Features
* **Recursive Processing:** Scans the input folder and all its subfolders automatically.
* **Structure Replication:** Mirrors your exact input subfolder tree into the output directory.
* **Smart Pre-Validation:** Skips files that have already been correctly converted, making it safe to stop and resume at any time.
* **Post-Encoding Integrity Check:** Inspects the video height and matches the stream duration with the source file using `ffprobe` to catch silent failures.
* **Auto-Correction Retry Loop:** Completely wipes corrupted outputs and automatically retries encoding up to a customizable limit if an error or asset mismatch is found.
* **Session Logging:** Generates a real-time `log.txt` track sheet alongside the script for effortless debugging.

---

## Requirements

To run this script, you must have **FFmpeg** and **FFprobe** installed and added to your system's Environment Variables (`PATH`).

* **Official Website:** Download the latest builds directly from the [Official FFmpeg Website](https://ffmpeg.org/).

> 💡 *Test if it is ready by opening your Command Prompt (`cmd`) and typing `ffmpeg -version` and `ffprobe -version` before launching the script.*

---

## Configurable Variables

Open the `.bat` file in any text editor to modify the following internal environment variables according to your environment layout and hardware capabilities:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `SOURCE` | `E:\Downloads\Torrent\anime\input` | The absolute directory path where your source raw media files are located. |
| `DESTINATION` | `E:\Downloads\Torrent\anime\output` | The absolute directory path where the processed 720p files will be deployed. |
| `THREADS` | `6` | Limits the maximum CPU threads allocated to FFmpeg (prevents 100% CPU system freezes). |
| `MAX_ATTEMPTS` | `3` | Number of sequential encoding retries allowed per file before marking it as a definitive failure and moving to the next block. |

---

## Technical Specifications (Encoding Profile)

The script forces the following video parameters for optimized compatibility and file-size reductions:
* **Video Codec:** `libx264` (H.264 profile)
* **Resolution:** Scaled to a locked height of `720p` (`-vf scale=-1:720`) maintaining original aspect ratio.
* **Quality Target:** `-crf 23`
* **Audio Codec:** `aac`
* **Subtitles:** Copied natively from the source stream container (`-c:s copy`)

---

## How To Use

1. Clone or download this repository.
2. Edit the script settings to match your `SOURCE` and `DESTINATION` paths.
3. Place your script anywhere or execute `auto-720p-encoder.bat`.
4. Monitor progress directly via the CLI terminal window or read `log.txt` for historic session tracking data.