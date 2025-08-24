# Multi-stage Dockerfile optimizado para Google Cloud Platform
# Sistema Aviator V19.3 - Producción
# Optimizado para seguridad, performance y tamaño

# ============================================================================
# STAGE 1: Builder - Compilar dependencias y preparar aplicación
# ============================================================================
FROM python:3.11-slim-bullseye AS builder

# Metadatos
LABEL maintainer="Aviator System Team" \
      version="19.3" \
      description="Sistema Aviator optimizado para GCP" \
      org.opencontainers.image.source="https://github.com/aviator-trading/aviator-system" \
      org.opencontainers.image.vendor="Aviator Trading" \
      org.opencontainers.image.licenses="MIT"

# Variables de entorno para optimización del build
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH=/app

# Instalar dependencias de compilación
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    make \
    libpq-dev \
    libssl-dev \
    libffi-dev \
    libc6-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Crear directorio de trabajo
WORKDIR /app

# Copiar archivos de requirements
COPY requirements.txt .
COPY aviator_system_core/requirements.txt ./core_requirements.txt

# Crear virtual environment y instalar dependencias
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Actualizar pip y instalar wheel para compilaciones más rápidas
RUN pip install --upgrade pip setuptools wheel

# Instalar dependencias Python en el virtual environment
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -r core_requirements.txt && \
    pip install --no-cache-dir \
        gunicorn[gevent]==21.2.0 \
        uvicorn[standard]==0.24.0 \
        google-cloud-monitoring==2.16.0 \
        google-cloud-logging==3.8.0 \
        google-cloud-storage==2.10.0 \
        google-cloud-sql-connector==1.4.3 \
        google-cloud-secret-manager==2.17.0 \
        google-cloud-kms==2.19.1 \
        prometheus-client==0.19.0 \
        structlog==23.2.0

# ============================================================================
# STAGE 2: Runtime - Imagen final optimizada
# ============================================================================
FROM python:3.11-slim-bullseye AS runtime

# Variables de entorno para runtime
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    PATH="/opt/venv/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive \
    # Variables específicas de GCP
    GOOGLE_CLOUD_PROJECT="" \
    GOOGLE_APPLICATION_CREDENTIALS="/app/credentials/service-account.json" \
    # Variables de aplicación
    FLASK_ENV=production \
    FLASK_DEBUG=0 \
    GUNICORN_WORKERS=4 \
    GUNICORN_TIMEOUT=120 \
    GUNICORN_KEEPALIVE=5 \
    # Variables de seguridad
    UMASK=0027

# Instalar solo dependencias runtime necesarias
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libpq5 \
    libssl1.1 \
    libffi7 \
    # Herramientas de monitoreo y debugging
    procps \
    htop \
    netcat-openbsd \
    # Cloud SQL Proxy
    && curl -o /usr/local/bin/cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 \
    && chmod +x /usr/local/bin/cloud_sql_proxy \
    # Limpiar cache
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && apt-get autoremove -y

# Crear usuario y grupo no-root para seguridad
RUN groupadd -r -g 1001 aviator && \
    useradd -r -u 1001 -g aviator -d /app -s /bin/bash aviator

# Crear estructura de directorios con permisos correctos
RUN mkdir -p /app/{data,logs,config,models,credentials,tmp} \
    /var/log/aviator \
    /var/run/aviator && \
    chown -R aviator:aviator /app /var/log/aviator /var/run/aviator && \
    chmod 750 /app && \
    chmod 755 /app/data /app/logs /app/config /app/models && \
    chmod 700 /app/credentials && \
    chmod 1777 /app/tmp

# Copiar virtual environment desde builder
COPY --from=builder /opt/venv /opt/venv

# Establecer directorio de trabajo
WORKDIR /app

# Copiar código fuente con permisos correctos
COPY --chown=aviator:aviator . .

# Copiar configuraciones específicas de GCP
COPY --chown=aviator:aviator gcp/configs/ ./config/gcp/

