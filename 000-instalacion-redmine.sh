#!/bin/bash
set -e # Salir inmediatamente si un comando falla

# --- Variables de Configuración ---
REDMINE_DB_USER="h-debian"
REDMINE_DB_PASS="h-debian-p"
REDMINE_DB_NAME="redmine"
REDMINE_INSTALL_DIR="/var/www/redmine-5.0"
REDMINE_VERSION_BRANCH="5.0-stable"
PUMA_WORKERS=2
PUMA_MIN_THREADS=1
PUMA_MAX_THREADS=16
PUMA_GEM_SPEC=">= 5.6.4" # Especificación de la versión de Puma deseada

# --- Colores para la Salida ---
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}[INFO] Iniciando el script de instalación de Redmine ${REDMINE_VERSION_BRANCH} con PostgreSQL y Puma...${NC}"

# --- PASO 0: Preparación y Limpieza ---
echo -e "${BLUE}[INFO] Paso 0: Preparando el sistema...${NC}"
sudo apt update -y
sudo apt install -y curl wget gnupg2 lsb-release software-properties-common ca-certificates apt-transport-https dirmngr

# --- PASO 1: Instalación de Paquetes del Sistema ---
echo -e "${BLUE}[INFO] Paso 1: Instalando paquetes del sistema (PostgreSQL, Ruby, Git, dependencias)...${NC}"
sudo apt install -y postgresql postgresql-contrib libpq-dev \
                    ruby ruby-dev build-essential git \
                    imagemagick libmagickwand-dev \
                    libxml2-dev libxslt1-dev zlib1g-dev \
                    ufw net-tools
echo -e "${GREEN}[OK] Paquetes del sistema instalados.${NC}"

# --- PASO 2: Configuración de PostgreSQL ---
echo -e "${BLUE}[INFO] Paso 2: Configurando PostgreSQL...${NC}"
if ! sudo systemctl is-active --quiet postgresql; then
    echo -e "${YELLOW}[AVISO] PostgreSQL no está activo. Intentando iniciarlo...${NC}"
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    sleep 5
    if ! sudo systemctl is-active --quiet postgresql; then
        echo -e "${RED}[ERROR] No se pudo iniciar PostgreSQL. Revisa la instalación de PostgreSQL.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}[OK] PostgreSQL está activo.${NC}"

sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${REDMINE_DB_NAME};" \
    || echo -e "${YELLOW}[AVISO] No se pudo eliminar la base de datos ${REDMINE_DB_NAME} (puede que no existiera).${NC}"
sudo -u postgres psql -c "DROP USER IF EXISTS \"${REDMINE_DB_USER}\";" \
    || echo -e "${YELLOW}[AVISO] No se pudo eliminar el usuario ${REDMINE_DB_USER} (puede que no existiera).${NC}"

sudo -u postgres psql -c "CREATE USER \"${REDMINE_DB_USER}\" WITH PASSWORD '${REDMINE_DB_PASS}';"
sudo -u postgres psql -c "CREATE DATABASE ${REDMINE_DB_NAME} OWNER \"${REDMINE_DB_USER}\" ENCODING 'utf8';"
sudo -u postgres psql -d "${REDMINE_DB_NAME}" -c "GRANT CONNECT ON DATABASE ${REDMINE_DB_NAME} TO \"${REDMINE_DB_USER}\";"
sudo -u postgres psql -d "${REDMINE_DB_NAME}" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO \"${REDMINE_DB_USER}\";"
echo -e "${GREEN}[OK] Base de datos y usuario configurados en PostgreSQL.${NC}"

# --- PASO 3: Instalación y Configuración de Redmine ---
echo -e "${BLUE}[INFO] Paso 3: Descargando e instalando Redmine...${NC}"
sudo mkdir -p /var/www

if [ -d "${REDMINE_INSTALL_DIR}" ]; then
    echo -e "${YELLOW}[AVISO] El directorio ${REDMINE_INSTALL_DIR} ya existe. Eliminándolo para una instalación limpia...${NC}"
    sudo rm -rf "${REDMINE_INSTALL_DIR}"
