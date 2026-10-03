#!/usr/bin/env sh
### ==============================================================================
### SCRIPT NAME: batch-auto-encoder.sh
### DESCRIPTION: Recursively scans, checks, and encodes video files using FFmpeg.
### AUTHOR: Anderson Games
### ==============================================================================
### Exit immediately if a command exits with a non-zero status - safety guard
set -eu
### ------------------------------------------------------------------------------
### CONSTANTS & CONFIGURATION DEFAULTS
### ------------------------------------------------------------------------------
CONFIG_FILE="config.cfg"
LOG_FILE="log.txt"

DEFAULT_SOURCE_DIR="."
DEFAULT_DESTINATION_DIR="encode-output"
DEFAULT_REPLICATE_SRC_DIR="true"
DEFAULT_EXTENSIONS=""
DEFAULT_RESOLUTION_HEIGHT="720"
DEFAULT_VIDEO_CODEC="libx265"
DEFAULT_VIDEO_CRF="28"
DEFAULT_MAX_THREADS=""
DEFAULT_MAX_ATTEMPTS="3"
DEFAULT_MAX_TOLERANCE="2"
DEFAULT_KEEP_INVALID_FILES="false"
DEFAULT_DRY_RUN="false"

### ------------------------------------------------------------------------------
### LOGGING UTILITIES
### ------------------------------------------------------------------------------
write_log() {
    local prefix="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [%s] %s\n" "$timestamp" "$prefix" "$message" >> "$LOG_FILE"
}

log_notice() {
    write_log "NOTICE" "$1"
    printf "[NOTICE] %s\n" "$1"
}

log_dry_run() {
    write_log "DRY-RUN" "$1"
    printf "[DRY-RUN] %s\n" "$1"
}

log_success() {
    write_log "SUCCESS" "$1"
    printf "[SUCCESS] %s\n" "$1"
}

log_skipped_valid() {
    write_log "SKIPPED/VALID" "$1"
    printf "[SKIPPED/VALID] %s\n" "$1"
}

log_error() {
    write_log "ERROR" "$1"
    printf "[ERROR] %s\n" "$1" >&2
}

log_critical() {
    write_log "CRITICAL" "$1"
    printf "[CRITICAL] %s\n" "$1" >&2
    exit 1
}

### ------------------------------------------------------------------------------
### CONFIGURATION MANAGEMENT (Pure-ish side-effect boundaries)
### ------------------------------------------------------------------------------
generate_default_config() {
    cat << EOF > "$CONFIG_FILE"
SOURCE_DIR=$DEFAULT_SOURCE_DIR
DESTINATION_DIR=$DEFAULT_DESTINATION_DIR
REPLICATE_SRC_DIR=$DEFAULT_REPLICATE_SRC_DIR
EXTENSIONS=$DEFAULT_EXTENSIONS
RESOLUTION_HEIGHT=$DEFAULT_RESOLUTION_HEIGHT
VIDEO_CODEC=$DEFAULT_VIDEO_CODEC
VIDEO_CRF=$DEFAULT_VIDEO_CRF
MAX_THREADS=$DEFAULT_MAX_THREADS
MAX_ATTEMPTS=$DEFAULT_MAX_ATTEMPTS
MAX_TOLERANCE=$DEFAULT_MAX_TOLERANCE
KEEP_INVALID_FILES=$DEFAULT_KEEP_INVALID_FILES
DRY_RUN=$DEFAULT_DRY_RUN
EOF
    log_notice "Generated default configuration file: $CONFIG_FILE"
}

init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        generate_default_config
    fi
}

