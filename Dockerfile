# Stage 1: Build Environment
FROM python:3.11-slim-bookworm AS builder

# Create app directory
WORKDIR /app

# Install system tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       zip curl jq git \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip to the latest version
RUN pip install --upgrade pip

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install AWS CLI via pip (more secure and version controllable)
RUN pip install awscli-local awscli

# Download NLTK data
RUN python -m nltk.downloader punkt stopwords wordnet omw-1.4

# Verify AWS CLI installation
RUN aws --version

# Stage 2: Final Runtime Environment
FROM python:3.11-slim-bookworm
WORKDIR /app

# Install runtime tools in final image
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       zip unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy all pip-installed tools (including Python packages and AWS CLI)
COPY --from=builder /usr/local /usr/local

# Copy the downloaded NLTK data
COPY --from=builder /root/nltk_data /root/nltk_data

# Set the environment variable so NLTK can locate the data
ENV NLTK_DATA=/root/nltk_data

# Ensure the PATH includes the location where pip installs binaries
ENV PATH="/usr/local/bin:$PATH"

# Copy the application files
COPY src/ ./src
COPY data/ ./data
COPY results/ ./results
COPY scripts/ ./scripts
COPY README.md ./
COPY LICENSE ./

# Ensure executable permissions for all scripts
RUN chmod +x scripts/*.sh

# Verify AWS CLI is available in final image
RUN aws --version

# Default command - keep container running
CMD ["tail", "-f", "/dev/null"]