# =============================================================================
# LLMster Container - Headless LM Studio Server
# =============================================================================
# Build with: podman build -f Dockerfile.llmster -t llmster .
# =============================================================================

FROM docker.io/library/debian:trixie-slim

# Labels for documentation
LABEL maintainer="nickistre" \
      description="Headless LM Studio server container with AMD GPU support" \
      version="1.0.0"

# =============================================================================
# Installation Phase
# =============================================================================

# Install required dependencies including libatomic
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    tzdata \
    jq \
    libatomic1 \
    libgomp1 \
    libc6 \
    && curl -fsSL https://lmstudio.ai/install.sh | sh \
    && rm -rf /tmp/*install* \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Configuration Phase
# =============================================================================

# Set working directory
WORKDIR /root

# Create necessary directories
RUN mkdir -p \
    ~/.lmstudio/models \
    ~/.cache/llmster

# =============================================================================
# GPU Support Configuration (AMD Vulkan + ROCm)
# =============================================================================

# Install Mesa drivers for AMD GPU Vulkan support
RUN apt-get update && apt-get install -y --no-install-recommends \
    mesa-vulkan-drivers \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Vulkan driver
ENV LIBVA_DRIVER_NAME=radeonsi \
    VULKAN_ICD=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json

# Install ROCm runtime libraries (for LM Studio's ROCm backend).
# Set INSTALL_ROCM=0 at build time to skip and save ~2-3 GB image size.
ARG INSTALL_ROCM=1
ARG ROCM_VERSION=6.4

RUN if [ "$INSTALL_ROCM" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        wget gpg gpgv ca-certificates && \
      mkdir -p /etc/apt/keyrings && \
      wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key \
        | gpg --dearmor > /etc/apt/keyrings/rocm.gpg && \
      echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main" \
        > /etc/apt/sources.list.d/rocm.list && \
      printf 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600\n' \
        > /etc/apt/preferences.d/rocm-pin-600 && \
      printf 'APT::Key::GPGVCommand "/usr/bin/gpgv";\n' \
        > /etc/apt/apt.conf.d/99gpgv-compat && \
      apt-get update && apt-get install -y --no-install-recommends \
        hipblas rocblas && \
      apt-get clean && rm -rf /var/lib/apt/lists/* ; \
    fi

ENV LD_LIBRARY_PATH=/opt/rocm/lib

# =============================================================================
# LLMster Configuration
# =============================================================================

ENV PATH=/root/.lmstudio/bin:$PATH \
    LM_STUDIO_UPDATE=0 \
    LMS_RUNTIME_UPDATE=0

# Allow internal container communication
ENV OLLAMA_ORIGINS=* \
    LMS_SERVER_HOST=0.0.0.0

# =============================================================================
# Health Check Configuration
# =============================================================================

# Create health check script
RUN echo '#!/bin/sh' > /healthcheck.sh && \
    echo 'curl -f "http://localhost:${LLMSTER_PORT:-1234}/v1/models" || exit 1' >> /healthcheck.sh && \
    chmod +x /healthcheck.sh

# =============================================================================
# Entry Point
# =============================================================================

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 1234

ENTRYPOINT ["/entrypoint.sh"]