fi
echo -e "${BLUE}[INFO] Clonando Redmine ${REDMINE_VERSION_BRANCH} en ${REDMINE_INSTALL_DIR}...${NC}"
sudo git clone --branch "${REDMINE_VERSION_BRANCH}" https://github.com/redmine/redmine.git "${REDMINE_INSTALL_DIR}"
echo -e "${GREEN}[OK] Redmine clonado.${NC}"

cd "${REDMINE_INSTALL_DIR}" # ¡IMPORTANTE! Moverse al directorio de Redmine aquí
echo -e "${BLUE}[INFO] Directorio actual: $(pwd)${NC}"


echo -e "${BLUE}[INFO] Creando directorios necesarios para Redmine y Puma...${NC}"
sudo mkdir -p tmp/pids tmp/sockets files log public/plugin_assets

echo -e "${BLUE}[INFO] Configurando ${REDMINE_INSTALL_DIR}/config/database.yml...${NC}"
sudo cp config/database.yml.example config/database.yml
sudo tee config/database.yml > /dev/null << EOF_DB
production:
  adapter: postgresql
  database: ${REDMINE_DB_NAME}
  host: localhost
  username: ${REDMINE_DB_USER}
  password: ${REDMINE_DB_PASS}
  encoding: utf8
EOF_DB
echo -e "${GREEN}[OK] config/database.yml configurado.${NC}"

# --- PASO 4: Modificación del Gemfile y Instalación de Dependencias (Gemas con Bundler) ---
echo -e "${BLUE}[INFO] Paso 4: Preparando Gemfile y instalando gemas de Ruby con Bundler...${NC}"

GEMFILE_PATH="Gemfile"
PUMA_TARGET_LINE="gem 'puma', '${PUMA_GEM_SPEC}'"
BACKUP_PATH="${GEMFILE_PATH}.backup_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "${GEMFILE_PATH}" ]; then
    echo -e "${RED}[ERROR] ${REDMINE_INSTALL_DIR}/${GEMFILE_PATH} no encontrado. La clonación de Redmine pudo haber fallado.${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Modificando ${GEMFILE_PATH} para asegurar la gema Puma correcta...${NC}"
echo -e "${BLUE}[INFO] Creando copia de respaldo: ${BACKUP_PATH}${NC}"
sudo cp "${GEMFILE_PATH}" "${BACKUP_PATH}"

echo -e "${BLUE}[INFO] Eliminando cualquier línea existente de 'gem puma'...${NC}"
sudo sed -i "/^[[:space:]]*gem[[:space:]]*['\"]puma['\"].*/d" "${GEMFILE_PATH}"

echo -e "${BLUE}[INFO] Añadiendo '${PUMA_TARGET_LINE}' después de 'gem bundler'...${NC}"
sudo sed -i "/^[[:space:]]*gem[[:space:]]*['\"]bundler['\"].*/a ${PUMA_TARGET_LINE}" "${GEMFILE_PATH}"

echo -e "${GREEN}[OK] Gemfile modificado. Verificando la línea de Puma:${NC}"
sudo grep "puma" "${GEMFILE_PATH}" || echo -e "${RED}[ERROR] Línea de Puma no encontrada después de la modificación.${NC}"

if ! command -v gem &> /dev/null; then
    echo -e "${RED}[ERROR] El comando 'gem' no se encuentra. Asegúrate de que Ruby esté instalado correctamente.${NC}"
    exit 1
fi
if ! gem spec bundler > /dev/null 2>&1; then
    echo -e "${BLUE}[INFO] Instalando Bundler gema...${NC}"
    sudo gem install bundler --no-document
    echo -e "${GREEN}[OK] Bundler instalado.${NC}"
else
    echo -e "${YELLOW}[AVISO] Bundler ya está instalado.${NC}"
fi

