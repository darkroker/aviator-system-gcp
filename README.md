# Aviator System V19.3 - GCP Deployment

🚀 Sistema de Trading Aviator optimizado para Google Cloud Platform

## Características

- **Dashboard en tiempo real** con Streamlit
- **API REST** con FastAPI
- **Detección de patrones** con Machine Learning
- **Despliegue automático** en Cloud Run
- **Monitoreo integrado** con Cloud Monitoring
- **Escalado automático** basado en demanda

## Arquitectura

- **Frontend**: Streamlit Dashboard (Puerto 8501)
- **Backend**: FastAPI Microservices (Puerto 8002)
- **Base de datos**: SQLite/PostgreSQL
- **Contenedor**: Docker optimizado para GCP
- **Orquestación**: Cloud Run

## Despliegue

El sistema se despliega automáticamente en GCP usando GitHub Actions cuando se hace push a la rama `main`.

### Configuración requerida:

1. **Proyecto GCP**: `aviator-trading-system-prod`
2. **Región**: `us-central1`
3. **Secreto GitHub**: `GCP_SA_KEY` (Service Account JSON)

### URLs de acceso:

- **Dashboard Principal**: `https://aviator-system-[hash]-uc.a.run.app`
- **API Health Check**: `https://aviator-system-[hash]-uc.a.run.app/health`
- **API Documentation**: `https://aviator-system-[hash]-uc.a.run.app/docs`

## Monitoreo

- **Logs**: Cloud Logging
- **Métricas**: Cloud Monitoring
- **Alertas**: Configuradas para errores y latencia
- **Health Checks**: Automáticos cada 30 segundos

## Seguridad

- **Autenticación**: IAM de Google Cloud
- **Encriptación**: En tránsito y en reposo
- **Firewall**: Configurado para tráfico HTTPS únicamente
- **Secrets**: Gestionados con Secret Manager

---

**Versión**: 19.3  
**Última actualización**: 2025-01-24  
**Estado**: ✅ Activo en producción
