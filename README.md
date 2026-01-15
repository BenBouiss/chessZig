Uci complient chess engine project to try out the zig programming language.Uci complient chess engine project to try out the zig programming language. 


Multiple files exist in the build/ directory due to a bug with the zig build command on wsl. The current work around is to set the env variable ZIG_LOCAL_CACHE_DIR to somewhere in the linux filesystem part and the the windows part.

Installation:
```
 ./build/build.sh && ./zig-out/bin/engine
```
make and run

comptime build arguments:
- useStaged: Staged move generation or not
- useMagic: Use magic method for slider pieces move generation
- fastBiscan: Use of the "intrinsics" file for bitscan and reverseBitscan
- useDebug: Performs sanityChecks at various stage of the move making / unmaking
- useHash: (not used) Wether to use the hash table for previous explored move to retrieve the evaluation / nbr of moves
  - This option is now up to the engine using the setoption name useHash value true
- useAvx2: (experimental) enable to change the way to get checkers / pinners bitboard during the "staged" move generation


build script:
- build.sh: Standard zig debug build with default comptime arguments
- fbuild.sh: ReleaseFast zig build with "fastBiscan"
- fmbuild.sh: ReleaseFast zig build with "fastBiscan" and "magic"
- fsbuild.sh: ReleaseFast zig build with "fastBiscan", "staged" and "magic"
- test.sh: Runs the tests
...


Tasklist:
- (?)Remove the p_state.pieceBB[14] into 14 independant values with the correct names 

Sources: 
- https://www.chessprogramming.org/
- https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator#comments-section
- https://github.com/abulmo/hqperft

Values: 

|Nodes|Capture|Doublepush|Enpassant|castling|promotions|

|=====|=======|==========|=========|========|==========|

|20|0|8|0|0|0|

|400|0|160|0|0|0|

|8902|34|2800|0|0|0|

|197281|1576|61730|0|0|0|

|4865609|82719|1211076|258|0|0|

|119060324|2812008|29374680|5248|0|0|

|3195901860|108329926|644115108|319617|883453|0|

depth = 1: 0 ms for 20 nodes (20000 nodes/s)
depth = 2: 0 ms for 400 nodes (400000 nodes/s)
depth = 3: 1 ms for 8902 nodes (4451000 nodes/s)
depth = 4: 8 ms for 197281 nodes (21920000 nodes/s)
depth = 5: 182 ms for 4865609 nodes (26588000 nodes/s)
depth = 6: 4127 ms for 119060324 nodes (28842000 nodes/s)
depth = 7: 118382 ms for 3195901860 nodes (26996000 nodes/s)

Supported UCI commands:
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

UCI setoption options:
- threads: [spin] number of threads to be used during the search
- usehash: [check] enables or disables the use of the hashTable
- hash: [spin] size of the hashTable in MB
- uci_limitstrength: [check] enables or disables the limitation of the engine's strength
- UCI_Elo: [spin] engine's elo
- fixedDepth: [check] fixes the depth during a normal go cmd to the depth prescribed by the engine's elo
- clearHash: [button] clears the hashTable's entries