get_config_value() {
    local key="$1"
    local val
    val=$(grep "^[[:space:]]*$key=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '\r' | sed 's/^[[:space:]]//;s/[[:space:]]*$//')
    printf "%s" "$val"
}

ensure_config_key() {
    local key="$1"
    local default_val="$2"
    if ! grep -q "^[[:space:]]*$key=" "$CONFIG_FILE" 2>/dev/null; then
        printf "%s=%s\n" "$key" "$default_val" >> "$CONFIG_FILE"
        log_notice "Added missing configuration key '$key' with default value."
    fi
}

validate_and_fix_config() {
    init_config
    ensure_config_key "SOURCE_DIR" "$DEFAULT_SOURCE_DIR"
    ensure_config_key "DESTINATION_DIR" "$DEFAULT_DESTINATION_DIR"
    ensure_config_key "REPLICATE_SRC_DIR" "$DEFAULT_REPLICATE_SRC_DIR"
    ensure_config_key "EXTENSIONS" "$DEFAULT_EXTENSIONS"
    ensure_config_key "RESOLUTION_HEIGHT" "$DEFAULT_RESOLUTION_HEIGHT"
    ensure_config_key "VIDEO_CODEC" "$DEFAULT_VIDEO_CODEC"
    ensure_config_key "VIDEO_CRF" "$DEFAULT_VIDEO_CRF"
    ensure_config_key "MAX_THREADS" "$DEFAULT_MAX_THREADS"
    ensure_config_key "MAX_ATTEMPTS" "$DEFAULT_MAX_ATTEMPTS"
    ensure_config_key "MAX_TOLERANCE" "$DEFAULT_MAX_TOLERANCE"
    ensure_config_key "KEEP_INVALID_FILES" "$DEFAULT_KEEP_INVALID_FILES"
    ensure_config_key "DRY_RUN" "$DEFAULT_DRY_RUN"
}

### ------------------------------------------------------------------------------
### SYSTEM DEPENDENCIES & METADATA UTILITIES (Pure-ish functions)
### ------------------------------------------------------------------------------
check_dependencies() {
    if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
        log_critical "ffmpeg or ffprobe not installed. Install with package manager (e.g., sudo apt install ffmpeg) and try again."
    fi
    local ffmpeg_ver ffprobe_ver
    ffmpeg_ver=$(ffmpeg -version 2>/dev/null | head -n 1)
    ffprobe_ver=$(ffprobe -version 2>/dev/null | head -n 1)
    log_notice "Dependencies check passed. FFmpeg: $ffmpeg_ver | FFprobe: $ffprobe_ver"
}

get_video_resolution_height() {
    local file="$1"
    ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0"
}

get_video_duration() {
    local file="$1"
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0"
}

is_extension_allowed() {
    local ext="$1"
    local extensions_cfg="$2"
    if [ -z "$extensions_cfg" ]; then
        return 0
    fi
    local normalized_ext
    normalized_ext=$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')
    local old_ifs="$IFS"
    IFS=','
    for allowed in $extensions_cfg; do
        allowed=$(printf "%s" "$allowed" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        if [ "$normalized_ext" = "$allowed" ]; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}

### ------------------------------------------------------------------------------
### MAIN EXECUTION FLOW
### ------------------------------------------------------------------------------
main() {
    touch "$LOG_FILE"
    log_notice "Session started."

    validate_and_fix_config
    check_dependencies

    local src_dir dest_dir replicate_src ext_filter target_height codec crf max_threads max_attempts max_tolerance keep_invalid dry_run
    src_dir=$(get_config_value "SOURCE_DIR")
    dest_dir=$(get_config_value "DESTINATION_DIR")
    replicate_src=$(get_config_value "REPLICATE_SRC_DIR")
    ext_filter=$(get_config_value "EXTENSIONS")
    target_height=$(get_config_value "RESOLUTION_HEIGHT")
    codec=$(get_config_value "VIDEO_CODEC")
    crf=$(get_config_value "VIDEO_CRF")
    max_threads=$(get_config_value "MAX_THREADS")
    max_attempts=$(get_config_value "MAX_ATTEMPTS")
    max_tolerance=$(get_config_value "MAX_TOLERANCE")
    keep_invalid=$(get_config_value "KEEP_INVALID_FILES")
    dry_run=$(get_config_value "DRY_RUN")

    if [ ! -d "$src_dir" ]; then
        log_critical "Source directory '$src_dir' does not exist or is not a directory."
    fi

    if [ ! -d "$dest_dir" ]; then
        mkdir -p "$dest_dir"
        log_notice "Created destination directory: $dest_dir"
    fi

    # Validate codec and CRF fallback
    case "$codec" in
        libx264|libx265|libsvtav1) ;;
        *)
            log_notice "Invalid VIDEO_CODEC '$codec'. Falling back to default 'libx265'."
            codec="libx265"
            ;;
    esac

    case "$crf" in
        *[!0-9]*)
            log_notice "Invalid VIDEO_CRF '$crf'. Falling back to default '28'."
            crf="28"
            ;;
        *)
            if [ "$crf" -lt 0 ] || [ "$crf" -gt 51 ]; then
                log_notice "Invalid VIDEO_CRF '$crf' out of range [0-51]. Falling back to default '28'."
                crf="28"
            fi
            ;;
    esac

    log_notice "Scanning directory: $src_dir (Target Height: ${target_height}p, Codec: $codec, CRF: $crf, Dry Run: $dry_run)"

    local total_processed=0 total_success=0 total_skipped=0 total_errors=0

    while IFS= read -r file_path; do
        [ -z "$file_path" ] && continue

        local rel_path=""
        if [ "$replicate_src" = "true" ]; then
            # Compute relative path from src_dir
            rel_path="${file_path#"$src_dir"}"
            rel_path="${rel_path#/}"
        else
            rel_path=$(basename "$file_path")
        fi

        local full_filename
        full_filename=$(basename "$file_path")
        local ext=""
        local base_name=""

        if printf "%s" "$full_filename" | grep -q '\.'; then
            ext="${full_filename##*.}"
            base_name="${full_filename%.*}"
        else
            ext=""
            base_name="$full_filename"
        fi

        if ! is_extension_allowed "$ext" "$ext_filter"; then
            continue
        fi

        # Get source resolution height to check if it's lower or equal to target height (e.g. 720p, 1080p)
        local src_height
        src_height=$(get_video_resolution_height "$file_path")

        if [ "$src_height" -gt 0 ] && [ "$src_height" -le "$target_height" ]; then
            write_log "SKIPPED/LOW-RES" "Skipped file \"$full_filename\": source height (${src_height}p) is less than or equal to target height (${target_height}p)."
            printf "[SKIPPED/LOW-RES] Skipped file \"%s\": source height (%sp) is <= target height (%sp).\n" "$full_filename" "$src_height" "$target_height"
            total_skipped=$((total_skipped + 1))
            continue
        fi

        total_processed=$((total_processed + 1))

        local dest_file_dir="$dest_dir"
        if [ "$replicate_src" = "true" ]; then
            local sub_dir
            sub_dir=$(dirname "$rel_path")
            if [ "$sub_dir" != "." ] && [ -n "$sub_dir" ]; then
                dest_file_dir="$dest_dir/$sub_dir"
            fi
        fi

        [ ! -d "$dest_file_dir" ] && mkdir -p "$dest_file_dir"

        local target_file_path="$dest_file_dir/$full_filename"
        local needs_suffix=0
        local process_file=1

        if [ -f "$target_file_path" ]; then
            local dest_height dest_duration src_duration
            dest_height=$(get_video_resolution_height "$target_file_path")
            dest_duration=$(get_video_duration "$target_file_path")
            src_duration=$(get_video_duration "$file_path")

            local dur_diff=0
            if command -v awk >/dev/null 2>&1; then
                dur_diff=$(awk -v d1="$dest_duration" -v d2="$src_duration" 'BEGIN { diff = d1 - d2; if (diff < 0) diff = -diff; print diff }')
            else
                dur_diff=0
            fi

            local is_valid=0
            # Check validity: resolution height matches target AND duration within tolerance
            if [ "$dest_height" -eq "$target_height" ] && [ "$(echo "$dur_diff <= $max_tolerance" | bc 2>/dev/null || echo 1)" -eq 1 ]; then
                is_valid=1
            fi

            if [ "$is_valid" -eq 1 ]; then
                log_skipped_valid "Skipped valid destination file: \"$full_filename\""
                total_skipped=$((total_skipped + 1))
                process_file=0
            else
                log_notice "Destination file \"$full_filename\" is invalid. Handling invalid file."
                if [ "$keep_invalid" = "true" ]; then
                    local invalid_target="$dest_file_dir/${base_name}-INVALID.$ext"
                    mv "$target_file_path" "$invalid_target"
                    log_notice "Renamed invalid file to: $(basename "$invalid_target")"
                else
                    rm -f "$target_file_path"
                    log_notice "Removed invalid destination file: $full_filename"
                fi
                needs_suffix=1
            fi
        fi

        if [ "$process_file" -eq 1 ]; then
            local final_dest_filename="$full_filename"
            if [ "$needs_suffix" -eq 1 ] || [ -f "$dest_file_dir/$full_filename" ]; then
                final_dest_filename="${base_name}-${target_height}p.${ext}"
            fi
            local final_dest_path="$dest_file_dir/$final_dest_filename"

            if [ "$dry_run" = "true" ]; then
                log_dry_run "\"$file_path\" -> \"$final_dest_path\" (Target Height: ${target_height}p, Codec: $codec)"
                total_success=$((total_success + 1))
            else
                check_dependencies
                local attempt=1
                local success=0

                while [ "$attempt" -le "$max_attempts" ]; do
                    log_notice "Encoding attempt $attempt of $max_attempts for: \"$full_filename\""
                    
                    # Scale based on target height maintaining aspect ratio (-2 ensures height is divisible by 2 for encoders)
                    local vf_filter="scale=-2:${target_height}"
                    local thread_arg=""
                    if [ -n "$max_threads" ]; then
                        thread_arg="-threads $max_threads"
                    fi

                    if ffmpeg -y -i "$file_path" -vf "$vf_filter" -c:v "$codec" -crf "$crf" $thread_arg -map 0 "$final_dest_path" >/dev/null 2>&1; then
                        success=1
                        break
                    else
                        if [ ! -f "$final_dest_path" ] || [ ! -s "$final_dest_path" ]; then
                            log_critical "Disk space insufficient or file creation failed for \"$full_filename\". Cleaning up and exiting."
                        fi
                        rm -f "$final_dest_path"
                        attempt=$((attempt + 1))
                    fi
                done

                if [ "$success" -eq 1 ]; then
                    log_success "Successfully encoded: \"$full_filename\" -> \"$final_dest_filename\""
                    total_success=$((total_success + 1))
                else
                    log_error "Failed to encode \"$full_filename\" after $max_attempts attempts."
                    rm -f "$final_dest_path"
                    total_errors=$((total_errors + 1))
                fi
            fi
        fi

    done <<EOF
$(find "$src_dir" -type f ! -path "*/$dest_dir/*" ! -name "$CONFIG_FILE" ! -name "$LOG_FILE")
EOF

    log_notice "Session finished."
    log_notice "Summary -> Total Processed: $total_processed | Success/Simulated: $total_success | Skipped (Valid): $total_skipped | Errors: $total_errors"
    printf "Execution complete. Check %s for details.\n" "$LOG_FILE"
}

main "$@"