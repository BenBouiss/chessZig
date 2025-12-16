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
