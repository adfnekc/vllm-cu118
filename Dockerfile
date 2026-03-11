# ==============================
# Stage 1: build
# ==============================
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    build-essential \
    ninja-build

RUN python3 -m pip install --upgrade pip

# # 安装 PyTorch cu118
RUN pip install \
    torch==2.1.2+cu118 \
    torchvision==0.16.2+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

# 安装 vLLM
RUN pip install vllm

# 清理 pip cache
RUN rm -rf ~/.cache/pip


# ==============================
# Stage 2: runtime
# ==============================
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update 
RUN apt-get install -y \
    python3 \
    python3-pip \
    libglib2.0-0

# 复制 python packages
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# 删除缓存
RUN rm -rf \
    ~/.cache \
    /root/.nv \
    /tmp/*

ENV VLLM_WORKER_MULTIPROC_METHOD=spawn

WORKDIR /workspace

EXPOSE 8000

CMD ["python3", "-m", "vllm.entrypoints.openai.api_server", \
     "--host", "0.0.0.0", \
     "--port", "8000"]