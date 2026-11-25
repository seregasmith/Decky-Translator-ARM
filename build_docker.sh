#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir="$project_dir/out"
artifact=Decky-Translator-arm64.zip

mkdir -p "$output_dir"
staging_dir=$(mktemp -d "$output_dir/.docker-build.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker buildx build \
    --platform linux/arm64 \
    --target artifact \
    --output "type=local,dest=$staging_dir,platform-split=false" \
    "$project_dir"

if [ ! -s "$staging_dir/$artifact" ]; then
    printf 'Docker did not export %s\n' "$artifact" >&2
    exit 1
fi

mv -f "$staging_dir/$artifact" "$output_dir/$artifact"
printf 'Built %s\n' "$output_dir/$artifact"
