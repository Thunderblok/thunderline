"""
Cerebros Genetic Algorithm - Simplified implementation for NAS

This is a lightweight GA implementation for neural architecture search.
Based on the pattern from https://github.com/david-thrower/cerebros-core-algorithm-alpha

For production, replace this with the full Cerebros implementation.
"""

import numpy as np
import logging
from typing import List, Tuple, Dict, Any, Callable
from dataclasses import dataclass
from datetime import datetime

logger = logging.getLogger(__name__)


@dataclass
class Individual:
    """
    Represents a neural network architecture in the GA population
    """
    layers: List[int]  # Hidden layer sizes
    activation: str
    optimizer: str
    learning_rate: float
    dropout_rate: float
    batch_size: int
    fitness: float = 0.0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "layers": self.layers,
            "activation": self.activation,
            "optimizer": self.optimizer,
            "learning_rate": self.learning_rate,
            "dropout_rate": self.dropout_rate,
            "batch_size": self.batch_size,
            "fitness": self.fitness
        }


class CerebrosGA:
    """
    Genetic Algorithm for Neural Architecture Search
    """
    
    def __init__(
        self,
        population_size: int = 20,
        mutation_rate: float = 0.1,
        crossover_rate: float = 0.7,
        elite_size: int = 2,
        tau: float = 1.0
    ):
        self.population_size = population_size
        self.mutation_rate = mutation_rate
        self.crossover_rate = crossover_rate
        self.elite_size = elite_size
        self.tau = tau  # Temperature for selection
        
        # Search space configuration
        self.layer_sizes = [16, 32, 64, 128, 256, 512]
        self.activations = ["relu", "tanh", "sigmoid", "elu"]
        self.optimizers = ["adam", "sgd", "rmsprop"]
        self.learning_rates = [0.0001, 0.001, 0.01]
        self.dropout_rates = [0.0, 0.1, 0.2, 0.3, 0.5]
        self.batch_sizes = [16, 32, 64, 128]
        
    def initialize_population(self) -> List[Individual]:
        """Create random initial population"""
        population = []
        for _ in range(self.population_size):
            # Random number of layers (1-4 hidden layers)
            num_layers = np.random.randint(1, 5)
            layers = [np.random.choice(self.layer_sizes) for _ in range(num_layers)]
            
            individual = Individual(
                layers=layers,
                activation=np.random.choice(self.activations),
                optimizer=np.random.choice(self.optimizers),
                learning_rate=float(np.random.choice(self.learning_rates)),
                dropout_rate=float(np.random.choice(self.dropout_rates)),
                batch_size=int(np.random.choice(self.batch_sizes))
            )
            population.append(individual)
        
        return population
    
    def evaluate_fitness(
        self,
        individual: Individual,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_test: np.ndarray,
        y_test: np.ndarray
    ) -> float:
        """
        Evaluate individual's fitness by training a simple model
        
        For production, this would build and train a full neural network.
        For now, we use a simplified heuristic based on architecture properties.
        """
        # Simplified fitness based on architecture characteristics
        # In production, this would actually train the model
        
        # Base fitness from architecture complexity
        total_params = sum(individual.layers)
        complexity_score = 1.0 - (abs(total_params - 256) / 512.0)  # Prefer ~256 total params
        
        # Bonus for good learning rate
        lr_score = 1.0 if 0.0001 <= individual.learning_rate <= 0.01 else 0.5
        
        # Bonus for reasonable dropout
        dropout_score = 1.0 if 0.1 <= individual.dropout_rate <= 0.3 else 0.7
        
        # Random noise to simulate training variance
        noise = np.random.uniform(0.8, 1.2)
        
        fitness = (complexity_score * 0.5 + lr_score * 0.3 + dropout_score * 0.2) * noise
        fitness = max(0.0, min(1.0, fitness))  # Clamp to [0, 1]
        
        return float(fitness)
    
    def tournament_selection(self, population: List[Individual], k: int = 3) -> Individual:
        """Select individual using tournament selection with temperature"""
        # Select k random individuals
        tournament = np.random.choice(population, size=k, replace=False)
        
        # Apply softmax with temperature (tau)
        fitnesses = np.array([ind.fitness for ind in tournament])
        exp_fitness = np.exp(fitnesses / self.tau)
        probabilities = exp_fitness / exp_fitness.sum()
        
        # Select based on probabilities
        selected_idx = np.random.choice(len(tournament), p=probabilities)
        return tournament[selected_idx]
    
    def crossover(self, parent1: Individual, parent2: Individual) -> Tuple[Individual, Individual]:
        """Single-point crossover between two parents"""
        if np.random.rand() > self.crossover_rate:
            return parent1, parent2
        
        # Crossover layers
        if len(parent1.layers) > 1 and len(parent2.layers) > 1:
            point = min(len(parent1.layers), len(parent2.layers)) // 2
            child1_layers = parent1.layers[:point] + parent2.layers[point:]
            child2_layers = parent2.layers[:point] + parent1.layers[point:]
        else:
            child1_layers = parent1.layers.copy()
            child2_layers = parent2.layers.copy()
        
        # Inherit other parameters randomly
        child1 = Individual(
            layers=child1_layers,
            activation=np.random.choice([parent1.activation, parent2.activation]),
            optimizer=np.random.choice([parent1.optimizer, parent2.optimizer]),
            learning_rate=float(np.random.choice([parent1.learning_rate, parent2.learning_rate])),
            dropout_rate=float(np.random.choice([parent1.dropout_rate, parent2.dropout_rate])),
            batch_size=int(np.random.choice([parent1.batch_size, parent2.batch_size]))
        )
        
        child2 = Individual(
            layers=child2_layers,
            activation=np.random.choice([parent1.activation, parent2.activation]),
            optimizer=np.random.choice([parent1.optimizer, parent2.optimizer]),
            learning_rate=float(np.random.choice([parent1.learning_rate, parent2.learning_rate])),
            dropout_rate=float(np.random.choice([parent1.dropout_rate, parent2.dropout_rate])),
            batch_size=int(np.random.choice([parent1.batch_size, parent2.batch_size]))
        )
        
        return child1, child2
    
    def mutate(self, individual: Individual) -> Individual:
        """Mutate individual's parameters"""
        if np.random.rand() > self.mutation_rate:
            return individual
        
        # Randomly mutate one aspect
        mutation_type = np.random.randint(0, 6)
        
        if mutation_type == 0 and len(individual.layers) > 0:
            # Mutate layer size
            idx = np.random.randint(0, len(individual.layers))
            individual.layers[idx] = np.random.choice(self.layer_sizes)
        elif mutation_type == 1:
            # Mutate activation
            individual.activation = np.random.choice(self.activations)
        elif mutation_type == 2:
            # Mutate optimizer
            individual.optimizer = np.random.choice(self.optimizers)
        elif mutation_type == 3:
            # Mutate learning rate
            individual.learning_rate = float(np.random.choice(self.learning_rates))
        elif mutation_type == 4:
            # Mutate dropout
            individual.dropout_rate = float(np.random.choice(self.dropout_rates))
        elif mutation_type == 5:
            # Mutate batch size
            individual.batch_size = int(np.random.choice(self.batch_sizes))
        
        return individual
    
    def evolve(
        self,
        X_train: np.ndarray,
        y_train: np.ndarray,
        X_test: np.ndarray,
        y_test: np.ndarray,
        max_generations: int = 10
    ) -> Tuple[Individual, float, List[Dict]]:
        """
        Run the genetic algorithm
        
        Returns:
            best_individual: Best architecture found
            best_fitness: Best fitness achieved
            population_history: History of population evolution
        """
        logger.info(f"Starting GA evolution for {max_generations} generations")
        
        # Initialize population
        population = self.initialize_population()
        
        # Evaluate initial population
        for individual in population:
            individual.fitness = self.evaluate_fitness(individual, X_train, y_train, X_test, y_test)
        
        population_history = []
        best_individual = None
        best_fitness = -float('inf')
        
        for generation in range(max_generations):
            # Sort by fitness
            population.sort(key=lambda x: x.fitness, reverse=True)
            
            # Track best
            if population[0].fitness > best_fitness:
                best_fitness = population[0].fitness
                best_individual = population[0]
            
            # Record generation statistics
            fitnesses = [ind.fitness for ind in population]
            population_history.append({
                "generation": generation,
                "best_fitness": float(max(fitnesses)),
                "mean_fitness": float(np.mean(fitnesses)),
                "std_fitness": float(np.std(fitnesses)),
                "population_size": len(population)
            })
            
            logger.info(
                f"Generation {generation}: "
                f"best={max(fitnesses):.4f}, "
                f"mean={np.mean(fitnesses):.4f}"
            )
            
            # Create next generation
            new_population = []
            
            # Elitism: keep best individuals
            new_population.extend(population[:self.elite_size])
            
            # Generate offspring
            while len(new_population) < self.population_size:
                # Select parents
                parent1 = self.tournament_selection(population)
                parent2 = self.tournament_selection(population)
                
                # Crossover
                child1, child2 = self.crossover(parent1, parent2)
                
                # Mutate
                child1 = self.mutate(child1)
                child2 = self.mutate(child2)
                
                # Evaluate fitness
                child1.fitness = self.evaluate_fitness(child1, X_train, y_train, X_test, y_test)
                child2.fitness = self.evaluate_fitness(child2, X_train, y_train, X_test, y_test)
                
                new_population.extend([child1, child2])
            
            # Trim to population size
            population = new_population[:self.population_size]
        
        logger.info(f"GA evolution complete. Best fitness: {best_fitness:.4f}")
        
        return best_individual, best_fitness, population_history


