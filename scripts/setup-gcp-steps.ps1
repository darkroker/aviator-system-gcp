# 🚀 Script de Automatización de Pasos GCP para Aviator Trading
# Automatiza los pasos específicos de la guía "Pasos Inmediatos desde la Pantalla de GCP.txt"

param(
    [Parameter(Mandatory=$true, HelpMessage="ID del proyecto GCP (ej: aviator-trading-123456)")]
    [string]$ProjectId,
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-central1",
    
    [Parameter(Mandatory=$false)]
    [string]$Zone = "us-central1-a",
    
    [Parameter(Mandatory=$false)]
    [int]$BudgetAmount = 250,
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceAccountName = "aviator-deployment-sa",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBilling = $false
)

$ErrorActionPreference = "Stop"

# Colores para output
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step { param([string]$Message) Write-ColorOutput "📋 $Message" "Cyan" }
function Write-Success { param([string]$Message) Write-ColorOutput "✅ $Message" "Green" }
function Write-Warning { param([string]$Message) Write-ColorOutput "⚠️  $Message" "Yellow" }
function Write-Error { param([string]$Message) Write-ColorOutput "❌ $Message" "Red" }
function Write-Info { param([string]$Message) Write-ColorOutput "💡 $Message" "White" }

# Función para verificar prerequisitos
function Test-Prerequisites {
    Write-Step "Verificando prerequisitos..."
    
    # Verificar Google Cloud CLI
    try {
        $gcloudVersion = gcloud version --format="value(Google Cloud SDK)" 2>$null
        if ($gcloudVersion) {
            Write-Success "Google Cloud CLI instalado: $gcloudVersion"
        } else {
            throw "Google Cloud CLI no encontrado"
        }
    } catch {
        Write-Error "Google Cloud CLI no está instalado"
        Write-Info "Instala Google Cloud CLI desde: https://cloud.google.com/sdk/docs/install"
        Write-Info "O ejecuta: choco install gcloudsdk"
        return $false
    }
    
    # Verificar autenticación
    try {
        $account = gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if ($account) {
            Write-Success "Autenticado como: $account"
        } else {
            Write-Warning "No hay cuenta autenticada"
            Write-Info "Ejecutando autenticación..."
            gcloud auth login
            
            # Verificar nuevamente
            $account = gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
            if ($account) {
                Write-Success "Autenticación exitosa: $account"
            } else {
                Write-Error "Falló la autenticación"
                return $false
            }
        }
    } catch {
        Write-Error "Error verificando autenticación: $($_.Exception.Message)"
        return $false
    }
    
    return $true
}

# PASO 1: Crear Proyecto Específico para Aviator
function Step1-CreateProject {
    Write-Step "PASO 1: Crear Proyecto Específico para Aviator"
    
    try {
        # Verificar si el proyecto ya existe
        $existingProject = gcloud projects describe $ProjectId --format="value(projectId)" 2>$null
        
        if ($existingProject) {
            Write-Warning "El proyecto '$ProjectId' ya existe"
            Write-Info "Configurando como proyecto activo..."
        } else {
            Write-Info "Creando proyecto: $ProjectId"
            gcloud projects create $ProjectId --name="Aviator Trading System"
            Write-Success "Proyecto creado exitosamente"
        }
        
        # Configurar como proyecto por defecto
        gcloud config set project $ProjectId
        gcloud config set compute/region $Region
        gcloud config set compute/zone $Zone
        
        Write-Success "Proyecto configurado como activo: $ProjectId"
        Write-Info "Región: $Region, Zona: $Zone"
        
        return $true
        
    } catch {
        Write-Error "Error en Paso 1: $($_.Exception.Message)"
        return $false
    }
}