echo -e "${BLUE}[INFO] Configurando Bundler para instalar gemas en 'vendor/bundle' y omitir grupos no necesarios...${NC}"
sudo mkdir -p ".bundle"
sudo chown -R $(whoami):$(whoami) ".bundle"
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test mysql sqlite3'

echo -e "${BLUE}[INFO] Ejecutando 'bundle pristine' para asegurar una instalación limpia de gemas...${NC}"
sudo bundle pristine || echo -e "${YELLOW}[AVISO] 'bundle pristine' falló o no hizo nada, continuando...${NC}"

echo -e "${BLUE}[INFO] Ejecutando 'bundle install --jobs=$(nproc)'. Esto puede tardar varios minutos...${NC}"
BUNDLE_LOG_FILE="bundle_install.log"

if sudo sh -c "RAILS_ENV=production bundle install --jobs=$(nproc) --verbose > '${BUNDLE_LOG_FILE}' 2>&1"; then
    echo -e "${GREEN}[OK] Gemas instaladas.${NC}"
else
    echo -e "${RED}[ERROR] Falló la instalación de gemas con Bundler (código de salida $?).${NC}"
    if sudo test -f "${BUNDLE_LOG_FILE}"; then
        echo -e "${RED}Revise el archivo ${REDMINE_INSTALL_DIR}/${BUNDLE_LOG_FILE} para detalles:${NC}"
        sudo cat "${BUNDLE_LOG_FILE}"
    else
        echo -e "${RED}[ERROR] El archivo de log ${REDMINE_INSTALL_DIR}/${BUNDLE_LOG_FILE} NO FUE CREADO.${NC}"
    fi
    exit 1
fi

PUMA_BINSTUB_PATH_V1="vendor/bundle/bin/puma"
PUMA_BINSTUB_PATH_V2=$(sudo find "vendor/bundle/ruby/"*"/bin" -name puma -print -quit 2>/dev/null)

if sudo test -f "${PUMA_BINSTUB_PATH_V1}"; then
    echo -e "${GREEN}[OK] Ejecutable de Puma encontrado en ${REDMINE_INSTALL_DIR}/${PUMA_BINSTUB_PATH_V1}.${NC}"
elif [ -n "${PUMA_BINSTUB_PATH_V2}" ] && sudo test -f "${PUMA_BINSTUB_PATH_V2}"; then
    echo -e "${GREEN}[OK] Ejecutable de Puma encontrado en ${REDMINE_INSTALL_DIR}/${PUMA_BINSTUB_PATH_V2}.${NC}"
else
    echo -e "${RED}[ERROR CRITICO] El ejecutable de Puma NO se encontró en vendor/bundle después de 'bundle install'.${NC}"
    exit 1
fi

# --- PASO 5: Generación del Secreto del Almacén de Sesiones ---
echo -e "${BLUE}[INFO] Paso 5: Generando/configurando token secreto de Redmine...${NC}"
if ! sudo RAILS_ENV=production bundle exec rake generate_secret_token; then
    echo -e "${YELLOW}[AVISO] 'rake generate_secret_token' falló o no hizo nada. Verificando archivos de secretos alternativos...${NC}"
    if sudo test -f config/secrets.yml || sudo test -f config/credentials.yml.enc; then
        echo -e "${GREEN}[INFO] Se encontró config/secrets.yml o config/credentials.yml.enc. Se asume que el secreto está gestionado allí.${NC}"
    else
        echo -e "${RED}[ERROR CRITICO] 'rake generate_secret_token' falló y no se encontraron config/secrets.yml ni config/credentials.yml.enc. Saliendo.${NC}"
        exit 1;
    fi
else
    echo -e "${GREEN}[OK] Token secreto generado/configurado (o ya existía).${NC}"
fi

