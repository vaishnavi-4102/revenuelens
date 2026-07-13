# Extends the official Airflow image with:
#   1. the Snowflake provider, installed into Airflow's own environment
#      (this is the normal, supported way to add a provider)
#   2. two ISOLATED venvs for dbt and the data generator
#
# dbt-core and the generator's deps (pandas/numpy/Faker) are not pip
# installed into Airflow's own environment -- dbt-core in particular pulls
# in conflicting versions of packages Airflow also depends on (click,
# jinja2, requests), and installing it alongside Airflow is a well-known way
# to silently break Airflow itself. Each venv's entrypoint binary is
# symlinked into ~airflow/.local/bin instead of putting the venvs on PATH
# directly -- the official image's own entrypoint script resets PATH at
# container start (confirmed: a plain `ENV PATH=...` here is silently
# discarded by the time a task actually runs), but ~airflow/.local/bin
# survives that reset, so this is the one approach that's actually reliable.
# DAG code calls `dbt` and `revenuelens-python` by name -- no venv path is
# ever hardcoded into a DAG.
ARG AIRFLOW_VERSION=2.9.3
FROM apache/airflow:${AIRFLOW_VERSION}-python3.11

USER airflow

COPY dbt/requirements.txt /tmp/dbt-requirements.txt
RUN python -m venv "${AIRFLOW_HOME}/dbt-venv" && \
    "${AIRFLOW_HOME}/dbt-venv/bin/pip" install --no-cache-dir --upgrade pip && \
    "${AIRFLOW_HOME}/dbt-venv/bin/pip" install --no-cache-dir -r /tmp/dbt-requirements.txt

COPY data_generator/requirements.txt /tmp/gen-requirements.txt
RUN python -m venv "${AIRFLOW_HOME}/gen-venv" && \
    "${AIRFLOW_HOME}/gen-venv/bin/pip" install --no-cache-dir --upgrade pip && \
    "${AIRFLOW_HOME}/gen-venv/bin/pip" install --no-cache-dir -r /tmp/gen-requirements.txt

COPY airflow/requirements.txt /tmp/airflow-requirements.txt
RUN pip install --no-cache-dir -r /tmp/airflow-requirements.txt

# `dbt`'s own launcher script already has an absolute shebang pointing at
# its venv's python, so a plain symlink resolves correctly. A bare python
# *interpreter* binary is different: symlinking it directly breaks venv
# auto-detection (sys.executable resolves to the symlink's own path, not
# the venv, so it silently falls back to base site-packages and "works"
# while missing every package actually installed in gen-venv -- confirmed
# live). A tiny wrapper script that execs the real absolute path avoids
# that ambiguity entirely.
RUN mkdir -p /home/airflow/.local/bin && \
    ln -sf "${AIRFLOW_HOME}/dbt-venv/bin/dbt" /home/airflow/.local/bin/dbt && \
    printf '#!/bin/bash\nexec "%s/gen-venv/bin/python" "$@"\n' "${AIRFLOW_HOME}" > /home/airflow/.local/bin/revenuelens-python && \
    chmod +x /home/airflow/.local/bin/revenuelens-python
