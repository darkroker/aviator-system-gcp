# Script de Despliegue Automatizado para Sistema Aviator en GCP
# PowerShell Script para Windows

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "development",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectId = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTerraform = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDocker = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Destroy = $false
)

# Configuración
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$TerraformDir = Join-Path $ScriptDir "..\terraform"
$ConfigsDir = Join-Path $ScriptDir "..\configs"

# Colores para output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-ColorOutput $Message "Green" }
function Write-Warning { param([string]$Message) Write-ColorOutput $Message "Yellow" }
function Write-Error { param([string]$Message) Write-ColorOutput $Message "Red" }
function Write-Info { param([string]$Message) Write-ColorOutput $Message "Cyan" }

# Función para verificar dependencias
function Test-Dependencies {
    Write-Info "🔍 Verificando dependencias..."
    
    $dependencies = @(
        @{Name="gcloud"; Command="gcloud version"},
        @{Name="terraform"; Command="terraform version"},
        @{Name="docker"; Command="docker --version"}
    )
    
    foreach ($dep in $dependencies) {
        try {
            Invoke-Expression $dep.Command | Out-Null
            Write-Success "✓ $($dep.Name) está instalado"
        }
        catch {
            Write-Error "✗ $($dep.Name) no está instalado o no está en PATH"
            throw "Dependencia faltante: $($dep.Name)"
        }
    }
}

# Función para configurar GCP
function Initialize-GCP {
    param([string]$ProjectId)
    
    Write-Info "🔧 Configurando Google Cloud Platform..."
    
    if (-not $ProjectId) {
        $ProjectId = Read-Host "Ingrese el Project ID de GCP"
    }
    
    try {
        # Configurar proyecto por defecto
        gcloud config set project $ProjectId
        Write-Success "✓ Proyecto configurado: $ProjectId"
        
        # Verificar autenticación
        $currentAccount = gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if (-not $currentAccount) {
            Write-Warning "⚠ No hay cuenta autenticada. Iniciando autenticación..."
            gcloud auth login
        }
        else {
            Write-Success "✓ Autenticado como: $currentAccount"
        }
        
        # Habilitar APIs necesarias
        Write-Info "🔌 Habilitando APIs necesarias..."
        $apis = @(
            "compute.googleapis.com",
            "sql-component.googleapis.com",
            "storage-component.googleapis.com",
            "monitoring.googleapis.com",
            "logging.googleapis.com",
            "secretmanager.googleapis.com",
            "cloudbuild.googleapis.com"
        )
        
        foreach ($api in $apis) {
            Write-Info "  Habilitando $api..."
            gcloud services enable $api --quiet
        }
        Write-Success "✓ APIs habilitadas"
        
    }
    catch {
        Write-Error "Error configurando GCP: $($_.Exception.Message)"
        throw
    }
}

# Función para preparar Terraform
function Initialize-Terraform {
    Write-Info "🏗️ Preparando Terraform..."
    
    Push-Location $TerraformDir
    try {
        # Verificar archivo de variables
        if (-not (Test-Path "terraform.tfvars")) {
            if (Test-Path "terraform.tfvars.example") {
                Write-Warning "⚠ No se encontró terraform.tfvars. Copiando desde ejemplo..."
                Copy-Item "terraform.tfvars.example" "terraform.tfvars"
                Write-Warning "⚠ IMPORTANTE: Edite terraform.tfvars con sus valores reales antes de continuar"
                
                if (-not $Force) {
                    $continue = Read-Host "¿Desea continuar? (y/N)"
                    if ($continue -ne "y" -and $continue -ne "Y") {
                        throw "Despliegue cancelado por el usuario"
                    }
                }
            }
            else {
                throw "No se encontró terraform.tfvars ni terraform.tfvars.example"
            }
        }
        
        # Inicializar Terraform
        Write-Info "  Inicializando Terraform..."
        terraform init
        
        # Validar configuración
        Write-Info "  Validando configuración..."
        terraform validate
        
        # Planificar cambios
        Write-Info "  Planificando cambios..."
        terraform plan -out="tfplan"
        
        Write-Success "✓ Terraform preparado"
    }
    finally {
        Pop-Location
    }
}

