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

