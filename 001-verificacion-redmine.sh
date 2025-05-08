#!/bin/bash

# Script de Verificación para la Instalación de Redmine con Puma y PostgreSQL
# Nombre del archivo: verificaion-redmine.sh

# --- Variables de Configuración (deben coincidir con las usadas en la instalación) ---
REDMINE_DB_USER="h-debian"
REDMINE_DB_NAME="redmine"
REDMINE_INSTALL_DIR="/var/www/redmine-5.0"

# --- Colores para la Salida ---
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}--- INICIO DE VERIFICACIÓN DE REDMINE ---${NC}"

# --- 1. Verificación de Archivos de Configuración de Redmine/Puma (con cat) ---
echo -e "\n${YELLOW}=== 1. ARCHIVOS DE CONFIGURACIÓN ===${NC}"

echo -e "\n${BLUE}[INFO] Verificando: ${REDMINE_INSTALL_DIR}/config/database.yml${NC}"
if [ -f "${REDMINE_INSTALL_DIR}/config/database.yml" ]; then
    sudo cat "${REDMINE_INSTALL_DIR}/config/database.yml"
else
    echo -e "${RED}[ERROR] Archivo ${REDMINE_INSTALL_DIR}/config/database.yml NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando: ${REDMINE_INSTALL_DIR}/.bundle/config${NC}"
if [ -f "${REDMINE_INSTALL_DIR}/.bundle/config" ]; then
    sudo cat "${REDMINE_INSTALL_DIR}/.bundle/config"
else
    echo -e "${RED}[ERROR] Archivo ${REDMINE_INSTALL_DIR}/.bundle/config NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando: ${REDMINE_INSTALL_DIR}/config/initializers/secret_token.rb${NC}"
if [ -f "${REDMINE_INSTALL_DIR}/config/initializers/secret_token.rb" ]; then
    sudo cat "${REDMINE_INSTALL_DIR}/config/initializers/secret_token.rb"
else
    echo -e "${RED}[ERROR] Archivo ${REDMINE_INSTALL_DIR}/config/initializers/secret_token.rb NO ENCONTRADO.${NC}"
    echo -e "${YELLOW}[NOTA] Redmine 5+ podría usar config/credentials.yml.enc o secrets.yml en lugar de este archivo explícito.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando: ${REDMINE_INSTALL_DIR}/config/puma.rb${NC}"
if [ -f "${REDMINE_INSTALL_DIR}/config/puma.rb" ]; then
    sudo cat "${REDMINE_INSTALL_DIR}/config/puma.rb"
else
    echo -e "${RED}[ERROR] Archivo ${REDMINE_INSTALL_DIR}/config/puma.rb NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando: /etc/systemd/system/redmine_puma.service${NC}"
if [ -f "/etc/systemd/system/redmine_puma.service" ]; then
    sudo cat "/etc/systemd/system/redmine_puma.service"
else
    echo -e "${RED}[ERROR] Archivo /etc/systemd/system/redmine_puma.service NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando: ${REDMINE_INSTALL_DIR}/Gemfile (primeras y últimas 15 líneas)${NC}"
if [ -f "${REDMINE_INSTALL_DIR}/Gemfile" ]; then
    echo -e "${GREEN}--- Inicio de Gemfile ---${NC}"
    head -n 15 "${REDMINE_INSTALL_DIR}/Gemfile"
    echo -e "${GREEN}--- ... (contenido omitido) ... ---${NC}"
    echo -e "${GREEN}--- Final de Gemfile ---${NC}"
    tail -n 15 "${REDMINE_INSTALL_DIR}/Gemfile"
else
    echo -e "${RED}[ERROR] Archivo ${REDMINE_INSTALL_DIR}/Gemfile NO ENCONTRADO.${NC}"
fi

# --- 2. Verificación de Directorios y Permisos (con ls -ahl) ---
echo -e "\n${YELLOW}=== 2. DIRECTORIOS Y PERMISOS ===${NC}"

