#!/bin/bash
# Convert MP3 sound files to WAV for better compatibility with aplay

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOUNDS_DIR="$SCRIPT_DIR/../sounds"

echo "Converting sound files to WAV format..."

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo "Installing ffmpeg..."
    sudo apt-get update
    sudo apt-get install -y ffmpeg
fi

cd "$SOUNDS_DIR"

# Convert each MP3 to WAV
for mp3_file in *.mp3; do
    if [ -f "$mp3_file" ]; then
        wav_file="${mp3_file%.mp3}.wav"
        echo "Converting $mp3_file to $wav_file..."
        ffmpeg -i "$mp3_file" -acodec pcm_s16le -ar 44100 -ac 2 "$wav_file" -y
    fi
done

echo "Conversion complete!"
ls -lh *.wav