# PASO 2: Habilitar APIs Necesarias
function Step2-EnableAPIs {
    Write-Step "PASO 2: Habilitar APIs Necesarias"
    
    $requiredAPIs = @(
        @{Name="Compute Engine API"; Service="compute.googleapis.com"},
        @{Name="Cloud SQL Admin API"; Service="sqladmin.googleapis.com"},
        @{Name="Cloud Storage API"; Service="storage.googleapis.com"},
        @{Name="Cloud Build API"; Service="cloudbuild.googleapis.com"},
        @{Name="Cloud Monitoring API"; Service="monitoring.googleapis.com"},
        @{Name="Secret Manager API"; Service="secretmanager.googleapis.com"},
        @{Name="Cloud Resource Manager API"; Service="cloudresourcemanager.googleapis.com"},
        @{Name="IAM API"; Service="iam.googleapis.com"},
        @{Name="Cloud Logging API"; Service="logging.googleapis.com"}
    )
    
    $enabledCount = 0
    $totalAPIs = $requiredAPIs.Count
    
    foreach ($api in $requiredAPIs) {
        try {
            Write-Info "Habilitando $($api.Name)..."
            gcloud services enable $api.Service --quiet
            Write-Success "✓ $($api.Name) habilitada"
            $enabledCount++
        } catch {
            Write-Error "Error habilitando $($api.Name): $($_.Exception.Message)"
        }
    }
    
    Write-Success "APIs habilitadas: $enabledCount/$totalAPIs"
    
    if ($enabledCount -eq $totalAPIs) {
        Write-Success "Todas las APIs fueron habilitadas exitosamente"
        return $true
    } else {
        Write-Warning "Algunas APIs no pudieron ser habilitadas"
        return $false
    }
}

# PASO 3: Configurar Billing y Alertas
function Step3-ConfigureBilling {
    Write-Step "PASO 3: Configurar Billing y Alertas"
    
    if ($SkipBilling) {
        Write-Warning "Configuración de billing omitida (parámetro -SkipBilling)"
        return $true
    }
    
    try {
        # Verificar si hay una cuenta de billing vinculada
        $billingAccount = gcloud beta billing projects describe $ProjectId --format="value(billingAccountName)" 2>$null
        
        if (-not $billingAccount) {
            Write-Warning "No hay cuenta de billing vinculada al proyecto"
            Write-Info "Debes vincular una cuenta de billing manualmente en:"
            Write-Info "https://console.cloud.google.com/billing/linkedaccount?project=$ProjectId"
            
            $continue = Read-Host "¿Has vinculado la cuenta de billing? (y/n)"
            if ($continue -ne "y" -and $continue -ne "Y") {
                Write-Warning "Configuración de billing pendiente"
                return $false
            }
        } else {
            Write-Success "Cuenta de billing vinculada: $billingAccount"
        }
        
        # Crear presupuesto (requiere API de billing habilitada)
        Write-Info "Configurando presupuesto de $BudgetAmount USD..."
        
        # Crear archivo de configuración de presupuesto
        $budgetConfig = @"
{
  "displayName": "Aviator Trading Budget",
  "budgetFilter": {
    "projects": ["projects/$ProjectId"]
  },
  "amount": {
    "specifiedAmount": {
      "currencyCode": "USD",
      "units": "$BudgetAmount"
    }
  },
  "thresholdRules": [
    {
      "thresholdPercent": 0.5,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.75,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.9,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 1.0,
      "spendBasis": "CURRENT_SPEND"
    }
  ]
}
"@
        
        $budgetFile = "$env:TEMP\aviator-budget.json"
        $budgetConfig | Out-File -FilePath $budgetFile -Encoding UTF8
        
        try {
            # Habilitar API de billing
            gcloud services enable cloudbilling.googleapis.com --quiet
            
            # Crear presupuesto
            gcloud beta billing budgets create --billing-account=$(gcloud beta billing projects describe $ProjectId --format="value(billingAccountName)" | Split-Path -Leaf) --budget-from-file=$budgetFile
            
            Write-Success "Presupuesto configurado: $BudgetAmount USD con alertas en 50%, 75%, 90%, 100%"
            
            # Limpiar archivo temporal
            Remove-Item $budgetFile -Force
            
        } catch {
            Write-Warning "No se pudo crear el presupuesto automáticamente"
            Write-Info "Configura manualmente en: https://console.cloud.google.com/billing/budgets?project=$ProjectId"
        }
        
        return $true
        
    } catch {
        Write-Error "Error en Paso 3: $($_.Exception.Message)"
        Write-Info "Configura billing manualmente en la consola de GCP"
        return $false
    }
}

