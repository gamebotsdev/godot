#!/bin/bash
if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for tag selection. Please install it (e.g., sudo apt install fzf) and try again."
    exit 1
fi

# Save current branch or commit
current_ref=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_ref" = "HEAD" ]; then
    current_ref=$(git rev-parse HEAD)
fi
restore_branch() {
    echo "Restoring original branch/commit: $current_ref"
    git checkout "$current_ref"
}
trap restore_branch EXIT

git fetch --tags
TAG_FILE="$(dirname "$0")/.last_tag"
initial_query=""
if [ -f "$TAG_FILE" ]; then
    last_tag=$(cat "$TAG_FILE")
    if git tag | grep -qx "$last_tag"; then
        initial_query="--query=$last_tag"
    fi
fi
tag=$(git tag | fzf --prompt="Select tag: " $initial_query)
[ -z "$tag" ] && { echo "No tag selected."; exit 1; }
echo "$tag" > "$TAG_FILE"
git checkout "$tag" || { echo "Failed to checkout tag $tag"; exit 1; }
scons -j$(nproc) platform=linuxbsd target=editor dev_build=yes debug_symbols=yes compiledb=yes "$@"

# Determine if C# (Mono) build by checking args
is_mono=false
for arg in "$@"; do
    if [ "$arg" = "module_mono_enabled=yes" ]; then
        is_mono=true
        break
    fi
done

if [ "$is_mono" = true ]; then
    output_bin="bin/godot.linuxbsd.editor.dev.x86_64.mono"
    tagged_bin="bin/godot.linuxbsd.editor.${tag}.dev.x86_64.mono"
else
    output_bin="bin/godot.linuxbsd.editor.dev.x86_64"
    tagged_bin="bin/godot.linuxbsd.editor.${tag}.dev.x86_64"
fi

if [ -f "$output_bin" ]; then
    mv "$output_bin" "$tagged_bin"
    echo "Renamed $output_bin to $tagged_bin"
else
    echo "Build did not produce $output_bin"
fi

# For mono builds, generate glue and build assemblies after renaming
if [ "$is_mono" = true ]; then
    if [ -f "$tagged_bin" ]; then
        "$tagged_bin" --headless --generate-mono-glue modules/mono/glue
        python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir bin
    else
        echo "Mono binary $tagged_bin not found for glue generation."
    fi
fi
