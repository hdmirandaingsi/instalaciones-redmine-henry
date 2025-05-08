#!/bin/bash
set -e # Salir inmediatamente si un comando falla, aunque lo manejaremos con || true en algunos casos.

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

echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${RED}!!! ADVERTENCIA: ESTE SCRIPT REALIZARÁ UNA DESINSTALACIÓN COMPLETA   !!!${NC}"
echo -e "${RED}!!! DE REDMINE, PUMA, POSTGRESQL, RUBY, GIT Y SUS DATOS ASOCIADOS.  !!!${NC}"
echo -e "${RED}!!! ESTA ACCIÓN ES DESTRUCTIVA Y NO SE PUEDE DESHACER FÁCILMENTE.   !!!${NC}"
echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${YELLOW}Por favor, escribe 'SI, ESTOY SEGURO DE DESINSTALAR TODO' para continuar:${NC}"
read -r CONFIRMATION

if [ "$CONFIRMATION" != "SI, ESTOY SEGURO DE DESINSTALAR TODO" ]; then
    echo -e "${BLUE}[INFO] Desinstalación cancelada por el usuario.${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Iniciando el script de desinstalación completa...${NC}"

# --- PASO 1: Detener y Deshabilitar Servicios ---
echo -e "\n${BLUE}[INFO] Paso 1: Deteniendo y deshabilitando servicios...${NC}"

# Detener y deshabilitar el servicio Puma de Redmine
if systemctl list-units --full -all | grep -q 'redmine_puma.service'; then
    echo -e "${YELLOW}Deteniendo redmine_puma.service...${NC}"
    sudo systemctl stop redmine_puma.service || echo -e "${YELLOW}[AVISO] No se pudo detener redmine_puma.service (quizás ya estaba detenido).${NC}"
    echo -e "${YELLOW}Deshabilitando redmine_puma.service...${NC}"
    sudo systemctl disable redmine_puma.service || echo -e "${YELLOW}[AVISO] No se pudo deshabilitar redmine_puma.service.${NC}"
    echo -e "${YELLOW}Eliminando archivo de servicio /etc/systemd/system/redmine_puma.service...${NC}"
    sudo rm -f /etc/systemd/system/redmine_puma.service
    sudo systemctl daemon-reload
    echo -e "${GREEN}[OK] Servicio Redmine Puma detenido, deshabilitado y archivo eliminado.${NC}"
else
    echo -e "${YELLOW}[AVISO] Servicio redmine_puma.service no encontrado.${NC}"
fi

# Detener PostgreSQL
# (No se deshabilita aquí porque 'apt purge' lo hará si está gestionado por systemd y el paquete se elimina)
if systemctl list-units --full -all | grep -q 'postgresql.service'; then
    echo -e "${YELLOW}Deteniendo postgresql.service...${NC}"
    sudo systemctl stop postgresql.service || echo -e "${YELLOW}[AVISO] No se pudo detener postgresql.service (quizás ya estaba detenido).${NC}"
    echo -e "${GREEN}[OK] Servicio PostgreSQL detenido.${NC}"
else
    echo -e "${YELLOW}[AVISO] Servicio postgresql.service no encontrado.${NC}"
fi

# --- PASO 2: Eliminar Base de Datos y Usuario de Redmine en PostgreSQL ---
# Esto se hace ANTES de purgar PostgreSQL para asegurar que los comandos psql funcionen.
echo -e "\n${BLUE}[INFO] Paso 2: Eliminando base de datos y usuario de Redmine en PostgreSQL...${NC}"
# Comprobar si psql está disponible antes de intentar usarlo
if command -v psql >/dev/null 2>&1; then
    echo -e "${YELLOW}Intentando eliminar la base de datos '${REDMINE_DB_NAME}'...${NC}"
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${REDMINE_DB_NAME};" \
        || echo -e "${YELLOW}[AVISO] Falló la eliminación de la base de datos '${REDMINE_DB_NAME}' (puede que no exista o haya conexiones activas).${NC}"

    echo -e "${YELLOW}Intentando eliminar el usuario '${REDMINE_DB_USER}'...${NC}"
    sudo -u postgres psql -c "DROP USER IF EXISTS \"${REDMINE_DB_USER}\";" \
        || echo -e "${YELLOW}[AVISO] Falló la eliminación del usuario '${REDMINE_DB_USER}' (puede que no exista).${NC}"
    echo -e "${GREEN}[OK] Intento de eliminación de base de datos y usuario de Redmine completado.${NC}"
