UCI complient chess engine project to try out the zig programming language.

Multiple files exist in the build/ directory due to a bug with the zig build command on wsl. The current work around is to set the env variable ZIG_LOCAL_CACHE_DIR to somewhere in the linux filesystem part and the the windows part.

Running for zig version 0.16
Make and run:
```
 ./build/build.sh && ./zig-out/bin/engine
```

comptime build arguments:
- useStaged: Staged move generation or not
- useDebug: Performs sanityChecks at various stage of the move making / unmaking and more
- useAvx2: (experimental) enable to change the way to get checkers / pinners bitboard during the "staged" move generation

Sources: 
- https://www.chessprogramming.org/
- https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator#comments-section
- https://github.com/nescitus/cpw-engine/
- https://github.com/abulmo/hqperft
- https://github.com/AndyGrant/Ethereal/tree/master for the texel paper
- https://github.com/jnlt3/weather-factory Tuning tool
- https://github.com/jw1912/bullet/ NNUE trainer
- https://github.com/aqrit/sse2zig SSE stuffs
- https://github.com/Adam-Kulju/Patricia/ 

## Supported UCI commands:

- uci
- isready
- position
- go
    - searchmoves
    - <>
    - perft 
- stop
- quit
- ucinewgame
- setoption
- debug: [on | off]

Extra commands:
- print: prints the currently set position
- benchmark: launches a benchmark
- printparams: print tuning parameters

Performance profiling:
Currently the way to test wether a feature accelerates chess operations is to launch a perft and profile the resulting ELF file with [samply]. Exemple:
```
 samply record ./zig-out/bin/chess
```
