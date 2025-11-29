FROM python:3.11-slim

WORKDIR /app

# Copy all static files
COPY . .

# Expose port (PORT will be set at runtime by Koyeb)
EXPOSE 8000

# Start simple HTTP server using PORT environment variable
CMD sh -c "python -m http.server ${PORT:-8000}"
