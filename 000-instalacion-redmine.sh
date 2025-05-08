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
# cd /var/www # Nos moveremos al directorio de Redmine directamente después de clonar

if [ -d "${REDMINE_INSTALL_DIR}" ]; then
    echo -e "${YELLOW}[AVISO] El directorio ${REDMINE_INSTALL_DIR} ya existe. Eliminándolo para una instalación limpia...${NC}"
    sudo rm -rf "${REDMINE_INSTALL_DIR}"
fi
echo -e "${BLUE}[INFO] Clonando Redmine ${REDMINE_VERSION_BRANCH} en ${REDMINE_INSTALL_DIR}...${NC}"
# Clonamos directamente al REDMINE_INSTALL_DIR
sudo git clone --branch "${REDMINE_VERSION_BRANCH}" https://github.com/redmine/redmine.git "${REDMINE_INSTALL_DIR}"
echo -e "${GREEN}[OK] Redmine clonado.${NC}"

cd "${REDMINE_INSTALL_DIR}" # ¡IMPORTANTE! Moverse al directorio de Redmine aquí

echo -e "${BLUE}[INFO] Creando directorios necesarios para Redmine y Puma...${NC}"
sudo mkdir -p "${REDMINE_INSTALL_DIR}/tmp/pids" "${REDMINE_INSTALL_DIR}/tmp/sockets" \
               "${REDMINE_INSTALL_DIR}/files" "${REDMINE_INSTALL_DIR}/log" \
               "${REDMINE_INSTALL_DIR}/public/plugin_assets"

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

GEMFILE_PATH="${REDMINE_INSTALL_DIR}/Gemfile"
PUMA_TARGET_LINE="gem 'puma', '${PUMA_GEM_SPEC}'" # e.g., gem 'puma', '>= 5.6.4'
BACKUP_PATH="${GEMFILE_PATH}.backup_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "${GEMFILE_PATH}" ]; then
    echo -e "${RED}[ERROR] ${GEMFILE_PATH} no encontrado. La clonación de Redmine pudo haber fallado.${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Modificando ${GEMFILE_PATH} para asegurar la gema Puma correcta...${NC}"
echo -e "${BLUE}[INFO] Creando copia de respaldo: ${BACKUP_PATH}${NC}"
sudo cp "${GEMFILE_PATH}" "${BACKUP_PATH}"

echo -e "${BLUE}[INFO] Eliminando cualquier línea existente de 'gem puma'...${NC}"
# Usar sudo para modificar el archivo que pertenece a root en este punto (o será www-data después)
# El patrón busca líneas que comiencen con espacios opcionales, luego 'gem', espacios, 'puma' o "puma"
sudo sed -i "/^[[:space:]]*gem[[:space:]]*['\"]puma['\"].*/d" "${GEMFILE_PATH}"

echo -e "${BLUE}[INFO] Añadiendo '${PUMA_TARGET_LINE}' después de 'gem bundler'...${NC}"
# Añade la línea de Puma después de la línea que contiene 'gem 'bundler''
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
sudo mkdir -p "${REDMINE_INSTALL_DIR}/.bundle"
sudo chown -R $(whoami):$(whoami) "${REDMINE_INSTALL_DIR}/.bundle"
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test mysql sqlite3'

echo -e "${BLUE}[INFO] Ejecutando 'bundle pristine' para asegurar una instalación limpia de gemas...${NC}"
sudo bundle pristine || echo -e "${YELLOW}[AVISO] 'bundle pristine' falló o no hizo nada, continuando...${NC}"

echo -e "${BLUE}[INFO] Ejecutando 'bundle install --jobs=$(nproc)'. Esto puede tardar varios minutos...${NC}"
if sudo bundle install --jobs=$(nproc) > bundle_install.log 2>&1; then
    echo -e "${GREEN}[OK] Gemas instaladas.${NC}"
else
    echo -e "${RED}[ERROR] Falló la instalación de gemas con Bundler.${NC}"
    echo -e "${RED}Revise el archivo ${REDMINE_INSTALL_DIR}/bundle_install.log para detalles:${NC}"
    cat "${REDMINE_INSTALL_DIR}/bundle_install.log"
    exit 1
