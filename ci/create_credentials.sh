#! /usr/bin/env sh
# This file is a convenience script to copy credentials passed via CI environment variables
# to the correct location in the project. It will not overwrite existing files.

CREDENTIALS_STRING="$1"
KEY_STRING="$2"
CREDENTIALS_FILE="config/credentials.yml.enc"
KEY_FILE="config/master.key"

if [ -z "$CREDENTIALS_STRING" ]; then
    echo "No credentials string provided."
    echo "Usage: $0 <credentials string> <key string>"
    exit 1
fi
if [ -z "$KEY_STRING" ]; then
    echo "No key string provided."
    echo "Usage: $0 <credentials string> <key string>"
    exit 1
fi

if [ -f "$CREDENTIALS_FILE" ]; then
    echo "Credentials file already exist: $CREDENTIALS_FILE"
    echo "Not overwriting it."
else
  printf '%s' "$CREDENTIALS_STRING" >"$CREDENTIALS_FILE"
fi

if [ -f "$KEY_FILE" ]; then
    echo "Key file already exist: $KEY_FILE"
    echo "Not overwriting it."
else
    printf '%s' "$KEY_STRING" >"$KEY_FILE"
fi
