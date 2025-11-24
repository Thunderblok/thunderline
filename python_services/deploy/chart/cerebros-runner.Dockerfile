FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for TensorFlow
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    tensorflow>=2.15.0 \
    transformers \
    scikit-learn \
    pandas \
    numpy \
    mlflow \
    optuna \
    pendulum \
    jax[cpu] \
    pyvis \
    networkx

# Copy the cerebros Python package directly (build context is /home/mo/DEV)
COPY cerebros-core-algorithm-alpha/cerebros-core-algorithm-alpha/cerebros /app/cerebros

# Copy the POC script (moved out of chart/files to avoid Helm size limits)
COPY Thunderline/thunderhelm/deploy/cerebros_runner_poc.py /app/cerebros_runner.py

# Download the KJV bible text (needed by the POC)
RUN curl -sL https://raw.githubusercontent.com/mxw/grmr/master/src/finaltests/bible.txt -o /app/king-james-bible.txt

EXPOSE 8088

CMD ["python", "cerebros_runner.py"]