# Función para aplicar Terraform
function Deploy-Infrastructure {
    Write-Info "🚀 Desplegando infraestructura..."
    
    Push-Location $TerraformDir
    try {
        if (-not $Force) {
            Write-Warning "⚠ Se va a crear infraestructura en GCP. Esto puede generar costos."
            $continue = Read-Host "¿Desea continuar? (y/N)"
            if ($continue -ne "y" -and $continue -ne "Y") {
                throw "Despliegue cancelado por el usuario"
            }
        }
        
        # Aplicar plan
        terraform apply "tfplan"
        
        # Guardar outputs
        $outputFile = Join-Path $ConfigsDir "terraform-outputs.json"
        terraform output -json | Out-File -FilePath $outputFile -Encoding UTF8
        
        Write-Success "✓ Infraestructura desplegada"
        Write-Info "📄 Outputs guardados en: $outputFile"
        
        # Mostrar información importante
        Write-Info "📋 Información del despliegue:"
        terraform output
        
    }
    finally {
        Pop-Location
    }
}

# Función para destruir infraestructura
function Destroy-Infrastructure {
    Write-Warning "🗑️ DESTRUYENDO infraestructura..."
    
    Push-Location $TerraformDir
    try {
        if (-not $Force) {
            Write-Warning "⚠ PELIGRO: Se va a DESTRUIR toda la infraestructura."
            Write-Warning "⚠ Esto eliminará PERMANENTEMENTE todos los recursos."
            $confirm = Read-Host "Escriba 'DESTROY' para confirmar"
            if ($confirm -ne "DESTROY") {
                throw "Destrucción cancelada"
            }
        }
        
        terraform destroy -auto-approve
        Write-Success "✓ Infraestructura destruida"
        
    }
    finally {
        Pop-Location
    }
}

# Función para desplegar aplicación
function Deploy-Application {
    Write-Info "📦 Desplegando aplicación..."
    
    try {
        # Leer outputs de Terraform
        $outputFile = Join-Path $ConfigsDir "terraform-outputs.json"
        if (-not (Test-Path $outputFile)) {
            throw "No se encontraron outputs de Terraform. Ejecute primero el despliegue de infraestructura."
        }
        
        $outputs = Get-Content $outputFile | ConvertFrom-Json
        $instanceName = $outputs.compute_instance.value.name
        $zone = $outputs.compute_instance.value.zone
        
        # Copiar archivos a la instancia
        Write-Info "  Copiando archivos a la instancia..."
        $filesToCopy = @(
            "docker-compose.gcp.yml",
            "Dockerfile.gcp",
            ".env.gcp"
        )
        
        foreach ($file in $filesToCopy) {
            $localPath = Join-Path $RootDir $file
            if (Test-Path $localPath) {
                gcloud compute scp $localPath "${instanceName}:~/" --zone=$zone --quiet
                Write-Success "    ✓ Copiado: $file"
            }
            else {
                Write-Warning "    ⚠ No encontrado: $file"
            }
        }
        
        # Ejecutar comandos en la instancia
        Write-Info "  Configurando aplicación en la instancia..."
        $commands = @(
            "sudo apt-get update -y",
            "sudo apt-get install -y docker.io docker-compose",
            "sudo systemctl start docker",
            "sudo systemctl enable docker",
            "sudo usermod -aG docker $USER",
            "docker-compose -f docker-compose.gcp.yml pull",
            "docker-compose -f docker-compose.gcp.yml up -d"
        )
        
        foreach ($cmd in $commands) {
            Write-Info "    Ejecutando: $cmd"
            gcloud compute ssh $instanceName --zone=$zone --command="$cmd" --quiet
        }
        
        Write-Success "✓ Aplicación desplegada"
        
        # Mostrar URLs
        $externalIp = $outputs.compute_instance.value.external_ip
        Write-Info "🌐 URLs de la aplicación:"
        Write-Info "  Aplicación principal: http://$externalIp:8000"
        Write-Info "  Dashboard: http://$externalIp:8001"
        Write-Info "  API Docs: http://$externalIp:8000/docs"
        
    }
    catch {
        Write-Error "Error desplegando aplicación: $($_.Exception.Message)"
        throw
    }
}