# PASO 4: Crear Service Account
function Step4-CreateServiceAccount {
    Write-Step "PASO 4: Crear Service Account"
    
    try {
        $serviceAccountEmail = "$ServiceAccountName@$ProjectId.iam.gserviceaccount.com"
        
        # Verificar si ya existe
        $existingSA = gcloud iam service-accounts describe $serviceAccountEmail --format="value(email)" 2>$null
        
        if ($existingSA) {
            Write-Warning "Service Account ya existe: $serviceAccountEmail"
        } else {
            Write-Info "Creando Service Account: $ServiceAccountName"
            gcloud iam service-accounts create $ServiceAccountName `
                --display-name="Aviator Deployment Service Account" `
                --description="Service account for Aviator Trading deployment"
            
            Write-Success "Service Account creada: $serviceAccountEmail"
        }
        
        # Asignar roles necesarios
        $requiredRoles = @(
            "roles/compute.admin",
            "roles/cloudsql.admin",
            "roles/storage.admin",
            "roles/cloudbuild.builds.editor",
            "roles/monitoring.editor",
            "roles/secretmanager.admin",
            "roles/logging.admin",
            "roles/iam.serviceAccountUser"
        )
        
        Write-Info "Asignando roles..."
        foreach ($role in $requiredRoles) {
            try {
                gcloud projects add-iam-policy-binding $ProjectId `
                    --member="serviceAccount:$serviceAccountEmail" `
                    --role="$role" `
                    --quiet
                Write-Success "✓ Rol asignado: $role"
            } catch {
                Write-Warning "Error asignando rol $role"
            }
        }
        
        # Crear y descargar clave JSON
        $credentialsDir = Join-Path $PSScriptRoot "..\credentials"
        if (-not (Test-Path $credentialsDir)) {
            New-Item -ItemType Directory -Path $credentialsDir -Force | Out-Null
        }
        
        $credentialsFile = Join-Path $credentialsDir "aviator-gcp-credentials.json"
        
        Write-Info "Generando clave JSON..."
        gcloud iam service-accounts keys create $credentialsFile `
            --iam-account=$serviceAccountEmail
        
        Write-Success "Clave JSON descargada: $credentialsFile"
        Write-Info "IMPORTANTE: Guarda esta clave de forma segura y no la compartas"
        
        return @{
            Success = $true
            Email = $serviceAccountEmail
            KeyFile = $credentialsFile
        }
        
    } catch {
        Write-Error "Error en Paso 4: $($_.Exception.Message)"
        return @{ Success = $false }
    }
}

# PASO 5: Configurar Cloud Shell y Verificación
function Step5-ConfigureAndVerify {
    Write-Step "PASO 5: Configurar y Verificar Instalación"
    
    try {
        # Verificar configuración actual
        Write-Info "Verificando configuración actual..."
        
        $currentProject = gcloud config get-value project
        $currentRegion = gcloud config get-value compute/region
        $currentZone = gcloud config get-value compute/zone
        
        Write-Success "Proyecto activo: $currentProject"
        Write-Success "Región: $currentRegion"
        Write-Success "Zona: $currentZone"
        
        # Verificar APIs habilitadas
        Write-Info "Verificando APIs habilitadas..."
        $enabledServices = gcloud services list --enabled --format="value(name)"
        
        $criticalAPIs = @("compute", "sqladmin", "storage", "cloudbuild", "monitoring", "secretmanager")
        $enabledCritical = 0
        
        foreach ($api in $criticalAPIs) {
            if ($enabledServices -match $api) {
                Write-Success "✓ API $api habilitada"
                $enabledCritical++
            } else {
                Write-Warning "✗ API $api no encontrada"
            }
        }
        
        # Verificar Service Account
        Write-Info "Verificando Service Account..."
        $serviceAccountEmail = "$ServiceAccountName@$ProjectId.iam.gserviceaccount.com"
        $saExists = gcloud iam service-accounts describe $serviceAccountEmail --format="value(email)" 2>$null
        
        if ($saExists) {
            Write-Success "✓ Service Account verificada: $serviceAccountEmail"
        } else {
            Write-Warning "✗ Service Account no encontrada"
        }
        
        # Generar resumen de configuración
        $configSummary = @"

🎯 RESUMEN DE CONFIGURACIÓN COMPLETADA
================================================

📋 Proyecto GCP:
   ID: $ProjectId
   Región: $currentRegion
   Zona: $currentZone

🔌 APIs Críticas: $enabledCritical/$($criticalAPIs.Count) habilitadas

👤 Service Account: $serviceAccountEmail

📁 Archivos generados:
   - Credenciales: gcp/credentials/aviator-gcp-credentials.json
   - Configuración: .env.gcp (pendiente)

🌐 Enlaces útiles:
   - Consola GCP: https://console.cloud.google.com/home/dashboard?project=$ProjectId
   - Compute Engine: https://console.cloud.google.com/compute/instances?project=$ProjectId
   - Cloud SQL: https://console.cloud.google.com/sql/instances?project=$ProjectId
   - Storage: https://console.cloud.google.com/storage/browser?project=$ProjectId

"@
        
        Write-ColorOutput $configSummary "Cyan"
        
        return $true
        
    } catch {
        Write-Error "Error en Paso 5: $($_.Exception.Message)"
        return $false
    }
}

# Función principal
function Main {
    Write-ColorOutput "" "White"
    Write-ColorOutput "🚀 AUTOMATIZACIÓN DE CONFIGURACIÓN GCP - AVIATOR TRADING" "Cyan"
    Write-ColorOutput "================================================================" "Cyan"
    Write-ColorOutput "Proyecto: $ProjectId" "White"
    Write-ColorOutput "Región: $Region" "White"
    Write-ColorOutput "Presupuesto: $BudgetAmount USD" "White"
    Write-ColorOutput "================================================================" "Cyan"
    Write-ColorOutput "" "White"
    
    # Verificar prerequisitos
    if (-not (Test-Prerequisites)) {
        Write-Error "No se pueden cumplir los prerequisitos. Abortando."
        exit 1
    }
    
    $steps = @(
        @{Name="Crear Proyecto"; Function={Step1-CreateProject}},
        @{Name="Habilitar APIs"; Function={Step2-EnableAPIs}},
        @{Name="Configurar Billing"; Function={Step3-ConfigureBilling}},
        @{Name="Crear Service Account"; Function={Step4-CreateServiceAccount}},
        @{Name="Verificar Configuración"; Function={Step5-ConfigureAndVerify}}
    )
    
    $completedSteps = 0
    $totalSteps = $steps.Count
    
    foreach ($step in $steps) {
        Write-ColorOutput "" "White"
        Write-ColorOutput "▶️ Ejecutando: $($step.Name)" "Yellow"
        Write-ColorOutput "" "White"
        
        try {
            $result = & $step.Function
            if ($result) {
                $completedSteps++
                Write-Success "✅ $($step.Name) completado exitosamente"
            } else {
                Write-Warning "⚠️ $($step.Name) completado con advertencias"
            }
        } catch {
            Write-Error "❌ Error en $($step.Name): $($_.Exception.Message)"
            
            $continue = Read-Host "¿Continuar con los siguientes pasos? (y/n)"
            if ($continue -ne "y" -and $continue -ne "Y") {
                Write-Error "Proceso abortado por el usuario"
                exit 1
            }
        }
    }
    
    Write-ColorOutput "" "White"
    Write-ColorOutput "🎉 CONFIGURACIÓN COMPLETADA" "Green"
    Write-ColorOutput "================================================================" "Green"
    Write-ColorOutput "Pasos completados: $completedSteps/$totalSteps" "White"
    Write-ColorOutput "" "White"
    
    if ($completedSteps -eq $totalSteps) {
        Write-Success "¡Todos los pasos fueron completados exitosamente!"
        Write-Info "Próximos pasos:"
        Write-Info "1. Ejecutar: .\deploy.ps1 -ProjectId $ProjectId"
        Write-Info "2. Configurar base de datos con: .\migrate-database.ps1"
        Write-Info "3. Desplegar aplicación"
    } else {
        Write-Warning "Algunos pasos requieren atención manual"
        Write-Info "Revisa los mensajes anteriores y completa la configuración"
    }
    
    Write-ColorOutput "" "White"
}

# Ejecutar script principal
if ($MyInvocation.InvocationName -ne '.') {
    Main
}