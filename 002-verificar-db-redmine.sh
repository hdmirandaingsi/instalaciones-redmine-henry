#!/bin/bash

# --- Variables de Configuración (DEBEN COINCIDIR CON TU SCRIPT DE INSTALACIÓN) ---
REDMINE_DB_USER="h-debian"
REDMINE_DB_NAME="redmine"

# Nombres de algunas tablas clave de Redmine para inspeccionar su estructura
REDMINE_KEY_TABLES_STRUCTURE=("users" "projects" "issues" "settings" "trackers" "workflows" "repositories" "time_entries" "journals")

# Nombres de tablas importantes de Redmine de las que mostrar algunos datos
REDMINE_DATA_TABLES=("users" "projects" "issues" "issue_statuses" "trackers" "enabled_modules" "members" "roles" "time_entries" "news" "repositories")
# Puedes añadir o quitar tablas de esta lista según necesites

# --- Colores para la Salida ---
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}--- SCRIPT DE INSPECCIÓN DE POSTGRESQL PARA REDMINE (CON DATOS DE TABLAS) ---${NC}"

# Verificar si psql está disponible
if ! command -v psql &> /dev/null; then
    echo -e "${RED}[ERROR] El comando 'psql' no se encuentra. Asegúrate de que PostgreSQL esté instalado y en el PATH.${NC}"
    exit 1
fi

# Verificar si las variables están configuradas
if [ -z "$REDMINE_DB_NAME" ] || [ -z "$REDMINE_DB_USER" ]; then
    echo -e "${RED}[ERROR] Las variables REDMINE_DB_NAME o REDMINE_DB_USER no están configuradas en el script.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}=== 1. INFORMACIÓN GENERAL DEL SERVIDOR POSTGRESQL ===${NC}"
echo -e "${CYAN}Versión de PostgreSQL:${NC}"
sudo -u postgres psql -c "SELECT version();"
echo -e "\n${CYAN}Ubicación del archivo de configuración principal (postgresql.conf):${NC}"
sudo -u postgres psql -c "SHOW config_file;"
echo -e "\n${CYAN}Ubicación del archivo de configuración de autenticación de clientes (pg_hba.conf):${NC}"
sudo -u postgres psql -c "SHOW hba_file;"
echo -e "\n${CYAN}Directorio de logs de PostgreSQL:${NC}"
sudo -u postgres psql -c "SHOW log_directory;"

echo -e "\n${YELLOW}=== 2. LISTA DE TODAS LAS BASES DE DATOS ===${NC}"
sudo -u postgres psql -c "\l+"

echo -e "\n${YELLOW}=== 3. LISTA DE TODOS LOS ROLES (USUARIOS Y GRUPOS) ===${NC}"
sudo -u postgres psql -c "\du+"

echo -e "\n${YELLOW}=== 4. DETALLES DE LA BASE DE DATOS DE REDMINE: ${GREEN}${REDMINE_DB_NAME}${NC} ==="
sudo -u postgres psql -d "${REDMINE_DB_NAME}" << EOF
\pset pager off  -- Desactivar paginador para que toda la salida se muestre
\echo '${CYAN}Propietario, Codificación, Colación para la BD ${REDMINE_DB_NAME}:${NC}'
SELECT
    d.datname AS database_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
    d.datcollate AS collation,
    d.datctype AS ctype
FROM
    pg_catalog.pg_database d
WHERE
    d.datname = '${REDMINE_DB_NAME}';

\echo '\n${CYAN}Privilegios sobre la base de datos ${REDMINE_DB_NAME} (formato ACL):${NC}'
SELECT datacl FROM pg_database WHERE datname = '${REDMINE_DB_NAME}';
\l+ ${REDMINE_DB_NAME}

\echo '\n${CYAN}Esquemas dentro de la base de datos ${REDMINE_DB_NAME} y sus propietarios/privilegios:${NC}'
\dn+

\echo '\n${CYAN}Todas las Tablas en el esquema "public" y sus propietarios:${NC}'
\dt public.*

\echo '\n${CYAN}Privilegios del usuario ${GREEN}${REDMINE_DB_USER}${NC} sobre las tablas del esquema "public":${NC}'
SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM
    information_schema.role_table_grants
WHERE
    grantee = '${REDMINE_DB_USER}' AND table_schema = 'public'
ORDER BY
    table_name, privilege_type;

\echo '\n${CYAN}Estructura e Índices de Tablas Clave de Redmine:${NC}'
$(
for table_name in "${REDMINE_KEY_TABLES_STRUCTURE[@]}"; do
  echo "\\echo '\\n--- Estructura Tabla: public.${table_name} ---'"
  echo "\\d public.${table_name}"
  echo "\\di+ public.${table_name}"
done
)

\echo '\n${CYAN}Secuencias en el esquema "public" (usadas para IDs autoincrementales):${NC}'
\ds public.*

\echo '\n\n${YELLOW}=== 4.1. MUESTRA DE DATOS DE TABLAS IMPORTANTES DE REDMINE (Primeras 10 filas) ===${NC}'
$(
for table_name in "${REDMINE_DATA_TABLES[@]}"; do
  echo "\\echo '\\n${CYAN}--- Datos Tabla: public.${table_name} (LIMIT 10) ---${NC}'"
  # Primero, obtener los nombres de las columnas para mostrarlos si la tabla está vacía o para referencia
  echo "SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = '${table_name}';"
  echo "SELECT * FROM public.${table_name} LIMIT 10;"
done
)

EOF
# Fin del Here Document

echo -e "\n${YELLOW}=== 5. DETALLES DEL USUARIO/ROL DE REDMINE: ${GREEN}${REDMINE_DB_USER}${NC} ==="
sudo -u postgres psql << EOF
\pset pager off
\echo '${CYAN}Atributos del rol ${REDMINE_DB_USER}:${NC}'
\du+ ${REDMINE_DB_USER}

\echo '\n${CYAN}Privilegios explícitamente concedidos AL ROL ${REDMINE_DB_USER}:${NC}'
\dp ${REDMINE_DB_USER}

\echo '\n${CYAN}Objetos que pertenecen al rol ${REDMINE_DB_USER} en la base de datos ${REDMINE_DB_NAME} (si alguno):${NC}'
SELECT
    n.nspname as schema_name,
    c.relname as object_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'i' THEN 'INDEX'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'c' THEN 'COMPOSITE TYPE'
        WHEN 't' THEN 'TOAST TABLE'
        WHEN 'f' THEN 'FOREIGN TABLE'
    END as object_type
FROM
    pg_catalog.pg_class c
LEFT JOIN
    pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE
    c.relowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = '${REDMINE_DB_USER}')
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY
    n.nspname, c.relname;
EOF
# Fin del Here Document

echo -e "\n${YELLOW}=== 6. CONEXIONES ACTIVAS RELACIONADAS CON REDMINE ===${NC}"
sudo -u postgres psql -c "SELECT pid, datname, usename, application_name, client_addr, client_port, state, backend_start, query_start, state_change, wait_event_type, wait_event, query FROM pg_stat_activity WHERE datname = '${REDMINE_DB_NAME}' OR usename = '${REDMINE_DB_USER}';"
echo -e "\n${CYAN}Para ver TODAS las conexiones activas:${NC}"
echo -e "sudo -u postgres psql -c \"SELECT pid, datname, usename, application_name, client_addr, state, query FROM pg_stat_activity;\""

echo -e "\n${BLUE}--- FIN DE LA INSPECCIÓN ---${NC}"
