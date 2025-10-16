import os, sys
from cerebras.cloud.sdk import Cerebras

client = Cerebras(
    api_key="csk-5m5kfmy5c4dp9mp28ppxdwdwm5px4kvccyy5223kkhrv5cmc"
)

MODEL = "qwen-3-coder-480b" # "qwen-3-235b-a22b-instruct-2507"

MAX_SEQ_LEN = 30

print("Paste your data here press enter then press ctrl+z and then enter again: \n")
RAW_TEXT = sys.stdin.read()
PROMPT = f"""

Please package the data below o train an LLM for non-instruct text completion.

1. Context length summarization (not truncation) to proof-of-concept scale of **NO MORE THAN** {MAX_SEQ_LEN} tokens per sample.
2 Strip anything that is not English prose: Citations, URLs, line wraps, stray Unicode, labels, page numbers, verse numbers, etc.
3 Ensuring that samples begin with proper capitalization, end with correct punctuation and a natural end of paragraph, **not just naively truncating sequential sentences in the text** as separate samples that end “mid - paragraph” … which would have the undesired effect of encouraging the model to write in a verbose format beyond the context window and terminate its writings mid paragraph / throw a stop token without expressing a complete thought.
4. Package as a Python list[str].
5. Make no comments like "here is the data packaged as requested". Simply return a Python list[str] as described.
6. Process the entire data provided, as described.

This is the data to package.

```text
{RAW_TEXT}
```


"""

completion_create_response = client.chat.completions.create(
    messages=[
        {
            "role": "user",
            "content": PROMPT
        }
    ],
    model=MODEL,
    stream=False,
    max_completion_tokens=20000,
    temperature=0.7,
    top_p=0.8
)

print(completion_create_response)
