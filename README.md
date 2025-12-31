Uci complient chess engine project to try out the zig programming language. 


Multiple files exist in the build/ directory due to a bug with the zig build command on wsl. The current work around is to set the env variable ZIG_LOCAL_CACHE_DIR to somewhere in the linux filesystem part and the the windows part.

Installation:
    
    - make './build/build.sh'
        - run './zig-out/bin/Chess'
    - make and run './build/build.sh && ./zig-out/bin/Chess'



Speed up move gen by any means necessary(mostly through compile time(?))

Tasklist:
    - Remove the p_state.pieceBB[14] into 14 independant values with the correct names 

    - Witch-hunt if branches (looking at you isPiecePinned)

        - Each method/fn testing for turn should be comptimed away(?)

Sources: 
    - https://www.chessprogramming.org/
    - https://www.codeproject.com/articles/Worlds-Fastest-Bitboard-Chess-Movegenerator#comments-section
    - https://github.com/abulmo/hqperft

Values: 

|Nodes|Capture|Doublepush|Enpassant|castling|promotions|
|=====|=======|=========|========|==========|
Move generation (depth = 1): 0 ms for 20 nodes (20000 nodes/s)
|20|0|8|0|0|0|

Move generation (depth = 2): 0 ms for 400 nodes (400000 nodes/s)
|400|0|160|0|0|0|

Move generation (depth = 3): 1 ms for 8902 nodes (4451000 nodes/s)
|8902|34|2800|0|0|0|

Move generation (depth = 4): 8 ms for 197281 nodes (21920000 nodes/s)
|197281|1576|61730|0|0|0|

Move generation (depth = 5): 182 ms for 4865609 nodes (26588000 nodes/s)
|4865609|82719|1211076|258|0|0|

Move generation (depth = 6): 4127 ms for 119060324 nodes (28842000 nodes/s)
|119060324|2812008|29374680|5248|0|0|

Move generation (depth = 7): 118382 ms for 3195901860 nodes (26996000 nodes/s)
|3195901860|108329926|644115108|319617|883453|0|
