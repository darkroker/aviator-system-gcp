#!/usr/bin/env python3
"""
AVIATOR SYSTEM LAUNCHER V19.3
============================

Lanzador automático para todos los componentes del sistema Aviator:
- Microservicios FastAPI (Detector en tiempo real, Motor de patrones)
- Dashboards Streamlit (Principal, Integrado)
- Verificación de salud de servicios
- Apertura automática del dashboard principal

Autor: Aviator System Team
Versión: 19.3
Fecha: 2025-01-24
"""

import subprocess
import time
import sys
import os
import signal
import webbrowser
import requests
from pathlib import Path
from typing import Dict, List, Optional
import logging
from datetime import datetime

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('aviator_system.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Configuración de servicios
SERVICES_CONFIG = {
    "realtime_detector": {
        "script": "microservicios/realtime_detector/main.py",
        "port": 8002,
        "health_endpoint": "/health",
        "description": "Detector en Tiempo Real"
    },
    "aviator_patterns_engine": {
        "script": "microservicios/aviator_patterns_engine/main.py", 
        "port": 8002,
        "health_endpoint": "/health",
        "description": "Motor de Patrones Aviator"
    },
    "main_dashboard": {
        "script": "dashboards/main_dashboard.py",
        "port": 8501,
        "health_endpoint": "/health",
        "description": "Dashboard Principal"
    },
    "integrated_dashboard": {
        "script": "dashboards/integrated_dashboard.py",
        "port": 8502,
        "health_endpoint": "/health",
        "description": "Dashboard Integrado"
    }
}

# Variables globales para gestión de procesos
running_processes: Dict[str, subprocess.Popen] = {}
shutdown_requested = False

def check_dependencies() -> bool:
    """Verificar que todas las dependencias estén instaladas."""
    required_packages = ['streamlit', 'fastapi', 'uvicorn', 'requests']
    
    logger.info("🔍 Verificando dependencias del sistema...")
    
    for package in required_packages:
        try:
            __import__(package)
            logger.info(f"✅ {package}: OK")
        except ImportError:
            logger.error(f"❌ {package}: NO ENCONTRADO")
            logger.error(f"Instala con: pip install {package}")
            return False
    
    logger.info("✅ Todas las dependencias están instaladas")
    return True

def check_scripts_exist() -> bool:
    """Verificar que todos los scripts del sistema existan."""
    logger.info("📁 Verificando existencia de scripts del sistema...")
    
    for service_name, config in SERVICES_CONFIG.items():
        script_path = Path(config["script"])
        if script_path.exists():
            logger.info(f"✅ {config['description']}: {script_path}")
        else:
            logger.error(f"❌ {config['description']}: {script_path} NO ENCONTRADO")
            return False
    
    logger.info("✅ Todos los scripts del sistema están presentes")
    return True

def start_service(service_name: str, config: Dict) -> Optional[subprocess.Popen]:
    """Iniciar un servicio específico."""
    script_path = config["script"]
    port = config["port"]
    description = config["description"]
    
    logger.info(f"🚀 Iniciando {description}...")
    
    try:
        # Determinar el comando según el tipo de script
        if "streamlit" in script_path or script_path.endswith(".py") and "dashboard" in script_path:
            cmd = [
                sys.executable, "-m", "streamlit", "run", 
                script_path, 
                "--server.port", str(port),
                "--server.headless", "true",
                "--browser.gatherUsageStats", "false"
            ]
        elif "fastapi" in script_path or "main.py" in script_path:
            cmd = [
                sys.executable, "-m", "uvicorn",
                f"{script_path.replace('/', '.').replace('.py', '')}:app",
                "--host", "0.0.0.0",
                "--port", str(port),
                "--reload"
            ]
        else:
            cmd = [sys.executable, script_path]
        
        # Iniciar el proceso
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        
        # Esperar un momento para verificar que el proceso se inició correctamente
        time.sleep(2)
        
        if process.poll() is None:
            logger.info(f"✅ {description} iniciado correctamente (PID: {process.pid})")
            return process
        else:
            stdout, stderr = process.communicate()
            logger.error(f"❌ Error al iniciar {description}:")
            logger.error(f"STDOUT: {stdout}")
            logger.error(f"STDERR: {stderr}")
            return None
            
    except Exception as e:
        logger.error(f"❌ Excepción al iniciar {description}: {e}")
        return None

def check_service_health(service_name: str, config: Dict, timeout: int = 30) -> bool:
    """Verificar que un servicio esté respondiendo correctamente."""
    port = config["port"]
    health_endpoint = config["health_endpoint"]
    url = f"http://localhost:{port}{health_endpoint}"
    
    logger.info(f"🏥 Verificando salud de {config['description']}...")
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                logger.info(f"✅ {config['description']}: ACTIVO")
                return True
        except requests.exceptions.RequestException:
            pass
        
        time.sleep(2)
    
    logger.warning(f"⚠️ {config['description']}: No responde en {url}")
    return False

def signal_handler(signum, frame):
    """Manejador de señales para cierre limpio."""
    global shutdown_requested
    logger.info("\n🛑 Señal de cierre recibida. Cerrando servicios...")
    shutdown_requested = True
    shutdown_all_services()
    sys.exit(0)

def shutdown_all_services():
    """Cerrar todos los servicios en ejecución."""
    logger.info("🔄 Cerrando todos los servicios...")
    
    for service_name, process in running_processes.items():
        if process and process.poll() is None:
            logger.info(f"🛑 Cerrando {service_name}...")
            try:
                process.terminate()
                process.wait(timeout=10)
                logger.info(f"✅ {service_name} cerrado correctamente")
            except subprocess.TimeoutExpired:
                logger.warning(f"⚠️ Forzando cierre de {service_name}...")
                process.kill()
                process.wait()
            except Exception as e:
                logger.error(f"❌ Error cerrando {service_name}: {e}")
    
    running_processes.clear()
    logger.info("✅ Todos los servicios han sido cerrados")

def open_main_dashboard():
    """Abrir el dashboard principal en el navegador."""
    dashboard_url = "http://localhost:8501"
    logger.info(f"🌐 Abriendo dashboard principal en {dashboard_url}")
    
    try:
        webbrowser.open(dashboard_url)
        logger.info("✅ Dashboard abierto en el navegador")
    except Exception as e:
        logger.error(f"❌ Error abriendo navegador: {e}")
        logger.info(f"📱 Accede manualmente a: {dashboard_url}")

def main():
    """Función principal del launcher."""
    # Configurar manejadores de señales
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("="*60)
    logger.info("🚀 AVIATOR SYSTEM LAUNCHER V19.3")
    logger.info("="*60)
    logger.info(f"📅 Iniciado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("")
    
    try:
        # Verificar dependencias
        if not check_dependencies():
            logger.error("❌ Faltan dependencias críticas. Abortando...")
            return 1
        
        # Verificar scripts
        if not check_scripts_exist():
            logger.error("❌ Faltan scripts del sistema. Abortando...")
            return 1
        
        logger.info("🎯 Iniciando servicios del sistema Aviator...")
        logger.info("")
        
        # Iniciar todos los servicios
        for service_name, config in SERVICES_CONFIG.items():
            if shutdown_requested:
                break
                
            process = start_service(service_name, config)
            if process:
                running_processes[service_name] = process
                logger.info(f"📊 {config['description']}: http://localhost:{config['port']}")
            else:
                logger.error(f"❌ No se pudo iniciar {config['description']}")
        
        logger.info("")
        logger.info("⏳ Esperando que todos los servicios estén listos...")
        time.sleep(10)
        
        # Verificar salud de servicios
        logger.info("")
        logger.info("🏥 VERIFICACIÓN DE SALUD DE SERVICIOS")
        logger.info("-" * 50)
        
        all_healthy = True
        for service_name, config in SERVICES_CONFIG.items():
            if service_name in running_processes:
                if not check_service_health(service_name, config):
                    all_healthy = False
        
        if all_healthy:
            logger.info("")
            logger.info("✅ TODOS LOS SERVICIOS ESTÁN ACTIVOS")
            logger.info("")
            logger.info("🔗 ENLACES DE ACCESO:")
            logger.info("-" * 30)
            for service_name, config in SERVICES_CONFIG.items():
                logger.info(f"📊 {config['description']}: http://localhost:{config['port']}")
            
            logger.info("")
            logger.info("🌐 Abriendo dashboard principal...")
            open_main_dashboard()
            
            logger.info("")
            logger.info("🎉 SISTEMA AVIATOR INICIADO CORRECTAMENTE")
            logger.info("💡 Presiona Ctrl+C para detener todos los servicios")
            logger.info("="*60)
            
            # Mantener el launcher ejecutándose
            try:
                while not shutdown_requested:
                    time.sleep(1)
                    
                    # Verificar que los procesos sigan ejecutándose
                    for service_name, process in list(running_processes.items()):
                        if process.poll() is not None:
                            logger.warning(f"⚠️ {service_name} se ha detenido inesperadamente")
                            del running_processes[service_name]
                            
            except KeyboardInterrupt:
                logger.info("\n🛑 Interrupción de teclado recibida")
        else:
            logger.error("❌ Algunos servicios no están respondiendo correctamente")
            return 1
            
    except Exception as e:
        logger.error(f"❌ Error crítico en el launcher: {e}")
        return 1
    
    finally:
        shutdown_all_services()
        logger.info("👋 Aviator System Launcher finalizado")
    
    return 0

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)