echo -e "\n${BLUE}[INFO] Verificando directorio raíz de Redmine: ${REDMINE_INSTALL_DIR}/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de configuración: ${REDMINE_INSTALL_DIR}/config/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/config" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/config/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/config/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de logs: ${REDMINE_INSTALL_DIR}/log/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/log" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/log/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/log/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio temporal y PID de Puma: ${REDMINE_INSTALL_DIR}/tmp/pids/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/tmp/pids" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/tmp/pids/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/tmp/pids/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de archivos adjuntos: ${REDMINE_INSTALL_DIR}/files/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/files" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/files/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/files/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio público: ${REDMINE_INSTALL_DIR}/public/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/public" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/public/"
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/public/ NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de Git: ${REDMINE_INSTALL_DIR}/.git/ (primeras 10 líneas)${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/.git" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/.git/" | head -n 10 && echo "..."
else
    echo -e "${RED}[ERROR] Directorio ${REDMINE_INSTALL_DIR}/.git/ NO ENCONTRADO (¿Redmine no fue clonado con Git?).${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de gemas locales (si existe): ${REDMINE_INSTALL_DIR}/vendor/bundle/${NC}"
if [ -d "${REDMINE_INSTALL_DIR}/vendor/bundle" ]; then
    sudo ls -ahl "${REDMINE_INSTALL_DIR}/vendor/bundle/"
    # Intentar listar el subdirectorio de Ruby (la versión puede cambiar)
    RUBY_GEM_PATH=$(sudo find "${REDMINE_INSTALL_DIR}/vendor/bundle/ruby/" -maxdepth 1 -type d -name "[0-9]*.[0-9]*" | head -n 1)
    if [ -n "$RUBY_GEM_PATH" ] && [ -d "$RUBY_GEM_PATH/bin" ]; then
        echo -e "\n${BLUE}[INFO] Verificando binarios de gemas en: $RUBY_GEM_PATH/bin/${NC}"
        sudo ls -ahl "$RUBY_GEM_PATH/bin/"
    else
        echo -e "${YELLOW}[AVISO] No se encontró un subdirectorio de versión de Ruby o el directorio 'bin' en vendor/bundle.${NC}"
    fi
else
    echo -e "${YELLOW}[AVISO] Directorio ${REDMINE_INSTALL_DIR}/vendor/bundle/ NO ENCONTRADO (¿Las gemas se instalaron globalmente?).${NC}"
fi

# --- 3. Verificación de Directorios de PostgreSQL ---
echo -e "\n${YELLOW}=== 3. DIRECTORIOS DE POSTGRESQL ===${NC}"
# Intentar detectar la versión de PostgreSQL instalada
PG_VERSION_DIR=$(ls -d /etc/postgresql/[0-9]* 2>/dev/null | head -n 1)

if [ -n "$PG_VERSION_DIR" ]; then
    PG_VERSION=$(basename "$PG_VERSION_DIR")
    echo -e "${BLUE}[INFO] PostgreSQL versión detectada: ${PG_VERSION}${NC}"

    echo -e "\n${BLUE}[INFO] Verificando directorio de configuración de PostgreSQL: /etc/postgresql/${PG_VERSION}/main/${NC}"
    if [ -d "/etc/postgresql/${PG_VERSION}/main" ]; then
        sudo ls -ahl "/etc/postgresql/${PG_VERSION}/main/"
    else
        echo -e "${RED}[ERROR] Directorio /etc/postgresql/${PG_VERSION}/main/ NO ENCONTRADO.${NC}"
    fi

    echo -e "\n${BLUE}[INFO] Verificando directorio de datos de PostgreSQL: /var/lib/postgresql/${PG_VERSION}/main/${NC}"
    if [ -d "/var/lib/postgresql/${PG_VERSION}/main" ]; then
        sudo ls -ahl "/var/lib/postgresql/${PG_VERSION}/main/"
    else
        echo -e "${RED}[ERROR] Directorio /var/lib/postgresql/${PG_VERSION}/main/ NO ENCONTRADO.${NC}"
    fi
else
    echo -e "${YELLOW}[AVISO] No se pudo detectar automáticamente la versión/directorio de PostgreSQL en /etc/postgresql.${NC}"
    echo -e "${YELLOW}Verifica manualmente: 'ls -ahl /etc/postgresql/' y 'ls -ahl /var/lib/postgresql/'${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando directorio de logs de PostgreSQL: /var/log/postgresql/${NC}"
if [ -d "/var/log/postgresql" ]; then
    sudo ls -ahl "/var/log/postgresql/"
else
    echo -e "${RED}[ERROR] Directorio /var/log/postgresql/ NO ENCONTRADO.${NC}"
fi

# --- 4. Verificación de Estado de Servicios y Herramientas ---
echo -e "\n${YELLOW}=== 4. ESTADO DE SERVICIOS Y HERRAMIENTAS ===${NC}"

echo -e "\n${BLUE}[INFO] Verificando estado del servicio PostgreSQL...${NC}"
if systemctl list-units --full -all | grep -q 'postgresql.service'; then
    sudo systemctl status postgresql.service --no-pager || echo -e "${RED}[ERROR] No se pudo obtener el estado de PostgreSQL.${NC}"
else
    echo -e "${RED}[ERROR] Servicio postgresql.service no parece estar instalado/disponible.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando estado del servicio Puma para Redmine...${NC}"
if systemctl list-units --full -all | grep -q 'redmine_puma.service'; then
    sudo systemctl status redmine_puma.service --no-pager || echo -e "${RED}[ERROR] No se pudo obtener el estado de redmine_puma.service.${NC}"
else
    echo -e "${RED}[ERROR] Servicio redmine_puma.service no parece estar instalado/disponible.${NC}"
fi

echo -e "\n${BLUE}[INFO] Buscando procesos Puma...${NC}"
if ps aux | grep puma | grep -v grep; then
    echo -e "${GREEN}[OK] Procesos Puma encontrados.${NC}"
else
    echo -e "${YELLOW}[AVISO] No se encontraron procesos Puma en ejecución.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando si Puma escucha en el puerto 3000 (localhost)...${NC}"
if sudo netstat -tulnp | grep ':3000.*LISTEN'; then
    echo -e "${GREEN}[OK] Algo está escuchando en el puerto 3000.${NC}"
    sudo netstat -tulnp | grep ':3000.*LISTEN'
else
    echo -e "${YELLOW}[AVISO] Nada parece estar escuchando en el puerto 3000.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando versión de Ruby...${NC}"
if command -v ruby >/dev/null 2>&1; then
    ruby --version
    echo "Ruta de ruby: $(which ruby)"
else
    echo -e "${RED}[ERROR] Ruby no encontrado en el PATH.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando versión de gem...${NC}"
if command -v gem >/dev/null 2>&1; then
    gem --version
    echo "Ruta de gem: $(which gem)"
else
    echo -e "${RED}[ERROR] gem no encontrado en el PATH.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando versión de Bundler...${NC}"
if command -v bundle >/dev/null 2>&1; then
    bundle --version
    echo "Ruta de bundle: $(which bundle)"
else
    if [ -f "/usr/local/bin/bundle" ]; then
        /usr/local/bin/bundle --version
        echo "Ruta de bundle: /usr/local/bin/bundle"
    else
        echo -e "${RED}[ERROR] Bundler no encontrado en el PATH ni en /usr/local/bin/bundle.${NC}"
    fi
fi

echo -e "\n${BLUE}[INFO] Verificando versión de Git...${NC}"
if command -v git >/dev/null 2>&1; then
    git --version
    echo "Ruta de git: $(which git)"
else
    echo -e "${RED}[ERROR] Git no encontrado en el PATH.${NC}"
fi

# --- 4.5 Verificación de Uso de Recursos (CPU, RAM, I/O, Red) ---
echo -e "\n${YELLOW}=== 4.5 USO DE RECURSOS (CPU, RAM, I/O, RED) ===${NC}"

# --- CPU y RAM con ps ---
echo -e "\n${BLUE}[INFO] Verificando uso de CPU y RAM para procesos relacionados con Redmine (Puma/PostgreSQL)...${NC}"
echo -e "${GREEN}--- Procesos más relevantes (top 5 por uso de CPU) ---${NC}"
ps aux --sort=-%cpu | grep -E 'puma|postgres|ruby' | head -n 5 || echo -e "${YELLOW}[AVISO] No se encontraron procesos Puma/PostgreSQL en ejecución.${NC}"
echo -e "${YELLOW}Ejecuta 'top' o 'htop' manualmente para monitoreo interactivo.${NC}"

# --- I/O con iotop (requiere instalación: sudo apt install iotop) ---
echo -e "\n${BLUE}[INFO] Verificando uso de I/O (requiere iotop instalado)...${NC}"
if command -v iotop >/dev/null 2>&1; then
    echo -e "${GREEN}--- Procesos con mayor I/O (muestra instantánea) ---${NC}"
    sudo iotop -b -n 1 -o | grep -E 'puma|postgres|ruby' || echo -e "${YELLOW}[AVISO] No se encontraron procesos Puma/PostgreSQL con actividad de I/O significativa.${NC}"
else
    echo -e "${YELLOW}[AVISO] iotop no está instalado. Instálalo con: sudo apt install iotop${NC}"
    echo -e "${YELLOW}Alternativa: Usa 'iostat' (sudo apt install sysstat) o revisa manualmente con 'sudo iotop'.${NC}"
fi

# --- I/O con iostat (requiere instalación: sudo apt install sysstat) ---
echo -e "\n${BLUE}[INFO] Verificando estadísticas generales de I/O con iostat...${NC}"
if command -v iostat >/dev/null 2>&1; then
    sudo iostat -x 1 2 | tail -n +3 || echo -e "${YELLOW}[AVISO] Error al ejecutar iostat.${NC}"
else
    echo -e "${YELLOW}[AVISO] iostat no está instalado. Instálalo con: sudo apt install sysstat${NC}"
fi

# --- Red (Rx/Tx) con nload (requiere instalación: sudo apt install nload) ---
echo -e "\n${BLUE}[INFO] Verificando uso de red (Rx/Tx) con nload (si está instalado)...${NC}"
if command -v nload >/dev/null 2>&1; then
    echo -e "${GREEN}--- Estadísticas de red (muestra instantánea para la interfaz principal) ---${NC}"
    sudo nload -t 2000 -u H eth0 | head -n 10 || echo -e "${YELLOW}[AVISO] Error al ejecutar nload o interfaz no válida.${NC}"
    echo -e "${YELLOW}Ejecuta 'nload' manualmente para monitoreo interactivo.${NC}"
else
    echo -e "${YELLOW}[AVISO] nload no está instalado. Instálalo con: sudo apt install nload${NC}"
    echo -e "${YELLOW}Alternativa: Usa 'iftop' (sudo apt install iftop) o 'iptraf' para monitoreo de red.${NC}"
fi

# --- Conexiones de red con ss (reemplazo moderno de netstat) ---
echo -e "\n${BLUE}[INFO] Verificando conexiones de red TCP/IP en el puerto 3000 (Puma) y 5432 (PostgreSQL)...${NC}"
if command -v ss >/dev/null 2>&1; then
    sudo ss -tulnp | grep -E ':3000|:5432' || echo -e "${YELLOW}[AVISO] No se encontraron conexiones en los puertos 3000 o 5432.${NC}"
else
    echo -e "${YELLOW}[AVISO] ss no está instalado. Usa netstat como alternativa.${NC}"
    if command -v netstat >/dev/null 2>&1; then
        sudo netstat -tulnp | grep -E ':3000|:5432' || echo -e "${YELLOW}[AVISO] No se encontraron conexiones en los puertos 3000 o 5432.${NC}"
    else
        echo -e "${YELLOW}[AVISO] netstat no está instalado. Instálalo con: sudo apt install net-tools${NC}"
    fi
fi

# --- 5. Prueba de Acceso Básico ---
echo -e "\n${YELLOW}=== 5. PRUEBA DE ACCESO BÁSICO ===${NC}"
echo -e "\n${BLUE}[INFO] Intentando acceder a Redmine en http://localhost:3000 con curl...${NC}"
if curl -sSf --head http://localhost:3000 > /dev/null; then
    echo -e "${GREEN}[OK] Redmine responde correctamente en http://localhost:3000 (código de cabecera OK).${NC}"
    echo -e "Respuesta de cabeceras:"
    curl -I http://localhost:3000
else
    echo -e "${RED}[ERROR] No se pudo conectar a Redmine en http://localhost:3000 o la respuesta no fue exitosa.${NC}"
    echo -e "${YELLOW}Posibles causas: Puma no iniciado, firewall bloqueando, errores en la aplicación Redmine.${NC}"
    echo -e "${YELLOW}Revisa: 'sudo systemctl status redmine_puma.service', 'sudo journalctl -xeu redmine_puma.service'${NC}"
    echo -e "${YELLOW}y los logs en '${REDMINE_INSTALL_DIR}/log/'.${NC}"
fi

echo -e "\n${BLUE}--- FIN DE VERIFICACIÓN ---${NC}"
