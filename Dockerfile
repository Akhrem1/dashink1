FROM python:3.14.6-slim@sha256:7bec7ddcddeff7975d6ba9b4be7dd6f6b2f55e7491539145e2978f7f97ce9144

# DejaVu is the render font; Pillow needs a real TTF and slim images ship none.
RUN apt-get update \
 && apt-get install -y --no-install-recommends fonts-dejavu-core curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Named explicitly rather than `COPY . .` so the build context's kindle/,
# docs/ and __pycache__ stay out of the image. The cost is that a new module
# has to be added here too, or the container dies on import at startup.
COPY app.py sources.py render.py i18n.py ./
COPY lang/ ./lang/

# The app writes nothing and listens above 1024, so it has no reason to be root.
# The copied files stay root-owned and world-readable, which also stops the
# process rewriting its own code.
#
# The home directory has to exist even though nothing of ours writes to it:
# --no-create-home still records /home/dashink in passwd, and gunicorn's control
# server opens $HOME at startup. Without it every boot logs
# "Control server error: [Errno 13] Permission denied: '/home/dashink'" while
# otherwise serving normally.
RUN useradd --system --create-home --home-dir /home/dashink --uid 10001 dashink
USER dashink

EXPOSE 8099

# One worker, two threads: renders are ~100ms and the only client is a Kindle
# waking up every few minutes. More workers would just duplicate the caches.
CMD ["gunicorn", "--bind", "0.0.0.0:8099", "--workers", "1", "--threads", "2", \
     "--access-logfile", "-", "app:app"]