def cerebros_core_ga(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_test: np.ndarray,
    y_test: np.ndarray,
    population_size: int = 20,
    mutation_rate: float = 0.1,
    crossover_rate: float = 0.7,
    elite_size: int = 2,
    max_generations: int = 10,
    tau: float = 1.0,
    **kwargs
) -> Tuple[Individual, float, List[Dict]]:
    """
    Main entry point for Cerebros GA
    
    This matches the expected interface from cerebros-core-algorithm-alpha.
    """
    ga = CerebrosGA(
        population_size=population_size,
        mutation_rate=mutation_rate,
        crossover_rate=crossover_rate,
        elite_size=elite_size,
        tau=tau
    )
    
    return ga.evolve(X_train, y_train, X_test, y_test, max_generations)


# Test the implementation
if __name__ == "__main__":
    print("Testing Cerebros GA")
    print("=" * 80)
    
    # Generate dummy data
    X_train = np.random.rand(100, 20)
    y_train = np.random.randint(0, 2, 100)
    X_test = np.random.rand(30, 20)
    y_test = np.random.randint(0, 2, 30)
    
    # Run GA
    best, fitness, history = cerebros_core_ga(
        X_train, y_train, X_test, y_test,
        population_size=10,
        max_generations=5,
        mutation_rate=0.15,
        crossover_rate=0.7,
        elite_size=2,
        tau=1.0
    )
    
    print("\n" + "=" * 80)
    print("Best Architecture Found:")
    print("=" * 80)
    print(f"Layers: {best.layers}")
    print(f"Activation: {best.activation}")
    print(f"Optimizer: {best.optimizer}")
    print(f"Learning Rate: {best.learning_rate}")
    print(f"Dropout: {best.dropout_rate}")
    print(f"Batch Size: {best.batch_size}")
    print(f"Fitness: {best.fitness:.4f}")
    
    print("\n" + "=" * 80)
    print("Evolution History:")
    print("=" * 80)
    for gen in history:
        print(f"Gen {gen['generation']}: best={gen['best_fitness']:.4f}, mean={gen['mean_fitness']:.4f}")
    
    print("\n✅ Test complete")