fi

# Verificar si el binstub de puma existe
PUMA_BINSTUB_PATH_V1="${REDMINE_INSTALL_DIR}/vendor/bundle/bin/puma"
PUMA_BINSTUB_PATH_V2=$(sudo find "${REDMINE_INSTALL_DIR}/vendor/bundle/ruby/"*"/bin" -name puma -print -quit 2>/dev/null) # Usar sudo aquí por si acaso

if sudo test -f "${PUMA_BINSTUB_PATH_V1}"; then
    echo -e "${GREEN}[OK] Ejecutable de Puma encontrado en ${PUMA_BINSTUB_PATH_V1}.${NC}"
elif [ -n "${PUMA_BINSTUB_PATH_V2}" ] && sudo test -f "${PUMA_BINSTUB_PATH_V2}"; then
    echo -e "${GREEN}[OK] Ejecutable de Puma encontrado en ${PUMA_BINSTUB_PATH_V2}.${NC}"
else
    echo -e "${RED}[ERROR CRITICO] El ejecutable de Puma NO se encontró en vendor/bundle después de 'bundle install'.${NC}"
    echo -e "${YELLOW}Posibles causas y verificaciones:${NC}"
    grep puma "${REDMINE_INSTALL_DIR}/Gemfile" || echo "Puma no encontrado en Gemfile"
    sudo find "${REDMINE_INSTALL_DIR}/vendor/bundle" -type f -name puma -print 2>/dev/null || echo "No se encontró 'puma' en vendor/bundle"
    exit 1
fi


# --- PASO 5: Generación del Secreto del Almacén de Sesiones ---
echo -e "${BLUE}[INFO] Paso 5: Generando/configurando token secreto de Redmine...${NC}"
sudo RAILS_ENV=production bundle exec rake generate_secret_token \
    || { echo -e "${RED}[ERROR] Falló 'rake generate_secret_token'. Saliendo.${NC}"; exit 1; }
echo -e "${GREEN}[OK] Token secreto generado/configurado.${NC}"


# --- PASO 6: Creación de Objetos del Esquema de Base de Datos ---
echo -e "${BLUE}[INFO] Paso 6: Ejecutando migraciones de base de datos...${NC}"
sudo RAILS_ENV=production bundle exec rake db:migrate > db_migrate.log 2>&1 || {
    echo -e "${RED}[ERROR] Fallaron las migraciones de base de datos.${NC}"
    echo -e "${RED}Revise ${REDMINE_INSTALL_DIR}/db_migrate.log.${NC}"
    cat "${REDMINE_INSTALL_DIR}/db_migrate.log"
    exit 1
}
echo -e "${GREEN}[OK] Migraciones de base de datos ejecutadas.${NC}"

# --- PASO 7: Conjunto de Datos Predeterminado de la Base de Datos ---
echo -e "${BLUE}[INFO] Paso 7: Cargando datos por defecto (Idioma: Inglés)...${NC}"
sudo RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data < /dev/null > load_default_data.log 2>&1 || {
    echo -e "${YELLOW}[AVISO] Falló la carga de datos por defecto (puede ser normal si ya se ejecutó). Código de salida: $?.${NC}"
    echo -e "${YELLOW}Revise el archivo ${REDMINE_INSTALL_DIR}/load_default_data.log para detalles.${NC}"
}
echo -e "${GREEN}[OK] Intento de carga de datos por defecto completado.${NC}"

# --- PASO 8: Permisos del Sistema de Archivos ---
echo -e "${BLUE}[INFO] Paso 8: Ajustando permisos del directorio de Redmine para www-data...${NC}"
sudo chown -R www-data:www-data "${REDMINE_INSTALL_DIR}"

sudo find "${REDMINE_INSTALL_DIR}" -type d -exec chmod 755 {} \;
sudo find "${REDMINE_INSTALL_DIR}" -type f -exec chmod 644 {} \;