# --- PASO 6: Creación de Objetos del Esquema de Base de Datos ---
echo -e "${BLUE}[INFO] Paso 6: Ejecutando migraciones de base de datos...${NC}"
DB_MIGRATE_LOG_FILE="db_migrate.log"
# Corrección AQUÍ: Usar `sudo sh -c "comando > archivo"` para la redirección del log
if sudo sh -c "RAILS_ENV=production bundle exec rake db:migrate > '${DB_MIGRATE_LOG_FILE}' 2>&1"; then
    echo -e "${GREEN}[OK] Migraciones de base de datos ejecutadas.${NC}"
else
    echo -e "${RED}[ERROR] Fallaron las migraciones de base de datos (código de salida $?).${NC}"
    if sudo test -f "${DB_MIGRATE_LOG_FILE}"; then
        echo -e "${RED}Revise ${REDMINE_INSTALL_DIR}/${DB_MIGRATE_LOG_FILE}.${NC}"
        sudo cat "${DB_MIGRATE_LOG_FILE}"
    else
        echo -e "${RED}[ERROR] El archivo de log ${REDMINE_INSTALL_DIR}/${DB_MIGRATE_LOG_FILE} NO FUE CREADO.${NC}"
    fi
    exit 1
fi

# --- PASO 7: Conjunto de Datos Predeterminado de la Base de Datos ---
echo -e "${BLUE}[INFO] Paso 7: Cargando datos por defecto (Idioma: Inglés)...${NC}"
LOAD_DEFAULT_DATA_LOG_FILE="load_default_data.log"
# Corrección AQUÍ: Usar `sudo sh -c "comando > archivo"` para la redirección del log
# El '< /dev/null' es para evitar que rake pida entrada interactiva, debe ir dentro de sh -c
if sudo sh -c "RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data < /dev/null > '${LOAD_DEFAULT_DATA_LOG_FILE}' 2>&1"; then
    echo -e "${GREEN}[OK] Carga de datos por defecto completada (o ya existían).${NC}"
else
    echo -e "${YELLOW}[AVISO] Falló la carga de datos por defecto (puede ser normal si ya se ejecutó). Código de salida: $?.${NC}"
    if sudo test -f "${LOAD_DEFAULT_DATA_LOG_FILE}"; then
        echo -e "${YELLOW}Revise el archivo ${REDMINE_INSTALL_DIR}/${LOAD_DEFAULT_DATA_LOG_FILE} para detalles.${NC}"
        # sudo cat "${LOAD_DEFAULT_DATA_LOG_FILE}" # Descomentar si quieres ver el log siempre en este caso
    else
        echo -e "${YELLOW}[AVISO] El archivo de log ${REDMINE_INSTALL_DIR}/${LOAD_DEFAULT_DATA_LOG_FILE} NO FUE CREADO.${NC}"
    fi
fi

# --- PASO 8: Permisos del Sistema de Archivos ---
echo -e "${BLUE}[INFO] Paso 8: Ajustando permisos del directorio de Redmine para www-data...${NC}"
sudo chown -R www-data:www-data "${REDMINE_INSTALL_DIR}"

sudo find . -type d -exec chmod 755 {} \;
sudo find . -type f -exec chmod 644 {} \;

WRITABLE_DIRS_RELATIVE=( "files" "log" "tmp" "public/plugin_assets" )
for dir_rel in "${WRITABLE_DIRS_RELATIVE[@]}"; do
    if [ -d "${dir_rel}" ]; then
        sudo find "${dir_rel}" -type d -exec chmod ug=rwx,o=rx {} \;
        sudo find "${dir_rel}" -type f -exec chmod ug=rw,o=r {} \;
    else
        echo -e "${YELLOW}[AVISO] Directorio esperado '${dir_rel}' no encontrado para ajustar permisos.${NC}"
    fi
done

