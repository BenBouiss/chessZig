This folder will contain files around the subject of tuning the chess engine's parameters.

Objective:
- Isolate a number of engine parameters to be tuned
- Implement a "tournament" type of script
- Implement optimization algorithms
    - Simulated annealing
    - Meta heuristic!!!!
    - Other?


Implication:
- Move the array score somewhere easily modifiable
- Set up option setoption to modify parameters
    - pawnScoreArr ...

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
    