# Función para verificar estado
function Test-Deployment {
    Write-Info "🔍 Verificando estado del despliegue..."
    
    try {
        $outputFile = Join-Path $ConfigsDir "terraform-outputs.json"
        if (Test-Path $outputFile) {
            $outputs = Get-Content $outputFile | ConvertFrom-Json
            $externalIp = $outputs.compute_instance.value.external_ip
            
            # Verificar conectividad
            Write-Info "  Verificando conectividad..."
            $healthUrl = "http://$externalIp:8000/health"
            
            try {
                $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 10
                if ($response.StatusCode -eq 200) {
                    Write-Success "✓ Aplicación respondiendo correctamente"
                }
                else {
                    Write-Warning "⚠ Aplicación responde pero con código: $($response.StatusCode)"
                }
            }
            catch {
                Write-Warning "⚠ No se puede conectar a la aplicación. Puede estar iniciándose..."
            }
        }
        else {
            Write-Warning "⚠ No se encontraron outputs de Terraform"
        }
    }
    catch {
        Write-Error "Error verificando despliegue: $($_.Exception.Message)"
    }
}

# Función principal
function Main {
    try {
        Write-Info "🚀 Iniciando despliegue del Sistema Aviator en GCP"
        Write-Info "📅 $(Get-Date)"
        Write-Info "🌍 Entorno: $Environment"
        
        # Verificar dependencias
        Test-Dependencies
        
        if ($Destroy) {
            Destroy-Infrastructure
            return
        }
        
        # Configurar GCP
        Initialize-GCP -ProjectId $ProjectId
        
        # Desplegar infraestructura
        if (-not $SkipTerraform) {
            Initialize-Terraform
            Deploy-Infrastructure
        }
        
        # Desplegar aplicación
        if (-not $SkipDocker) {
            Deploy-Application
        }
        
        # Verificar estado
        Test-Deployment
        
        Write-Success "🎉 Despliegue completado exitosamente!"
        Write-Info "📚 Consulte la documentación para próximos pasos"
        
    }
    catch {
        Write-Error "💥 Error durante el despliegue: $($_.Exception.Message)"
        Write-Error "📋 Stack trace: $($_.ScriptStackTrace)"
        exit 1
    }
}

# Mostrar ayuda
if ($args -contains "-h" -or $args -contains "--help") {
    Write-Host @"
🚀 Script de Despliegue del Sistema Aviator en GCP

USO:
    .\deploy.ps1 [OPCIONES]

OPCIONES:
    -Environment <env>     Entorno de despliegue (development, staging, production)
    -ProjectId <id>        ID del proyecto de GCP
    -SkipTerraform         Omitir despliegue de infraestructura
    -SkipDocker           Omitir despliegue de aplicación
    -Force                Ejecutar sin confirmaciones
    -Destroy              Destruir infraestructura
    -h, --help            Mostrar esta ayuda

EJEMPLOS:
    .\deploy.ps1 -Environment development -ProjectId mi-proyecto-123
    .\deploy.ps1 -SkipTerraform -Environment production
    .\deploy.ps1 -Destroy -Force

REQUISITOS:
    - Google Cloud SDK (gcloud)
    - Terraform
    - Docker
    - PowerShell 5.1+

"@
    exit 0
}

# Ejecutar función principal
Main