BINSTUB_DIRS_RELATIVE=( "bin" "vendor/bundle/bin" )
RUBY_VERSION_IN_BUNDLE_REL_PATH=$(ls -d vendor/bundle/ruby/* 2>/dev/null | head -n 1)
if [ -n "$RUBY_VERSION_IN_BUNDLE_REL_PATH" ] && [ -d "$RUBY_VERSION_IN_BUNDLE_REL_PATH/bin" ]; then
    BINSTUB_DIRS_RELATIVE+=("$RUBY_VERSION_IN_BUNDLE_REL_PATH/bin")
fi
for dir_rel in "${BINSTUB_DIRS_RELATIVE[@]}"; do
    if [ -d "${dir_rel}" ]; then
        sudo find "${dir_rel}" -type f -exec chmod ug+x,o+x {} \;
    fi
done
echo -e "${GREEN}[OK] Permisos de directorio ajustados para www-data.${NC}"

# --- PASO 9: Configuración de Puma y Servicio Systemd ---
echo -e "${BLUE}[INFO] Paso 9: Configurando Puma y creando servicio systemd...${NC}"

sudo -u www-data tee "config/puma.rb" > /dev/null << EOF_PUMA_CONF
bind 'tcp://127.0.0.1:3000'
bind 'tcp://[::1]:3000'
workers Integer(ENV['PUMA_WORKERS'] || ${PUMA_WORKERS})
threads Integer(ENV['MIN_THREADS']  || ${PUMA_MIN_THREADS}), Integer(ENV['MAX_THREADS'] || ${PUMA_MAX_THREADS})
environment ENV.fetch('RAILS_ENV') { 'production' }
directory '${REDMINE_INSTALL_DIR}'
pidfile '${REDMINE_INSTALL_DIR}/tmp/pids/puma.pid'
state_path '${REDMINE_INSTALL_DIR}/tmp/pids/puma.state'
stdout_redirect '${REDMINE_INSTALL_DIR}/log/puma_stdout.log', '${REDMINE_INSTALL_DIR}/log/puma_stderr.log', true
on_worker_boot do
  require "active_record"
  db_config_path = File.expand_path("../database.yml", __FILE__)
  if File.exist?(db_config_path)
    database_yml = YAML.load_file(db_config_path)
    config = database_yml[ENV.fetch('RAILS_ENV') { 'production' }.to_s]
    ActiveRecord::Base.establish_connection(config)
  else
    STDERR.puts "ERROR: database.yml no encontrado en #{db_config_path} desde puma.rb"
  end
end
before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base.connection_pool)
end
EOF_PUMA_CONF
echo -e "${GREEN}[OK] Archivo de configuración de Puma creado en ${REDMINE_INSTALL_DIR}/config/puma.rb.${NC}"

BUNDLE_PATH=$(which bundle || echo "/usr/local/bin/bundle")
if [ ! -f "$BUNDLE_PATH" ] && [ -f "/usr/bin/bundle" ]; then
    BUNDLE_PATH="/usr/bin/bundle"
fi
if ! command -v "${BUNDLE_PATH}" &> /dev/null; then
    echo -e "${RED}[ERROR CRITICO] No se pudo encontrar el ejecutable de 'bundle' en ${BUNDLE_PATH}.${NC}"
    exit 1
fi
echo -e "${BLUE}[INFO] Usando ruta para bundle: ${BUNDLE_PATH}${NC}"

PUMA_SERVICE_FILE="/etc/systemd/system/redmine_puma.service"
sudo tee "${PUMA_SERVICE_FILE}" > /dev/null << EOF_SYSTEMD
[Unit]
Description=Puma HTTP Server for Redmine ${REDMINE_VERSION_BRANCH}
After=network.target postgresql.service
StartLimitIntervalSec=0
[Service]
Type=notify
User=www-data
Group=www-data
Environment=RAILS_ENV=production
WorkingDirectory=${REDMINE_INSTALL_DIR}
ExecStart=${BUNDLE_PATH} exec puma -C config/puma.rb
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
echo -e "${GREEN}[OK] Archivo de servicio systemd creado en ${PUMA_SERVICE_FILE}.${NC}"

echo -e "${BLUE}[INFO] Recargando systemd daemon, habilitando e iniciando el servicio Puma...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable redmine_puma.service
sudo systemctl stop redmine_puma.service || true
sudo systemctl start redmine_puma.service || {
    echo -e "${RED}[ERROR CRITICO] Falló el inicio del servicio Puma.${NC}"
    sudo systemctl status redmine_puma.service --no-pager
    sudo journalctl -xeu redmine_puma.service --no-pager -n 50
    sudo -u www-data RAILS_ENV=production ${BUNDLE_PATH} exec puma -C "${REDMINE_INSTALL_DIR}/config/puma.rb" || \
        echo -e "${RED}El intento manual como www-data también falló.${NC}"
    exit 1
}
echo -e "${GREEN}[OK] Servicio Puma habilitado e iniciado.${NC}"

# --- PASO 10: Configuración del Firewall (UFW) ---
echo -e "${BLUE}[INFO] Paso 10: Configurando Firewall (UFW)...${NC}"
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}Responde 'y' si UFW te pide confirmación para habilitarse.${NC}"
    sudo ufw enable <<< "y" || { echo -e "${YELLOW}[AVISO] UFW ya está activo o falló su habilitación.${NC}"; true; }
    sudo ufw allow 22/tcp comment 'SSH' || { echo -e "${YELLOW}[AVISO] Regla SSH ya existe o falló.${NC}"; true; }
    echo -e "${GREEN}[OK] Firewall (UFW) configurado.${NC}"
else
    echo -e "${YELLOW}[AVISO] UFW no está instalado. Omitiendo configuración de firewall.${NC}"
fi

# --- VERIFICACIÓN FINAL ---
echo -e "\n${BLUE}--- VERIFICACIÓN FINAL ---${NC}"
echo -e "\n${BLUE}[INFO] Verificando archivos de configuración clave...${NC}"
declare -A files_to_check=(
    ["config/database.yml"]="Database config"
    [".bundle/config"]="Bundler local config"
    ["config/secrets.yml"]="Secrets YAML (si existe)"
    ["config/credentials.yml.enc"]="Rails Encrypted Credentials (si existe)"
    ["config/puma.rb"]="Puma config"
    ["/etc/systemd/system/redmine_puma.service"]="Systemd Service"
)
for file_key in "${!files_to_check[@]}"; do
    description="${files_to_check[$file_key]}"
    file_path="${file_key}"
    if [[ "${file_path}" == /* ]]; then path_to_test="${file_path}"; else path_to_test="${REDMINE_INSTALL_DIR}/${file_path}"; fi
    echo -e "\n${BLUE}[INFO] Verificando: ${path_to_test} (${description})...${NC}"
    if sudo test -f "${path_to_test}"; then
        echo -e "${GREEN}[OK] Archivo ${path_to_test} ENCONTRADO.${NC}"
    else
        if [[ "${description}" == *"Secrets YAML"* || "${description}" == *"Rails Encrypted Credentials"* ]]; then
             echo -e "${YELLOW}[AVISO] Archivo ${path_to_test} NO ENCONTRADO (puede ser normal).${NC}"
        else
            echo -e "${RED}[ERROR] Archivo ${path_to_test} NO ENCONTRADO.${NC}"
        fi
    fi
done

echo -e "\n${BLUE}[INFO] Verificando Gemfile (puma)...${NC}"
if sudo grep -Eq "^[[:space:]]*gem[[:space:]]*['\"]puma['\"],[[:space:]]*['\"]${PUMA_GEM_SPEC}['\"]" "Gemfile"; then
    echo -e "${GREEN}[OK] '${PUMA_TARGET_LINE}' encontrada en Gemfile.${NC}"
else
    echo -e "${RED}[ERROR] '${PUMA_TARGET_LINE}' NO encontrada correctamente en Gemfile.${NC}"
    sudo grep "puma" "Gemfile"
fi

echo -e "\n${BLUE}[INFO] Verificando directorios importantes...${NC}"
declare -A dirs_to_check_rel=( ["tmp/pids/"]="Puma PID" ["log/"]="Log" ["files/"]="Files" )
for dir_rel_key in "${!dirs_to_check_rel[@]}"; do
    description="${dirs_to_check_rel[$dir_rel_key]}"
    path_to_test="${REDMINE_INSTALL_DIR}/${dir_rel_key}"
    echo -e "\n${BLUE}[INFO] Verificando directorio: ${path_to_test} (${description})...${NC}"
    if sudo test -d "${path_to_test}"; then echo -e "${GREEN}[OK] Directorio ${path_to_test} ENCONTRADO.${NC}"; else echo -e "${RED}[ERROR] Directorio ${path_to_test} NO ENCONTRADO.${NC}"; fi
done

echo -e "\n${BLUE}[INFO] Verificando estado del servicio PostgreSQL...${NC}"
if sudo systemctl is-active --quiet postgresql; then echo -e "${GREEN}[OK] Servicio PostgreSQL activo.${NC}"; else echo -e "${RED}[ERROR] Servicio PostgreSQL NO activo.${NC}"; sudo systemctl status postgresql --no-pager; fi

echo -e "\n${BLUE}[INFO] Verificando estado del servicio Puma para Redmine...${NC}"
if [ -f "${PUMA_SERVICE_FILE}" ]; then
    if sudo systemctl is-active --quiet redmine_puma.service; then echo -e "${GREEN}[OK] Servicio redmine_puma.service activo.${NC}"; else echo -e "${RED}[ERROR] Servicio redmine_puma.service NO activo.${NC}"; sudo systemctl status redmine_puma.service --no-pager; fi
else
    echo -e "${RED}[ERROR] Archivo de servicio ${PUMA_SERVICE_FILE} NO ENCONTRADO.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando procesos Puma...${NC}"
if pgrep -u www-data -f puma &> /dev/null; then echo -e "${GREEN}[OK] Procesos Puma (www-data) encontrados.${NC}"; ps aux | grep puma | grep -v grep; else echo -e "${YELLOW}[AVISO] No se encontraron procesos Puma (www-data).${NC}"; fi

echo -e "\n${BLUE}[INFO] Verificando puerto 3000...${NC}"
if sudo netstat -tulnp | grep ':3000.*LISTEN' &> /dev/null; then echo -e "${GREEN}[OK] Puerto 3000 escuchando.${NC}"; else echo -e "${YELLOW}[AVISO] Puerto 3000 NO escuchando.${NC}"; fi

echo -e "\n${BLUE}[INFO] Verificando acceso local a Redmine con curl...${NC}"
if curl -sSf --head http://localhost:3000 > /dev/null; then echo -e "${GREEN}[OK] Redmine responde en http://localhost:3000${NC}"; else echo -e "${RED}[ERROR] No se pudo conectar a Redmine en http://localhost:3000.${NC}"; fi

echo -e "\n${GREEN}--- INSTALACIÓN COMPLETADA (o intentada) ---${NC}"
echo -e "${GREEN}Redmine debería estar accesible en ${YELLOW}http://localhost:3000${NC}"
echo -e "${YELLOW}Usuario: admin / Contraseña: admin (cambiar inmediatamente).${NC}"
echo -e "${BLUE}Logs de instalación:${NC}"
echo -e "  Gemfile backup: ${REDMINE_INSTALL_DIR}/${BACKUP_PATH}"
echo -e "  Bundle: ${REDMINE_INSTALL_DIR}/${BUNDLE_LOG_FILE}"
echo -e "  Migraciones BD: ${REDMINE_INSTALL_DIR}/${DB_MIGRATE_LOG_FILE}"
echo -e "  Carga datos defecto: ${REDMINE_INSTALL_DIR}/${LOAD_DEFAULT_DATA_LOG_FILE}"
echo -e "${BLUE}Logs de Puma:${NC}"
echo -e "  Stdout: ${REDMINE_INSTALL_DIR}/log/puma_stdout.log"
echo -e "  Stderr: ${REDMINE_INSTALL_DIR}/log/puma_stderr.log"
echo -e "  Systemd journal: sudo journalctl -xeu redmine_puma.service -n 200 --no-pager"
