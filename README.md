Chess engine project to learn the zig programming language.

Installation:

    - make './build/build.sh'
        - run './zig-out/bin/Chess'
    - make and run './build/build.sh && ./zig-out/bin/Chess'



Speed up move gen by any means necessary(mostly through compile time(?))

Tasklist:
    [ ] Remove the p_state.pieceBB[14] into 14 independant values with the correct names 
    [ ] Witch-hunt if branches (looking at you isPiecePinned)
        [ ] Each method/fn testing for turn should be comptimed away(?)

