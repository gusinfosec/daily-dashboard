FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./app.py
COPY templates ./templates

# Default envs (override at runtime)
ENV OWM_API_KEY="" \
    CITY="Boca Raton" \
    COUNTRY="US" \
    UNITS="imperial"

EXPOSE 5000
# Use gunicorn for production-ish serving
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "app:app"]
