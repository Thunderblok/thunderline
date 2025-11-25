#!/usr/bin/env python3
"""
ONNX Model Inference Service

Standalone inference service for CerebrosNotGPT ONNX models.
Provides text generation with various sampling strategies.

Usage:
    # Interactive mode
    python onnx_inference.py model.onnx tokenizer/ --interactive
    
    # Single prompt
    python onnx_inference.py model.onnx tokenizer/ --prompt "In the beginning"
    
    # With sampling parameters
    python onnx_inference.py model.onnx tokenizer/ --prompt "Hello" \
        --temperature 0.7 --top-k 50 --top-p 0.95

Requirements:
    pip install onnxruntime numpy transformers
"""

import argparse
import os
import sys
import json
from typing import List, Optional, Dict, Any
from dataclasses import dataclass

import numpy as np


@dataclass
class GenerationConfig:
    """Configuration for text generation."""
    max_new_tokens: int = 50
    temperature: float = 0.7
    top_k: int = 50
    top_p: float = 0.95
    repetition_penalty: float = 1.2
    presence_penalty: float = 1.3
    frequency_penalty: float = 1.3
    do_sample: bool = True


class CerebrosONNXGenerator:
    """
    ONNX-based text generator for CerebrosNotGPT models.
    
    Provides text generation with multiple sampling strategies:
    - Greedy decoding
    - Temperature scaling
    - Top-k sampling
    - Top-p (nucleus) sampling
    - Repetition/presence/frequency penalties
    """
    
    def __init__(
        self,
        model_path: str,
        tokenizer_path: str,
        max_seq_length: int = 40,
        device: str = "cpu"
    ):
        """
        Initialize the generator.
        
        Args:
            model_path: Path to ONNX model file
            tokenizer_path: Path to tokenizer directory
            max_seq_length: Maximum sequence length (must match training)
            device: Execution provider ("cpu" or "cuda")
        """
        import onnxruntime as ort
        from transformers import AutoTokenizer
        
        self.max_seq_length = max_seq_length
        
        # Load ONNX model
        print(f"📂 Loading ONNX model: {model_path}")
        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"] if device == "cuda" else ["CPUExecutionProvider"]
        self.session = ort.InferenceSession(model_path, providers=providers)
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name
        print(f"   ✓ Model loaded (input: {self.input_name}, output: {self.output_name})")
        
        # Load tokenizer
        print(f"📂 Loading tokenizer: {tokenizer_path}")
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
        self.vocab_size = self.tokenizer.vocab_size
        self.pad_token_id = self.tokenizer.pad_token_id or self.tokenizer.eos_token_id
        print(f"   ✓ Tokenizer loaded (vocab_size: {self.vocab_size})")
    
    def encode(self, text: str) -> List[int]:
        """Encode text to token IDs."""
        return self.tokenizer.encode(text, add_special_tokens=False)
    
    def decode(self, token_ids: List[int]) -> str:
        """Decode token IDs to text."""
        return self.tokenizer.decode(token_ids, skip_special_tokens=True)
    
    def pad_tokens(self, token_ids: List[int]) -> np.ndarray:
        """Pad token sequence to max_seq_length."""
        if len(token_ids) >= self.max_seq_length:
            # Truncate from the left (keep most recent tokens)
            token_ids = token_ids[-self.max_seq_length:]
        else:
            # Pad on the right
            padding = [self.pad_token_id] * (self.max_seq_length - len(token_ids))
            token_ids = token_ids + padding
        
        return np.array([token_ids], dtype=np.int32)
    
    def get_next_token_logits(self, token_ids: List[int]) -> np.ndarray:
        """Run inference and get logits for next token."""
        input_array = self.pad_tokens(token_ids)
        outputs = self.session.run([self.output_name], {self.input_name: input_array})
        return outputs[0][0]  # Shape: (vocab_size,)
    
    def apply_repetition_penalty(
        self,
        logits: np.ndarray,
        token_ids: List[int],
        penalty: float
    ) -> np.ndarray:
        """Apply repetition penalty to discourage repeated tokens."""
        if penalty == 1.0:
            return logits
        
        for token_id in set(token_ids):
            if token_id < len(logits):
                if logits[token_id] > 0:
                    logits[token_id] /= penalty
                else:
                    logits[token_id] *= penalty
        
        return logits
    
    def apply_presence_penalty(
        self,
        logits: np.ndarray,
        token_ids: List[int],
        penalty: float
    ) -> np.ndarray:
        """Apply presence penalty (flat penalty for any used token)."""
        if penalty == 0.0:
            return logits
        
        for token_id in set(token_ids):
            if token_id < len(logits):
                logits[token_id] -= penalty
        
        return logits
    
    def apply_frequency_penalty(
        self,
        logits: np.ndarray,
        token_ids: List[int],
        penalty: float
    ) -> np.ndarray:
        """Apply frequency penalty (scaled by occurrence count)."""
        if penalty == 0.0:
            return logits
        
        from collections import Counter
        token_counts = Counter(token_ids)
        
        for token_id, count in token_counts.items():
            if token_id < len(logits):
                logits[token_id] -= penalty * count
        
        return logits
    
    def sample_token(
        self,
        logits: np.ndarray,
        config: GenerationConfig
    ) -> int:
        """Sample next token from logits using configured strategy."""
        
        # Apply temperature
        if config.temperature != 1.0:
            logits = logits / config.temperature
        
        # Convert to probabilities
        probs = self._softmax(logits)
        
        if not config.do_sample:
            # Greedy decoding
            return int(np.argmax(probs))
        
        # Apply top-k filtering
        if config.top_k > 0:
            top_k_indices = np.argsort(probs)[-config.top_k:]
            mask = np.zeros_like(probs)
            mask[top_k_indices] = 1
            probs = probs * mask
        
        # Apply top-p (nucleus) filtering
        if config.top_p < 1.0:
            sorted_indices = np.argsort(probs)[::-1]
            sorted_probs = probs[sorted_indices]
            cumsum = np.cumsum(sorted_probs)
            cutoff_idx = np.searchsorted(cumsum, config.top_p) + 1
            
            mask = np.zeros_like(probs)
            mask[sorted_indices[:cutoff_idx]] = 1
            probs = probs * mask
        
        # Renormalize
        probs_sum = np.sum(probs)
        if probs_sum > 0:
            probs = probs / probs_sum
        else:
            # Fallback to uniform
            probs = np.ones_like(probs) / len(probs)
        
        # Sample
        return int(np.random.choice(len(probs), p=probs))
    
    def _softmax(self, x: np.ndarray) -> np.ndarray:
        """Compute softmax probabilities."""
        exp_x = np.exp(x - np.max(x))
        return exp_x / np.sum(exp_x)
    
    def generate(
        self,
        prompt: str,
        config: Optional[GenerationConfig] = None
    ) -> str:
        """
        Generate text continuation for a prompt.
        
        Args:
            prompt: Input text to continue
            config: Generation configuration
        
        Returns:
            Generated text (prompt + continuation)
        """
        if config is None:
            config = GenerationConfig()
        
        # Encode prompt
        token_ids = self.encode(prompt)
        original_length = len(token_ids)
        
        # Generate tokens
        for _ in range(config.max_new_tokens):
            # Get logits for next token
            logits = self.get_next_token_logits(token_ids)
            
            # Apply penalties
            if config.repetition_penalty != 1.0:
                logits = self.apply_repetition_penalty(
                    logits, token_ids, config.repetition_penalty
                )
            if config.presence_penalty != 0.0:
                logits = self.apply_presence_penalty(
                    logits, token_ids, config.presence_penalty
                )
            if config.frequency_penalty != 0.0:
                logits = self.apply_frequency_penalty(
                    logits, token_ids, config.frequency_penalty
                )
            
            # Sample next token
            next_token = self.sample_token(logits, config)
            
            # Check for end of sequence
            if next_token == self.pad_token_id:
                break
            
            token_ids.append(next_token)
            
            # Check max length
            if len(token_ids) >= self.max_seq_length:
                break
        
        # Decode and return
        return self.decode(token_ids)
    
    def generate_greedy(self, prompt: str, max_new_tokens: int = 50) -> str:
        """Generate text using greedy decoding."""
        config = GenerationConfig(
            max_new_tokens=max_new_tokens,
            do_sample=False
        )
        return self.generate(prompt, config)
    
    def generate_beam(
        self,
        prompt: str,
        max_new_tokens: int = 50,
        temperature: float = 0.7,
        top_k: int = 50,
        top_p: float = 0.95
    ) -> str:
        """Generate text using beam-style sampling."""
        config = GenerationConfig(
            max_new_tokens=max_new_tokens,
            temperature=temperature,
            top_k=top_k,
            top_p=top_p,
            do_sample=True
        )
        return self.generate(prompt, config)