else
    echo -e "${YELLOW}[AVISO] Comando 'psql' no encontrado. Omitiendo eliminación de BD/usuario de Redmine vía psql.${NC}"
    echo -e "${YELLOW}La purga de PostgreSQL debería eliminar todos los datos si se hace correctamente.${NC}"
fi


# --- PASO 3: Purgar Paquetes de Software ---
echo -e "\n${BLUE}[INFO] Paso 3: Purgando paquetes de software (PostgreSQL, Ruby, Git, etc.)...${NC}"

# Purgar PostgreSQL
echo -e "${YELLOW}Purgando paquetes de PostgreSQL...${NC}"
sudo apt purge -y postgresql\* libpq-dev\* pgdg-keyring\* || echo -e "${YELLOW}[AVISO] Error al purgar PostgreSQL (algunos paquetes podrían no existir).${NC}"
# Eliminar archivos de configuración y datos residuales de PostgreSQL
echo -e "${YELLOW}Eliminando directorios de configuración y datos de PostgreSQL...${NC}"
sudo rm -rf /etc/postgresql/ /etc/postgresql-common/ /var/lib/postgresql/
echo -e "${GREEN}[OK] Intento de purga de PostgreSQL y eliminación de directorios completado.${NC}"

# Purgar Ruby y Bundler (gemas)
echo -e "${YELLOW}Purgando paquetes de Ruby y eliminando gemas...${NC}"
sudo apt purge -y ruby\* libruby\* ruby-dev\* build-essential\* || echo -e "${YELLOW}[AVISO] Error al purgar Ruby (algunos paquetes podrían no existir).${NC}"
# Intentar desinstalar Bundler si fue instalado con gem
if command -v gem >/dev/null 2>&1; then
    echo -e "${YELLOW}Intentando desinstalar la gema Bundler globalmente...${NC}"
    sudo gem uninstall bundler --all --executables --force || echo -e "${YELLOW}[AVISO] No se pudo desinstalar la gema Bundler (quizás no estaba instalada).${NC}"
    # Limpiar directorios de gemas si es posible (esto es delicado y depende de cómo se instaló Ruby)
    # Comentar/descomentar con precaución. Ejemplo para Ruby de apt:
    # RUBY_GEM_DIR_APT=$(gem environment gemdir 2>/dev/null)
    # if [ -n "$RUBY_GEM_DIR_APT" ] && [ "$RUBY_GEM_DIR_APT" != "/usr/local/lib/ruby/gems" ]; then # Evitar rutas muy genéricas por si acaso
    #    echo -e "${YELLOW}Eliminando directorio de gemas de sistema: ${RUBY_GEM_DIR_APT}...${NC}"
    #    # sudo rm -rf "$RUBY_GEM_DIR_APT" # MUY AGRESIVO, DESCOMENTAR CON CUIDADO
    # fi
fi
echo -e "${GREEN}[OK] Intento de purga de Ruby y Bundler completado.${NC}"

# Purgar Git
echo -e "${YELLOW}Purgando Git...${NC}"
sudo apt purge -y git\* || echo -e "${YELLOW}[AVISO] Error al purgar Git (quizás no estaba instalado).${NC}"
echo -e "${GREEN}[OK] Intento de purga de Git completado.${NC}"

# Purgar otras dependencias instaladas para Redmine
echo -e "${YELLOW}Purgando otras dependencias (ImageMagick, libxml2, etc.)...${NC}"
sudo apt purge -y imagemagick\* libmagickwand-dev\* libxml2-dev\* libxslt1-dev\* zlib1g-dev\* \
                    ufw\* net-tools\* curl\* wget\* gnupg2\* lsb-release\* software-properties-common\* \
                    || echo -e "${YELLOW}[AVISO] Error al purgar otras dependencias (algunos paquetes podrían no existir).${NC}"
echo -e "${GREEN}[OK] Intento de purga de otras dependencias completado.${NC}"


# --- PASO 4: Limpieza del Sistema de Paquetes ---
echo -e "\n${BLUE}[INFO] Paso 4: Limpiando sistema de paquetes (autoremove, clean)...${NC}"
sudo apt autoremove -y || echo -e "${YELLOW}[AVISO] 'apt autoremove' encontró problemas o no había nada que eliminar.${NC}"
sudo apt clean || echo -e "${YELLOW}[AVISO] 'apt clean' encontró problemas.${NC}"
echo -e "${GREEN}[OK] Sistema de paquetes limpiado.${NC}"

# --- PASO 5: Eliminar Archivos y Directorios de Redmine ---
echo -e "\n${BLUE}[INFO] Paso 5: Eliminando archivos y directorios de Redmine...${NC}"

