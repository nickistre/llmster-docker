# =============================================================================
# LLMster Container - Headless LM Studio Server
# =============================================================================
# Build with: podman build -f Dockerfile.llmster -t llmster .
# =============================================================================

FROM docker.io/library/debian:trixie-slim

# Labels for documentation
LABEL maintainer="Project Team" \
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
# GPU Support Configuration (AMD/Vulcan)
# =============================================================================

# Install Mesa drivers for AMD GPU support
RUN apt-get update && apt-get install -y --no-install-recommends \
    mesa-vulkan-drivers \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Vulkan driver
ENV LIBVA_DRIVER_NAME=radeonsi \
    VULKAN_ICD=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json

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
