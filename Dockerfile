# Stage 1: Build Environment
# Here we install all dependencies and prepare necessary data.
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
RUN pip install awscli-local

# Download NLTK data
RUN python -m nltk.downloader punkt stopwords wordnet omw-1.4


# Stage 2: Final Runtime Environment
# This stage is minimal and contains only what's needed to run the application.
FROM python:3.11-slim-bookworm
WORKDIR /app

# Copy all pip-installed tools (including Python packages and AWS CLI)
COPY --from=builder /usr/local /usr/local

# Copy the downloaded NLTK data
COPY --from=builder /root/nltk_data /root/nltk_data

# Set the environment variable so NLTK can locate the data
ENV NLTK_DATA=/root/nltk_data

# Copy the application
COPY src/ ./src
COPY data/ ./data
COPY results/ ./results
COPY main.sh ./
# COPY instructions.pdf ./
COPY README.md ./
COPY LICENSE ./

# Ensure executable permissions
RUN chmod +x main.sh

# Default command
CMD ["./main.sh", "all"]