if [ -d "${REDMINE_INSTALL_DIR}" ]; then
    echo -e "${YELLOW}Eliminando el directorio de instalación de Redmine: ${REDMINE_INSTALL_DIR}...${NC}"
    sudo rm -rf "${REDMINE_INSTALL_DIR}"
    echo -e "${GREEN}[OK] Directorio ${REDMINE_INSTALL_DIR} eliminado.${NC}"
else
    echo -e "${YELLOW}[AVISO] El directorio ${REDMINE_INSTALL_DIR} no existe.${NC}"
fi

# Eliminar el directorio /var/www si está vacío y fue creado por el script
if [ -d "/var/www" ] && [ -z "$(ls -A /var/www)" ]; then
    echo -e "${YELLOW}Eliminando directorio /var/www (si está vacío)...${NC}"
    sudo rmdir /var/www || echo -e "${YELLOW}[AVISO] No se pudo eliminar /var/www (quizás no está vacío o no existe).${NC}"
fi


# --- PASO 6: Limpiar Logs y Archivos de Configuración Residuales (Opcional y Agresivo) ---
echo -e "\n${BLUE}[INFO] Paso 6: Buscando y eliminando archivos de configuración residuales y logs...${NC}"

# Logs de PostgreSQL (si 'apt purge' no los eliminó completamente)
echo -e "${YELLOW}Eliminando logs residuales de PostgreSQL en /var/log/postgresql/...${NC}"
sudo rm -rf /var/log/postgresql/
echo -e "${GREEN}[OK] Intento de eliminación de logs de PostgreSQL completado.${NC}"

# Archivos de usuario relacionados con Ruby (ej: .gem, .bundle en $HOME)
# ¡¡¡MUY AGRESIVO SI EL USUARIO USA RUBY PARA OTRAS COSAS!!!
# Por seguridad, esto está comentado. Descomentar y adaptar con extremo cuidado.
# TARGET_USER_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
# if [ -n "$TARGET_USER_HOME" ]; then
#     echo -e "${YELLOW}Eliminando configuraciones de Ruby del HOME del usuario ($TARGET_USER_HOME)... (COMENTADO POR SEGURIDAD)${NC}"
#     # sudo rm -rf "${TARGET_USER_HOME}/.gem"
#     # sudo rm -rf "${TARGET_USER_HOME}/.bundle"
# else
#     echo -e "${YELLOW}[AVISO] No se pudo determinar el directorio HOME del usuario para limpiar configs de Ruby.${NC}"
# fi


# --- PASO 7: Verificar Eliminación (Manual) ---
echo -e "\n${BLUE}[INFO] Paso 7: Verificación (se recomienda revisión manual adicional)...${NC}"
echo -e "${YELLOW}Comprobando si los directorios principales existen:${NC}"
echo -n "Directorio Redmine (${REDMINE_INSTALL_DIR}): "
[ -d "${REDMINE_INSTALL_DIR}" ] && echo -e "${RED}EXISTE${NC}" || echo -e "${GREEN}NO EXISTE${NC}"
echo -n "Directorio /etc/postgresql/: "
[ -d "/etc/postgresql/" ] && echo -e "${RED}EXISTE${NC}" || echo -e "${GREEN}NO EXISTE${NC}"
echo -n "Directorio /var/lib/postgresql/: "
[ -d "/var/lib/postgresql/" ] && echo -e "${RED}EXISTE${NC}" || echo -e "${GREEN}NO EXISTE${NC}"

echo -e "\n${YELLOW}Comprobando si los comandos principales existen:${NC}"
for cmd in psql ruby gem bundle git redmine_puma.service; do
    echo -n "Comando/Servicio '$cmd': "
    if [[ "$cmd" == *.service ]]; then
        systemctl list-units --full -all | grep -q "$cmd" && echo -e "${RED}SERVICIO EXISTE${NC}" || echo -e "${GREEN}SERVICIO NO EXISTE${NC}"
    else
        command -v "$cmd" >/dev/null 2>&1 && echo -e "${RED}COMANDO EXISTE ($(command -v "$cmd"))${NC}" || echo -e "${GREEN}COMANDO NO EXISTE${NC}"
    fi
done

echo -e "\n${GREEN}--- DESINSTALACIÓN COMPLETADA (o intentada) ---${NC}"
echo -e "${YELLOW}Se recomienda reiniciar el sistema para asegurar que todos los servicios y procesos se han detenido completamente.${NC}"
echo -e "${YELLOW}Por favor, revisa manualmente si quedan archivos o configuraciones no deseadas.${NC}"
