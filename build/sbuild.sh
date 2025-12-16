
#me="$(whoami)"
me="$USER"
tmp_folder="/home/$me/.zig-tmp"
mkdir -p "$tmp_folder"
echo "Creating temporary folder at: $tmp_folder"

export ZIG_LOCAL_CACHE_DIR="$tmp_folder/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR="$tmp_folder/.zig-cache"

zig build -DfastBitscan=true -DuseMagic=true -DuseStaged=true
