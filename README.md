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
- fastBitscan: Use of the "intrinsics" file for bitscan and reverseBitscan
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
- [?] Remove the p_state.pieceBB[14] into 14 independant values with the correct names 
    - Still on the fence on this one
- [x] Convert evaluation to use centiPawn represention(use larger int instead of lower floats?) 
- [ ] Heuristic to add to evaluation
    - [x] King safety (use the one present in the texel coeffs see .zig file)
    - Add complexity

- [ ] Search optimization 
    - [ ] Late move reduction
        - in the move ordering search the "best" moves to deeper depth than the lower owns
        - heuristics for the depth decays dependant of the state of the game
    - [ ] Futility pruning ?
    - [ ] History ordering debug

Sources: 
- https://www.chessprogramming.org/
- https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator#comments-section
- https://github.com/abulmo/hqperft
- https://github.com/AndyGrant/Ethereal/tree/master for the texel paper

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

- depth = 1: 0 ms for 20 nodes (20000 nodes/s)
- depth = 2: 0 ms for 400 nodes (400000 nodes/s)
- depth = 3: 1 ms for 8902 nodes (4451000 nodes/s)
- depth = 4: 8 ms for 197281 nodes (21920000 nodes/s)
- depth = 5: 182 ms for 4865609 nodes (26588000 nodes/s)
- depth = 6: 4127 ms for 119060324 nodes (28842000 nodes/s)
- depth = 7: 118382 ms for 3195901860 nodes (26996000 nodes/s)

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
- UCI_Elo: [spin] engine's elo(not real elo only used to linear interp between depth 1(elo = 1000) and depth 6(elo = 3000))
- fixedDepth: [check] fixes the depth during a normal go cmd to the depth prescribed by the engine's elo
- clearHash: [button] clears the hashTable's entries
- useTexel: [check] enable the texel evaluation method
- heuristicWeightsPath: [string] path to the file containing the weights to be used


File structures:
A running theme here, a line will be ignored if it is malformed and/or doest correspond to the wanted format. Same behavior as the uci engine when in a similar position

##.info: Primarely used to configure matches between engines, everything is case-insensitive (should be atleast)
sections:
- engine sections [engine1], [engine2]
    - path, cmd = 'path="{s}";' path to the engine binary
    - name, cmd = 'name="{s}";' name to register the engine by, will be used when saving the logs of the match(es)
    - engine cmd, cmd = "{s}" the string will be sent as is to the engine, can be used to setoptions, enable debug or more...
        - Anything starting with '"' will we considered, it also is the fallback cases for cmd parsing(last possible option when picking the type) I think

- match section [match]:
    - nMatch, cmd = 'nMatch={d};' number of match to be played between the engines
    - playerSwitch, cmd = 'playerSwitch={s};' either 'true' or 'false', when enabled each match will be composed of 2 matches where the player will play both sides (engine1 vs engine2, engine2 vs engine1). Is usual to test if an engine is good as white and black
    - debugMode, cmd = 'debugMode={s};' either 'true' or 'false', is used to toggle more debug prints
    - useOpeningBook, cmd = 'useOpeningBook={s};' either 'true' or 'false', if an opening book is provided then each matches will be played starting from a drawn match entry from the opening book. This is useful to get multiple different matches to compare engine's strength, as currently this engine will produce the exact same match everytime when played against itself(heuristic function always the same for a given fen code) 
    - openingBookPath, cmd = 'openingBookPath={s};' path to the opening book to be used
    - saveLogs, cmd = 'saveLogs={s};' either 'true' or 'false' bool to enable the saving of internal logs and match logs
    - logsLocation, cmd = 'logsLocation={s};' directory to save the logs files, if not provided will use the default location the parent directory


##.winfo: Primarely used to pass weights to the engine throught the heuristicWeightsPath option,  
- {piece}ScoreArr, cmd = '{piece}ScoreArr = [{d}, {d}, ..., {d}];' where piece is a chess piece, the content here is an array of 64 float values separeted by ',' to be used in the evaluation function. If the number of elements isnt 64, the line will be ignored
- {piece}value, WIP way to set the individual piece heuristic values, primarely used in the piece counting phase of the evaluation function
- more to come as the evaluation gets more complex

Performance profiling:
Currently the way to test wether a feature accelerates chess operations is to launch a perft and profile the resulting ELF file with [samply]. An exemple of profiling can be found below:
```
 samply record ./zig-out/bin/chess
```
Samply has been a great tool to debug performance issues, especially the tricky ones (ie: magic table indexing see src/magic.zig getBishopMoves()).


