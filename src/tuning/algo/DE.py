import algo.template as template

class DE(template.templateSelectionAlgo):
    def __init__(self, **parentKwargs):
        super().__init__(**parentKwargs)

        self.CR = 0.1
        self.F = 2
        raise NotImplementedError

    def compute_crossover(self):
        pass

    def step(self):
        assert self.objective is not None
        scores = self.objective.evaluate(self.population)
        self.population.sort(key = lambda x: x.score, reverse = True)
        self.best_indiv_list.append(self.population[0])

