FROM python:3.12-slim

WORKDIR /app

# Dependencies change rarely, so they come first and stay cached.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Source changes on every commit, so it comes last.
COPY main.py VERSION ./

# Run as a non-root user.
RUN useradd --uid 10001 --no-create-home app
USER 10001

ENV PORT=8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 4 --timeout 30 main:app