# Crear scripts de entrada optimizados
RUN echo '#!/bin/bash\n\
set -euo pipefail\n\
\n\
# Función de logging\n\
log() {\n\
    echo "[$(date -Iseconds)] $*" >&2\n\
}\n\
\n\
# Verificar variables de entorno críticas\n\
if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then\n\
    log "ERROR: GOOGLE_CLOUD_PROJECT no está configurado"\n\
    exit 1\n\
fi\n\
\n\
# Inicializar Cloud SQL Proxy si está configurado\n\
if [[ -n "${CLOUD_SQL_CONNECTION_NAME:-}" ]]; then\n\
    log "Iniciando Cloud SQL Proxy..."\n\
    cloud_sql_proxy -instances="${CLOUD_SQL_CONNECTION_NAME}"=tcp:5432 &\n\
    PROXY_PID=$!\n\
    echo $PROXY_PID > /var/run/aviator/cloud_sql_proxy.pid\n\
fi\n\
\n\
# Esperar a que los servicios estén listos\n\
log "Esperando servicios..."\n\
sleep 5\n\
\n\
# Ejecutar comando principal\n\
log "Iniciando aplicación Aviator..."\n\
exec "$@"' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh && \
    chown aviator:aviator /app/entrypoint.sh

# Crear script de health check optimizado
RUN echo '#!/bin/bash\n\
set -euo pipefail\n\
\n\
# Health check para múltiples servicios\n\
check_service() {\n\
    local service_name="$1"\n\
    local url="$2"\n\
    local timeout="${3:-5}"\n\
    \n\
    if curl -f -s --max-time "$timeout" "$url" > /dev/null 2>&1; then\n\
        echo "$service_name: OK"\n\
        return 0\n\
    else\n\
        echo "$service_name: FAIL"\n\
        return 1\n\
    fi\n\
}\n\
\n\
# Verificar servicios principales\n\
failed=0\n\
\n\
# API principal\n\
check_service "API" "http://localhost:8000/health" || failed=$((failed + 1))\n\
\n\
# Dashboard\n\
check_service "Dashboard" "http://localhost:8080/health" || failed=$((failed + 1))\n\
\n\
# Verificar procesos críticos\n\
if ! pgrep -f "python.*start_aviator" > /dev/null; then\n\
    echo "Proceso principal: FAIL"\n\
    failed=$((failed + 1))\n\
else\n\
    echo "Proceso principal: OK"\n\
fi\n\
\n\
# Verificar uso de memoria (no debe exceder 90%)\n\
mem_usage=$(free | awk "/^Mem:/ {printf \"%.0f\", \$3/\$2 * 100}")\n\
if [[ $mem_usage -gt 90 ]]; then\n\
    echo "Memoria: WARN (${mem_usage}%)"\n\
else\n\
    echo "Memoria: OK (${mem_usage}%)"\n\
fi\n\
\n\
if [[ $failed -eq 0 ]]; then\n\
    echo "Health check: PASSED"\n\
    exit 0\n\
else\n\
    echo "Health check: FAILED ($failed servicios fallaron)"\n\
    exit 1\n\
fi' > /app/healthcheck.sh && \
    chmod +x /app/healthcheck.sh && \
    chown aviator:aviator /app/healthcheck.sh

# Cambiar a usuario no-root
USER aviator

# Exponer puertos
EXPOSE 8000 8080 8501 9090

# Health check mejorado
HEALTHCHECK --interval=30s --timeout=15s --start-period=120s --retries=3 \
    CMD ["/app/healthcheck.sh"]

# Configurar punto de entrada
ENTRYPOINT ["/app/entrypoint.sh"]

# Comando por defecto optimizado para producción
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "${GUNICORN_WORKERS}", \
     "--worker-class", "gevent", \
     "--worker-connections", "1000", \
     "--timeout", "${GUNICORN_TIMEOUT}", \
     "--keepalive", "${GUNICORN_KEEPALIVE}", \
     "--max-requests", "10000", \
     "--max-requests-jitter", "1000", \
     "--preload", \
     "--log-level", "warning", \
     "--access-logfile", "/var/log/aviator/access.log", \
     "--error-logfile", "/var/log/aviator/error.log", \
     "--capture-output", \
     "--enable-stdio-inheritance", \
     "start_aviator_system:app"]