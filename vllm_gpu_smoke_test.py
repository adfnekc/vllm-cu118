import sys
import torch

print("==== GPU Environment Check ====")

# 1. torch cuda
print("Torch version:", torch.__version__)
print("CUDA version:", torch.version.cuda)

if not torch.cuda.is_available():
    print("ERROR: CUDA not available")
    sys.exit(1)

device_count = torch.cuda.device_count()
print("GPU count:", device_count)

for i in range(device_count):
    print(f"GPU {i}:", torch.cuda.get_device_name(i))

print("\n==== vLLM Import Check ====")

try:
    import vllm
    print("vLLM version:", vllm.__version__)
except Exception as e:
    print("ERROR: vLLM import failed")
    print(e)
    sys.exit(2)

print("\n==== vLLM Inference Test ====")

try:
    from vllm import LLM, SamplingParams

    llm = LLM(
        model="facebook/opt-125m",
        trust_remote_code=True,
        max_model_len=512
    )

    params = SamplingParams(
        temperature=0.7,
        max_tokens=20
    )

    outputs = llm.generate(
        ["Hello, my name is"],
        params
    )

    for out in outputs:
        print("Prompt:", out.prompt)
        print("Output:", out.outputs[0].text)

except Exception as e:
    print("ERROR: vLLM inference failed")
    print(e)
    sys.exit(3)

print("\n==== SUCCESS ====")
print("vLLM GPU stack works correctly")