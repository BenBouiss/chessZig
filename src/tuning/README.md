This folder contains files used for the tuning of the engine's parameters. 

#Summary
The current idea is to:
    - Optimize the "single" weights using the "tournament" + mh method. See mh section for further information.
    - Take a good guess from the first step and perform a texel optimization to tune the PSQT weights.
The tournament is set with the following time format: (time = 60s, inc = 0.1s). The match is one round where the player switch side after a chess game ends, effectively a round is 2 chess matches. See the engines/engine_tourney.info file which is the base file currently used.

#Metaheuristic parameter optimization

As computationnal power is currently an issue, tuning 64 * 6 * 2 PSQT weights and performing the required chess matches is too expensive.


##Problem's dimension vs population size
As most MH algo performs random walk either in the direction of the current best(s) (exploitation) or random direction (exploration). 
The more dimension are added to the problem the less likely a random walk will produce a competitive set of weights given a constant sized population. 
In this case it is generaly advised to increase the population size, however doing so increases the number of calls to the evaluation function that is intended to be optimized.
In our problem the evaluation function is very expensive requiring multiple matches per configuration per currently known baseline. 
This motivated the removal of the PSQT weights from the tuned parameters. For tuning using MH a currently known good set of PSQT weights will be fixed and the engine produced by the MH will use these.

##Algo choice
There is an abundance of MH algo out there mainly motivated by the good results of state of the art algo (GWO, PSO, ACO, ...). These algorithms demonstrated good performance in various fields of study where performing "raw" gradient descents is impossible or non feasible compution wise. //Hence the name gradient free optimization algorithms
GWO was picked as the default algo in this project but more may come soon(tm).

#Texel
...

#Engine's modification
To facilitate this process, the engine's various weights were made modifiable trought the use of the setoption name heuristicWeightsPath value <path>. This is done with the .winfo "nomenclature" in mind which can be found in the first README.md of the repo.

The currently modifiable fields:
-PSQT
    -pawn...
    -bishop...
    -knight...
    -rook...
    -queen...
    -king...

-singles
    -isolatedPawn...
    -mobility...
    -stackedPawn...
    -passedPawn...
    -safetyKnight...
    -safetyBishop...
    -safetyRook...
    -safetyQueen...
    -structureProtection...

In singles, the value is extracted after the "="
Note: All fields are case incensitive, the "..." indicates that the rest is ignored.
Note2: The differentation between singles and PSQT is done via the PSQT value format which is field_name: \[val1, val2, ..., valn\];

Since the engine uses a tapered evaluation, all of these parameter can be specified with "\_MG" or "\_EG" inside the field's name. If none of "\_MG" or "\_EG" is found, the value is set for both the MG(mid game), EG(end game) slots.

## Misc / prototype section
Idea: 
- Set the time format to low and searchDepth / engineElo to low, makes the iter faster, but result still good?
    - Need to test if good heuristic found on shallow search == good on deep search
- Generate N engines / or N set of random params (possibly less compute intensive) around the current best 
- Execute a tournament, takes the top n best, perform crossOver / MH optim step 
- Execute previous step until good enough 

feature:
    - Checkpoint system:
        - Every round(?)
        - Save the state of the tournament object to a .pkl file
        - Load possibility to continue a previously started tuning
    - ?
Refactor:
    - Make MH algo with a maximisation objective where the scoring func launches the tourney in single/multiThreaded
        -  

Callback saving section:
Save the evolution of the population from one iter to the next
save mh params for loading and tuning continuation
2 possibilities:
    - save population + mh params 
    - only save population, let the mh do its thing then run
        - could possibly do a set_iter to let the mh correctly set its internals and such

save chess population fmt (example): 
    pawnScoreArr, (float, 64)
    bishopScoreArr, (float, 64)
    knightScoreArr, (float, 64)
    rookScoreArr , (float, 64)
    queenScoreArr, (float, 64)
    kingScoreArr, (float, 64)

with this info we can convert MH population => chess population
for each iter save the MH population fmt (example):
    positions(float,  64 * 6)
    scores(float)
    uid(float)

when loading in order to relaunch optim only the current population is actually needed not the complete history, plus the MH params or smthin see below
file format: yaml for better python integration probably

save format?
    - date: {s}; // not necessary
    - iter: {d};
    - maxiter: {d};
    - popsize: {d};
    - bounds: [[{f}, {f}], ..., [{f}, {f}]];
    - steps: [[{f}], ..., [{f}]];
    - fmtCode: {s}; // to be used to differentiate in the MH population => chess population
        - ex: f64_f64_f64_f64_f64_f64
    - populationHistory: [[indiv1, ..., indivN](0) .... [indiv1, ..., indivN](iter)];
        - Indiv fmt: [position: [{f}, {f}, ..., {f}], uid: {d}, score: {f}]
        - Same layout as in template.py, name of the keys not included
            - position
            - uid
            - score
    - ???

# Texel tuning
source: https://github.com/AndyGrant/Ethereal/blob/master/Tuning.pdf
plan is to use a pre computed csv files containing all the relevant coefficient computed from a given "book" file 
outcomes: 0: black win, 0.5: draw, 1: white win
csv content:
    - Coeff_0_w, Coeff_1_b, ...., Coeff_n_w, Coeff_n_b, Phase, Outcome
    

#MH part:

round idea: 
    - Init N random weight params and insert the current baseline or "simple config" one with its params frozen.
    - Start the optim with 1 match per "encounter" and playerSwith = true
    - 2 path
        - Either engines play amongst themselves + baseline. Plus possibility to make a new baseline if an engine consistently beats the baseline.
        - Only fight against baseline then replace with the first engine capable of going "positive" against it.
    - useOpeningBook should be true as nMatch wouldnt matter otherwise  
    - nMatch increasing should introduce layers to the heuristics and thus making better optim steps (ideally)
    - useGreedy
        - For path (1) useGreedy = false as a "good" score early in the optim is not representative of a good engine. It can indicate that the others are abysmal

        - For path (2) if all matches are played against a "good" baseline, useGreedy can be either/or. 
            - useGreedy = true, nMatch increasing and allowing the scoring to keep increasing (ie: more potential draws/wins) could be a way to refresh outdated scoring 
            - useGreedy = false, no refreshing needed as each step is a refresh. potential bad optim step

