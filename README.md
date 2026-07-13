# 🎬 Batch FFmpeg Smart Encoder

A highly resilient and automated Windows Batch script designed to recursively downscale videos to **720p (H.264/AAC)**. This script features pre-validation, post-encoding integrity checks, auto-correction retry loops, and precise event logging to prevent ghost failures or corrupted output files.

---

## 🚀 Features
* **Recursive Processing:** Scans the input folder and all its subfolders automatically.
* **Structure Replication:** Mirrors your exact input subfolder tree into the output directory.
* **Smart Pre-Validation:** Skips files that have already been correctly converted, making it safe to stop and resume at any time.
* **Post-Encoding Integrity Check:** Inspects the video height and matches the stream duration with the source file using `ffprobe` to catch silent failures.
* **Auto-Correction Retry Loop:** Completely wipes corrupted outputs and automatically retries encoding up to a customizable limit if an error or asset mismatch is found.
* **Session Logging:** Generates a real-time `log.txt` track sheet alongside the script for effortless debugging.
* **Plug-and-Play Portability:** Automatically detects its own execution directory if no configuration exists, allowing zero-setup operations.

---

## 🛠️ Requirements

To run this script, you must have **FFmpeg** and **FFprobe** installed and added to your system's Environment Variables (`PATH`).

* **Official Website:** Download the latest builds directly from the [Official FFmpeg Website](https://ffmpeg.org/).

> 💡 *Test if it is ready by opening your Command Prompt (`cmd`) and typing `ffmpeg -version` and `ffprobe -version` before launching the script.*

---

## ⚙️ Configuration (`config.cfg`)

You **do not** need to edit the `.bat` file. Upon its first launch, the script automatically generates a dedicated user configuration file named `config.cfg` in the same directory. 

Open `config.cfg` in any text editor to modify your settings. The script features an internal validation layer that automatically checks your inputs before processing.

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `SOURCE` | *Script execution folder* | The absolute directory path where your source raw media files are located. |
| `DESTINATION` | *Script execution folder* | The absolute directory path where the processed 720p files will be deployed. |
| `THREADS` | `6` | Limits the maximum CPU threads allocated to FFmpeg (prevents 100% CPU system freezes). |
| `MAX_ATTEMPTS` | `3` | Number of sequential encoding retries allowed per file before marking it as a definitive failure and moving to the next block. |

---

## 📊 Technical Specifications (Encoding Profile)

The script forces the following video parameters for optimized compatibility and file-size reductions:
* **Video Codec:** `libx264` (H.264 profile)
* **Resolution:** Scaled to a locked height of `720p` (`-vf scale=-1:720`) maintaining original aspect ratio.
* **Quality Target:** `-crf 23`
* **Audio Codec:** `aac`
* **Subtitles:** Copied natively from the source stream container (`-c:s copy`)

---

## 📝 How To Use

1. **Download:** Clone or download this repository to your system.
2. **First Run (Initialization):** Double-click `auto-720p-encoder.bat`. The script will detect that `config.cfg` is missing, safely generate a default one pointing to its current directory, and halt with a notification.
3. **Customize (Optional):** Open the newly created `config.cfg` to adjust your paths (`SOURCE` / `DESTINATION`) or hardware preferences (`THREADS`), then save the file.
4. **Execution:** Run `auto-720p-encoder.bat` again. The script will validate your `config.cfg` parameters and immediately begin processing your media assets.
5. **Monitor:** Trace progress directly via the CLI terminal window or read `log.txt` for historical session tracking and error reports.