WRITABLE_DIRS=(
    "${REDMINE_INSTALL_DIR}/files"
    "${REDMINE_INSTALL_DIR}/log"
    "${REDMINE_INSTALL_DIR}/tmp"
    "${REDMINE_INSTALL_DIR}/public/plugin_assets"
)
for dir in "${WRITABLE_DIRS[@]}"; do
    sudo find "${dir}" -type d -exec chmod ug+rwx,o+rx-w {} \;
    sudo find "${dir}" -type f -exec chmod ug+rw,o+r-w {} \;
done

BINSTUB_DIRS=(
    "${REDMINE_INSTALL_DIR}/bin"
    "${REDMINE_INSTALL_DIR}/vendor/bundle/bin"
)
RUBY_VERSION_IN_BUNDLE=$(sudo ls -d ${REDMINE_INSTALL_DIR}/vendor/bundle/ruby/* 2>/dev/null | head -n 1)
if [ -n "$RUBY_VERSION_IN_BUNDLE" ] && sudo test -d "$RUBY_VERSION_IN_BUNDLE/bin"; then
    BINSTUB_DIRS+=("$RUBY_VERSION_IN_BUNDLE/bin")
fi

for dir in "${BINSTUB_DIRS[@]}"; do
    if sudo test -d "${dir}"; then # Usar sudo test
        sudo chmod -R ug+rx,o+rx-w "${dir}"
    fi
done
echo -e "${GREEN}[OK] Permisos de directorio ajustados para www-data.${NC}"


# --- PASO 9: Configuración de Puma y Servicio Systemd ---
echo -e "${BLUE}[INFO] Paso 9: Configurando Puma y creando servicio systemd...${NC}"

sudo -u www-data tee "${REDMINE_INSTALL_DIR}/config/puma.rb" > /dev/null << EOF_PUMA_CONF
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
  db_config_path = File.expand_path("../../config/database.yml", __FILE__)
  if File.exist?(db_config_path)
    database_yml = YAML.load_file(db_config_path)
    config = database_yml[ENV.fetch('RAILS_ENV') { 'production' }.to_s]
    ActiveRecord::Base.establish_connection(config)
  else
    STDERR.puts "ERROR: database.yml no encontrado en #{db_config_path}"
  end
end

before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base.connection_pool)
end
EOF_PUMA_CONF
echo -e "${GREEN}[OK] Archivo de configuración de Puma creado.${NC}"

BUNDLE_PATH=$(which bundle || echo "/usr/local/bin/bundle")
if [ ! -f "$BUNDLE_PATH" ] && [ -f "/usr/bin/bundle" ]; then
    BUNDLE_PATH="/usr/bin/bundle"
fi
if ! command -v "${BUNDLE_PATH}" &> /dev/null; then
    echo -e "${RED}[ERROR CRITICO] No se pudo encontrar el ejecutable de 'bundle' en ${BUNDLE_PATH}. Verifica la instalación de Ruby/Bundler.${NC}"
    exit 1
fi
echo -e "${BLUE}[INFO] Usando ruta para bundle: ${BUNDLE_PATH}${NC}"

sudo tee /etc/systemd/system/redmine_puma.service > /dev/null << EOF_SYSTEMD
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
ExecStart=${BUNDLE_PATH} exec puma -C ${REDMINE_INSTALL_DIR}/config/puma.rb
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
echo -e "${GREEN}[OK] Archivo de servicio systemd creado.${NC}"

echo -e "${BLUE}[INFO] Recargando systemd daemon, habilitando e iniciando el servicio Puma...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable redmine_puma.service
sudo systemctl stop redmine_puma.service || true
sudo systemctl start redmine_puma.service || {
    echo -e "${RED}[ERROR CRITICO] Falló el inicio del servicio Puma.${NC}"
    echo -e "${YELLOW}--- Mostrando estado del servicio ---${NC}"
    sudo systemctl status redmine_puma.service --no-pager
    echo -e "${YELLOW}--- Mostrando logs del journal (-n 50) ---${NC}"
    sudo journalctl -xeu redmine_puma.service --no-pager -n 50
    echo -e "${YELLOW}--- Intentando ejecutar Puma manualmente como www-data para ver errores ---${NC}"
    cd "${REDMINE_INSTALL_DIR}"
    sudo -u www-data RAILS_ENV=production ${BUNDLE_PATH} exec puma -C "${REDMINE_INSTALL_DIR}/config/puma.rb" || \
        echo -e "${RED}El intento manual como www-data también falló.${NC}"
    echo -e "${RED}Revisa los logs de Puma: '${REDMINE_INSTALL_DIR}/log/puma_stdout.log' y '${REDMINE_INSTALL_DIR}/log/puma_stderr.log'.${NC}"
    exit 1
}
echo -e "${GREEN}[OK] Servicio Puma habilitado e iniciado.${NC}"

# --- PASO 10: Configuración del Firewall (UFW) ---
echo -e "${BLUE}[INFO] Paso 10: Configurando Firewall (UFW)...${NC}"
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}Responde 'y' si UFW te pide confirmación para habilitarse.${NC}"
    sudo ufw enable <<< "y" || { echo -e "${YELLOW}[AVISO] UFW ya está activo o falló su habilitación.${NC}"; true; }
    sudo ufw allow 22/tcp comment 'SSH' || { echo -e "${YELLOW}[AVISO] Regla SSH ya existe o falló.${NC}"; true; }
    # También se podría añadir la regla para el puerto 3000 si no hay un proxy inverso,
    # o el puerto del proxy inverso (80, 443)
    # sudo ufw allow 3000/tcp comment 'Redmine Puma'
    echo -e "${GREEN}[OK] Firewall (UFW) configurado.${NC}"
else
    echo -e "${YELLOW}[AVISO] UFW no está instalado. Omitiendo configuración de firewall.${NC}"
fi

# --- VERIFICACIÓN FINAL ---
echo -e "\n${BLUE}--- VERIFICACIÓN FINAL ---${NC}"
echo -e "\n${BLUE}[INFO] Verificando archivos de configuración clave...${NC}"
declare -A files_to_check=(
    ["${REDMINE_INSTALL_DIR}/config/database.yml"]="Database config"
    ["${REDMINE_INSTALL_DIR}/.bundle/config"]="Bundler local config"
    ["${REDMINE_INSTALL_DIR}/config/secrets.yml"]="Secrets YAML (si existe)"
    ["${REDMINE_INSTALL_DIR}/config/credentials.yml.enc"]="Rails Encrypted Credentials (si existe)"
    ["${REDMINE_INSTALL_DIR}/config/puma.rb"]="Puma config"
    ["/etc/systemd/system/redmine_puma.service"]="Systemd Service"
)
for file_path in "${!files_to_check[@]}"; do
    description="${files_to_check[$file_path]}"
    if sudo test -f "${file_path}"; then # Usar sudo test por permisos
        echo -e "${GREEN}[OK] Archivo ${file_path} (${description}) ENCONTRADO.${NC}"
    else
        if [[ "${file_path}" == *credentials.yml.enc* || "${file_path}" == *secrets.yml* ]]; then
            echo -e "${YELLOW}[AVISO] Archivo ${file_path} (${description}) NO ENCONTRADO (puede ser normal).${NC}"
        else
            echo -e "${RED}[ERROR] Archivo ${file_path} (${description}) NO ENCONTRADO.${NC}"
        fi
    fi
done

echo -e "\n${BLUE}[INFO] Verificando Gemfile (puma)...${NC}"
if sudo grep -Eq "^[[:space:]]*gem[[:space:]]*['\"]puma['\"],[[:space:]]*['\"]${PUMA_GEM_SPEC}['\"]" "${REDMINE_INSTALL_DIR}/Gemfile"; then
    echo -e "${GREEN}[OK] '${PUMA_TARGET_LINE}' encontrada en Gemfile.${NC}"
else
    echo -e "${RED}[ERROR] '${PUMA_TARGET_LINE}' NO encontrada correctamente en Gemfile.${NC}"
    sudo grep "puma" "${REDMINE_INSTALL_DIR}/Gemfile"
fi

echo -e "\n${BLUE}[INFO] Verificando directorios importantes...${NC}"
declare -A dirs_to_check=(
    ["${REDMINE_INSTALL_DIR}/tmp/pids/"]="Puma PID directory"
    ["${REDMINE_INSTALL_DIR}/log/"]="Log directory"
    ["${REDMINE_INSTALL_DIR}/files/"]="Files directory"
)
for dir_path in "${!dirs_to_check[@]}"; do
    description="${dirs_to_check[$dir_path]}"
    if sudo test -d "${dir_path}"; then # Usar sudo test
        echo -e "${GREEN}[OK] Directorio ${dir_path} (${description}) ENCONTRADO.${NC}"
    else
        echo -e "${RED}[ERROR] Directorio ${dir_path} (${description}) NO ENCONTRADO.${NC}"
    fi
done

echo -e "\n${BLUE}[INFO] Verificando estado del servicio PostgreSQL...${NC}"
if sudo systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}[OK] Servicio PostgreSQL está activo.${NC}"
else
    echo -e "${RED}[ERROR] Servicio PostgreSQL NO está activo.${NC}"
    sudo systemctl status postgresql --no-pager
fi

echo -e "\n${BLUE}[INFO] Verificando estado del servicio Puma para Redmine...${NC}"
if sudo systemctl is-active --quiet redmine_puma.service; then
    echo -e "${GREEN}[OK] Servicio redmine_puma.service está activo.${NC}"
else
    echo -e "${RED}[ERROR] Servicio redmine_puma.service NO está activo.${NC}"
    sudo systemctl status redmine_puma.service --no-pager
fi

echo -e "\n${BLUE}[INFO] Verificando procesos Puma...${NC}"
if pgrep -u www-data -f puma &> /dev/null; then
    echo -e "${GREEN}[OK] Procesos Puma ejecutándose como www-data encontrados.${NC}"
    ps aux | grep puma | grep -v grep
else
    echo -e "${YELLOW}[AVISO] No se encontraron procesos Puma ejecutándose como www-data.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando puerto 3000...${NC}"
if sudo netstat -tulnp | grep ':3000.*LISTEN' &> /dev/null; then
    echo -e "${GREEN}[OK] Algo está escuchando en el puerto 3000.${NC}"
else
    echo -e "${YELLOW}[AVISO] Nada parece estar escuchando en el puerto 3000.${NC}"
fi

echo -e "\n${BLUE}[INFO] Verificando acceso local a Redmine con curl...${NC}"
if curl -sSf --head http://localhost:3000 > /dev/null; then
    echo -e "${GREEN}[OK] Redmine responde en http://localhost:3000${NC}"
else
    echo -e "${RED}[ERROR] No se pudo conectar a Redmine en http://localhost:3000 o la respuesta no fue exitosa.${NC}"
    echo -e "${YELLOW}Revisa los logs de Puma y systemd mencionados.${NC}"
fi

echo -e "\n${GREEN}--- INSTALACIÓN COMPLETADA (o intentada) ---${NC}"
echo -e "${GREEN}Redmine debería estar accesible en ${YELLOW}http://localhost:3000${NC}"
echo -e "${YELLOW}Usuario por defecto: admin / Contraseña por defecto: admin (cambiar inmediatamente).${NC}"

sudo mkdir -p /srv/git/mi_proyecto.git
sudo git init --bare
sudo git config core.sharedRepository group

echo -e "${BLUE} Creado  repositorio Git en el servidor:${NC}"
echo -e "${BLUE}  RUTA :  /srv/git/mi_proyecto.git :${NC}"
echo -e "${BLUE}Logs de instalación:${NC}"


echo -e "${BLUE}Logs de instalación:${NC}"
echo -e "  Gemfile backup: ${BACKUP_PATH}"
echo -e "  Bundle: ${REDMINE_INSTALL_DIR}/bundle_install.log"
echo -e "  Migraciones BD: ${REDMINE_INSTALL_DIR}/db_migrate.log"
echo -e "  Carga datos defecto: ${REDMINE_INSTALL_DIR}/load_default_data.log"
echo -e "${BLUE}Logs de Puma (revisar si hay errores):${NC}"
echo -e "  Stdout: ${REDMINE_INSTALL_DIR}/log/puma_stdout.log"
echo -e "  Stderr: ${REDMINE_INSTALL_DIR}/log/puma_stderr.log"
echo -e "  Systemd journal: sudo journalctl -xeu redmine_puma.service -n 200 --no-pager"