def interactive_mode(generator: CerebrosONNXGenerator, config: GenerationConfig):
    """Run interactive text generation session."""
    print("\n" + "="*60)
    print("🤖 Cerebros ONNX Interactive Mode")
    print("="*60)
    print("Enter prompts to generate text. Type 'quit' to exit.")
    print("Type 'config' to show/modify generation settings.")
    print("="*60 + "\n")
    
    while True:
        try:
            prompt = input("📝 Prompt: ").strip()
            
            if not prompt:
                continue
            
            if prompt.lower() == 'quit':
                print("👋 Goodbye!")
                break
            
            if prompt.lower() == 'config':
                print(f"\nCurrent configuration:")
                for field, value in vars(config).items():
                    print(f"  {field}: {value}")
                print()
                continue
            
            # Generate
            print("🔄 Generating...")
            result = generator.generate(prompt, config)
            print(f"📖 Output: {result}\n")
            
        except KeyboardInterrupt:
            print("\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"❌ Error: {e}\n")


def main():
    parser = argparse.ArgumentParser(
        description="ONNX inference for CerebrosNotGPT models",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Interactive mode
    python onnx_inference.py model.onnx tokenizer/ --interactive
    
    # Single prompt
    python onnx_inference.py model.onnx tokenizer/ --prompt "In the beginning"
    
    # With custom sampling
    python onnx_inference.py model.onnx tokenizer/ --prompt "Hello" \\
        --temperature 0.8 --top-k 40 --max-tokens 100
"""
    )
    
    parser.add_argument("model", help="Path to ONNX model file")
    parser.add_argument("tokenizer", help="Path to tokenizer directory")
    
    parser.add_argument(
        "--prompt",
        help="Input prompt for generation"
    )
    
    parser.add_argument(
        "--interactive", "-i",
        action="store_true",
        help="Run in interactive mode"
    )
    
    parser.add_argument(
        "--max-seq-length",
        type=int,
        default=40,
        help="Maximum sequence length. Default: 40"
    )
    
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=50,
        help="Maximum new tokens to generate. Default: 50"
    )
    
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.7,
        help="Temperature for sampling. Default: 0.7"
    )
    
    parser.add_argument(
        "--top-k",
        type=int,
        default=50,
        help="Top-k sampling parameter. Default: 50"
    )
    
    parser.add_argument(
        "--top-p",
        type=float,
        default=0.95,
        help="Top-p (nucleus) sampling parameter. Default: 0.95"
    )
    
    parser.add_argument(
        "--repetition-penalty",
        type=float,
        default=1.2,
        help="Repetition penalty. Default: 1.2"
    )
    
    parser.add_argument(
        "--greedy",
        action="store_true",
        help="Use greedy decoding instead of sampling"
    )
    
    parser.add_argument(
        "--device",
        choices=["cpu", "cuda"],
        default="cpu",
        help="Execution device. Default: cpu"
    )
    
    args = parser.parse_args()
    
    # Validate inputs
    if not os.path.isfile(args.model):
        print(f"❌ Model not found: {args.model}")
        sys.exit(1)
    
    if not os.path.isdir(args.tokenizer):
        print(f"❌ Tokenizer directory not found: {args.tokenizer}")
        sys.exit(1)
    
    if not args.interactive and not args.prompt:
        print("❌ Either --prompt or --interactive is required")
        sys.exit(1)
    
    # Initialize generator
    generator = CerebrosONNXGenerator(
        model_path=args.model,
        tokenizer_path=args.tokenizer,
        max_seq_length=args.max_seq_length,
        device=args.device
    )
    
    # Create config
    config = GenerationConfig(
        max_new_tokens=args.max_tokens,
        temperature=args.temperature,
        top_k=args.top_k,
        top_p=args.top_p,
        repetition_penalty=args.repetition_penalty,
        do_sample=not args.greedy
    )
    
    if args.interactive:
        interactive_mode(generator, config)
    else:
        result = generator.generate(args.prompt, config)
        print(f"\n📖 Generated text:\n{result}")


if __name__ == "__main__":
    main()
