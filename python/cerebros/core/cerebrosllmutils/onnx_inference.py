"""
ONNX Inference for Cerebros Models

This module provides text generation using exported ONNX models,
matching the functionality of CerebrosNotGPT.generate() but using
ONNX Runtime for cross-platform deployment.

Usage:
    from cerebrosllmutils.onnx_inference import OnnxGenerator
    
    # Load model and tokenizer
    generator = OnnxGenerator("model.onnx", "tokenizer/")
    
    # Generate text
    result = generator.generate("In the beginning", max_new_tokens=50)
    print(result)
    
    # With sampling options
    result = generator.generate(
        "Hello world",
        max_new_tokens=100,
        temperature=0.7,
        top_k=50,
        top_p=0.95
    )

Requirements:
    pip install onnxruntime numpy transformers
"""

from dataclasses import dataclass
from typing import List, Optional, Dict, Any
from collections import Counter
import numpy as np


@dataclass
class GenerationConfig:
    """Configuration for text generation."""
    max_new_tokens: int = 50
    temperature: float = 0.7
    top_k: int = 50
    top_p: float = 0.95
    repetition_penalty: float = 1.0
    presence_penalty: float = 0.0
    frequency_penalty: float = 0.0
    do_sample: bool = True


class OnnxGenerator:
    """
    ONNX-based text generator compatible with CerebrosNotGPT API.
    
    This class provides the same generation interface as CerebrosNotGPT
    but uses ONNX Runtime for inference, enabling deployment without
    TensorFlow dependencies.
    """
    
    def __init__(
        self,
        model_path: str,
        tokenizer_path: str,
        max_seq_length: int = 40,
        device: str = "cpu"
    ):
        """
        Initialize the ONNX generator.
        
        Args:
            model_path: Path to ONNX model file
            tokenizer_path: Path to HuggingFace tokenizer directory
            max_seq_length: Maximum sequence length (must match training)
            device: "cpu" or "cuda"
        """
        import onnxruntime as ort
        from transformers import AutoTokenizer
        
        self.max_seq_length = max_seq_length
        
        # Load ONNX model
        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"] if device == "cuda" else ["CPUExecutionProvider"]
        self.session = ort.InferenceSession(model_path, providers=providers)
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name
        
        # Load tokenizer
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
        self.vocab_size = len(self.tokenizer)
        self.padding_token = self.tokenizer.pad_token_id or self.tokenizer.eos_token_id
    
    def generate(
        self,
        token_ids: Optional[List[int]] = None,
        text: Optional[str] = None,
        do_sample: bool = True,
        max_new_tokens: int = 50,
        temperature: float = 0.7,
        top_k: int = 50,
        top_p: float = 0.95,
        repetition_penalty: float = None,
        presence_penalty: float = None,
        frequency_penalty: float = None
    ) -> List[int]:
        """
        Generate text autoregressively - API compatible with CerebrosNotGPT.generate().
        
        Args:
            token_ids: Input token IDs (alternative to text)
            text: Input text (alternative to token_ids)
            do_sample: Use sampling (True) or greedy decoding (False)
            max_new_tokens: Maximum new tokens to generate
            temperature: Sampling temperature
            top_k: Top-k sampling parameter
            top_p: Top-p (nucleus) sampling parameter
            repetition_penalty: Penalty for repeated tokens (legacy)
            presence_penalty: Flat penalty for used tokens
            frequency_penalty: Penalty scaled by token frequency
        
        Returns:
            List of token IDs (input + generated)
        """
        # Get token_ids from text if needed
        if token_ids is None:
            if text is None:
                raise ValueError("Either token_ids or text must be provided")
            token_ids = self.tokenizer.encode(text, add_special_tokens=False)
        
        # Ensure token_ids is a list
        if not isinstance(token_ids, list):
            token_ids = list(token_ids)
        
        # Limit max_new_tokens
        max_new_tokens = min(max_new_tokens, self.max_seq_length - len(token_ids))
        
        current_tokens = token_ids.copy()
        generated_tokens = []
        
        for _ in range(max_new_tokens):
            # Pad or truncate to max_seq_length
            if len(current_tokens) > self.max_seq_length:
                input_tokens = current_tokens[-self.max_seq_length:]
            else:
                padding_needed = self.max_seq_length - len(current_tokens)
                input_tokens = current_tokens + [self.padding_token] * padding_needed
            
            # Run inference
            input_array = np.array([input_tokens], dtype=np.int32)
            probs = self.session.run([self.output_name], {self.input_name: input_array})[0][0]
            
            # Convert to logits for penalty application
            logits = np.log(probs + 1e-10)
            
            if do_sample:
                # Apply penalties
                if frequency_penalty or presence_penalty:
                    token_counts = Counter(current_tokens)
                    for token_id, count in token_counts.items():
                        if token_id < len(logits):
                            penalty = 0.0
                            if presence_penalty:
                                penalty += presence_penalty
                            if frequency_penalty:
                                penalty += frequency_penalty * count
                            logits[token_id] -= penalty
                
                if repetition_penalty and repetition_penalty != 1.0:
                    for token_id in set(current_tokens):
                        if token_id < len(logits):
                            logits[token_id] /= repetition_penalty
                
                # Apply temperature
                if temperature != 1.0:
                    logits = logits / temperature
                
                # Softmax
                probs = self._softmax(logits)
                
                # Top-k filtering
                if top_k > 0:
                    probs = self._apply_top_k(probs, top_k)
                
                # Top-p filtering
                if top_p < 1.0:
                    probs = self._apply_top_p(probs, top_p)
                
                # Sample
                probs_sum = np.sum(probs)
                if probs_sum > 0:
                    probs = probs / probs_sum
                    next_token = int(np.random.choice(len(probs), p=probs))
                else:
                    next_token = int(np.argmax(probs))
            else:
                # Greedy decoding
                if repetition_penalty and repetition_penalty != 1.0:
                    for token_id in set(current_tokens):
                        if token_id < len(logits):
                            logits[token_id] /= repetition_penalty
                
                next_token = int(np.argmax(logits))
            
            # Check for end of sequence
            if next_token == self.padding_token:
                break
            
            generated_tokens.append(next_token)
            current_tokens.append(next_token)
            
            if len(current_tokens) >= self.max_seq_length:
                break
        
        return token_ids + generated_tokens
    
    def generate_text(
        self,
        prompt: str,
        max_new_tokens: int = 50,
        **kwargs
    ) -> str:
        """
        Convenience method that returns decoded text.
        
        Args:
            prompt: Input text
            max_new_tokens: Maximum new tokens
            **kwargs: Additional generation parameters
        
        Returns:
            Generated text (prompt + completion)
        """
        token_ids = self.generate(
            text=prompt,
            max_new_tokens=max_new_tokens,
            **kwargs
        )
        return self.tokenizer.decode(token_ids, skip_special_tokens=True)
    
    def complete(self, prompt: str, **kwargs) -> str:
        """
        Generate completion only (without the prompt).
        
        Args:
            prompt: Input text
            **kwargs: Generation parameters
        
        Returns:
            Generated completion text (without prompt)
        """
        full_text = self.generate_text(prompt, **kwargs)
        return full_text[len(prompt):].lstrip()
    
    def _softmax(self, x: np.ndarray) -> np.ndarray:
        exp_x = np.exp(x - np.max(x))
        return exp_x / np.sum(exp_x)
    
    def _apply_top_k(self, probs: np.ndarray, k: int) -> np.ndarray:
        top_k_idx = np.argsort(probs)[-k:]
        mask = np.zeros_like(probs)
        mask[top_k_idx] = 1
        return probs * mask
    
    def _apply_top_p(self, probs: np.ndarray, p: float) -> np.ndarray:
        sorted_idx = np.argsort(probs)[::-1]
        sorted_probs = probs[sorted_idx]
        cumsum = np.cumsum(sorted_probs)
        cutoff = np.searchsorted(cumsum, p) + 1
        
        mask = np.zeros_like(probs)
        mask[sorted_idx[:cutoff]] = 1
        return probs * mask


# Alias for backward compatibility
CerebrosOnnxGenerator = OnnxGenerator


def load_generator(model_path: str, tokenizer_path: str, **kwargs) -> OnnxGenerator:
    """
    Factory function to load an ONNX generator.
    
    Args:
        model_path: Path to ONNX model
        tokenizer_path: Path to tokenizer
        **kwargs: Additional arguments for OnnxGenerator
    
    Returns:
        Initialized OnnxGenerator
    """
    return OnnxGenerator(model_path, tokenizer_path, **kwargs)
