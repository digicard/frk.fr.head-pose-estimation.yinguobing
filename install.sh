#!/bin/bash

# Crear directorio de logs
LOGDIR="install_logs"
mkdir -p $LOGDIR
LOGFILE="$LOGDIR/install_$(date +%Y%m%d_%H%M%S).log"
echo "Todos los logs se guardarán en $LOGFILE"

# Función para registrar mensajes en el log
log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" | tee -a "$LOGFILE"
}

# Función para manejar errores
handle_error() {
    log "ERROR: $1"
    log "Revisa el archivo de log $LOGFILE para más detalles"
    exit 1
}

log "Iniciando instalación"

# Verificar que pyenv está instalado
if ! command -v pyenv &> /dev/null; then
    handle_error "pyenv no está instalado. Por favor, instálalo primero."
fi
log "pyenv está instalado correctamente"

# Verificar la versión de Python actual
log "Versión de Python del sistema: $(python --version 2>&1)"

# Verificar que la versión de Python solicitada está disponible
if ! pyenv versions | grep -q "3.12.7"; then
    log "Python 3.12.7 no está instalado. Intentando instalarlo..."
    pyenv install 3.12.7 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo instalar Python 3.12.7"
fi
log "Python 3.12.7 está disponible"

# Verificar si el entorno virtual ya existe y eliminarlo si es necesario
if pyenv virtualenvs | grep -q "hpe-yinguobing"; then
    log "El entorno virtual hpe-yinguobing ya existe. Recreándolo..."
    pyenv uninstall -f hpe-yinguobing 2>&1 | tee -a "$LOGFILE"
fi

# Crear entorno virtual
log "Creando entorno virtual hpe-yinguobing..."
pyenv virtualenv 3.12.7 hpe-yinguobing 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo crear el entorno virtual"

# Configurar el entorno local
log "Configurando entorno local..."
pyenv local hpe-yinguobing 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo configurar el entorno local"

# Activar el entorno virtual
log "Activando entorno virtual..."
. "${PYENV_ROOT}/versions/hpe-yinguobing/bin/activate" 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo activar el entorno virtual"

# Verificar entorno virtual activado
log "Entorno Python activo: $(which python)"
log "Versión de Python activa: $(python --version 2>&1)"
log "Sistema operativo: $(uname -a)"

# Instalar herramientas básicas de compilación para resolver problemas de dependencias
log "Instalando herramientas básicas para compilación..."
pip install --upgrade pip setuptools wheel cmake scikit-build 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo instalar herramientas básicas"

# Instalar dependencias principales con versiones compatibles con Python 3.12
log "Instalando numpy compatible con Python 3.12..."
pip install "numpy>=1.26.0" 2>&1 | tee -a "$LOGFILE" || handle_error "No se pudo instalar numpy"

# Instalación de dependencias sencillas primero
log "Instalando dependencias básicas..."
pip install coloredlogs==15.0.1 flatbuffers==23.5.26 humanfriendly==10.0 mpmath==1.3.0 packaging==23.1 protobuf==4.23.2 sympy==1.12 2>&1 | tee -a "$LOGFILE"

# Instalar OpenCV
log "Instalando OpenCV (última versión compatible)..."
if ! pip install "opencv-python>=4.8.0" 2>&1 | tee -a "$LOGFILE"; then
    log "Error al instalar opencv-python específico. Probando con versión genérica..."
    pip install opencv-python 2>&1 | tee -a "$LOGFILE" || log "ADVERTENCIA: No se pudo instalar opencv-python"
fi

# Manejar el caso especial de onnxruntime - uso de función para verificar éxito real
install_onnx() {
    log "Intentando instalar $1..."
    if pip install $1 2>&1 | tee -a "$LOGFILE"; then
        # Verificar que realmente se instaló comprobando si se puede importar
        if python -c "import $2" &>/dev/null; then
            log "$1 instalado y verificado correctamente"
            return 0
        else
            log "ADVERTENCIA: $1 parece instalado pero no se puede importar"
            return 1
        fi
    else
        log "No se pudo instalar $1"
        return 1
    fi
}

# Instalar onnxruntime con comprobación estricta
log "Instalando onnxruntime..."
# Primero intentamos la versión GPU
if ! install_onnx "onnxruntime-gpu" "onnxruntime"; then
    log "onnxruntime-gpu no disponible, intentando versión CPU..."
    # Si falla, intentamos la versión CPU
    if ! install_onnx "onnxruntime" "onnxruntime"; then
        # Si ambas fallan, intentamos versiones anteriores
        log "Intentando versiones anteriores de onnxruntime..."
        for version in 1.16.3 1.16.0 1.15.1 1.15.0 1.14.1; do
            log "Probando onnxruntime==$version"
            if install_onnx "onnxruntime==$version" "onnxruntime"; then
                break
            fi
        done
    fi
fi

# Crear un archivo con los paquetes instalados para referencia
pip freeze > "installed_packages.txt"
log "Lista de paquetes instalados guardada en installed_packages.txt"

# Verificar que se instalaron los paquetes críticos
log "Verificando instalación de paquetes críticos..."
python -c "import numpy; print('numpy', numpy.__version__)" 2>&1 | tee -a "$LOGFILE" || log "ERROR: numpy no está disponible"
python -c "import cv2; print('opencv-python', cv2.__version__)" 2>&1 | tee -a "$LOGFILE" || log "ERROR: opencv-python no está disponible"
python -c "import onnxruntime; print('onnxruntime', onnxruntime.__version__)" 2>&1 | tee -a "$LOGFILE" || log "ERROR: onnxruntime no está disponible"

# Comprobar si se han instalado todos los paquetes críticos
if python -c "import numpy, cv2, onnxruntime" &>/dev/null; then
    log "ÉXITO: Todos los paquetes críticos están instalados correctamente"
    echo "====================================================================="
    echo "✅ Instalación COMPLETADA con éxito. Todos los paquetes están listos."
    echo "====================================================================="
else
    log "ERROR: No todos los paquetes críticos están disponibles"
    echo "====================================================================="
    echo "⚠️ ADVERTENCIA: Algunos paquetes no se instalaron correctamente."
    echo "Revisa el archivo de log en $LOGFILE para detalles."
    echo "====================================================================="
fi

log "Instalación completada. Verifica el log para posibles errores: $LOGFILE"
echo "Revisa el archivo de log en $LOGFILE para detalles y posibles errores."