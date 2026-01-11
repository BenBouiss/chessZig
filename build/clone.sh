echo "$PWD"
if [ ! -f $PWD/zig-out/bin/engine ]; then
	echo "engine not found at $PWD/zig-out/bin/engine"
else
	cp -u $PWD/zig-out/bin/engine engines/engine1
	cp -u $PWD/zig-out/bin/engine engines/engine2
	echo "done cloning to engines/engine2"
fi
