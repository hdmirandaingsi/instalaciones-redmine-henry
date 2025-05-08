#!/bin/bash
set -e

# Función para mostrar mensajes de estado
function echo_status {
    echo -e "\n\033[1;36m[+] $1\033[0m"
}

function echo_success {
    echo -e "\033[1;32m[✔] $1\033[0m"
}

function echo_info {
    echo -e "\033[1;33m[i] $1\033[0m"
}

# ==============================================
# INSTALACIÓN DE DEPENDENCIAS ESENCIALES
# ==============================================
echo_status "Instalando dependencias esenciales (curl, ca-certificates)..."
# Asegurarse de que apt esté actualizado para encontrar los paquetes
sudo apt-get update -y
# Instalar curl (necesario para descargar la clave GPG)
sudo apt-get install curl -y
# Instalar ca-certificates (necesario para verificar la conexión al repositorio)
sudo apt-get install ca-certificates -y
echo_success "Dependencias esenciales instaladas."


# ==============================================
# INSTALACIÓN DE CLOUDFLARED
# ==============================================
echo_status "Instalando Cloudflared..."

# Clave GPG y repositorio de Cloudflare
sudo mkdir -p --mode=0755 /usr/share/keyrings
# Ahora curl funcionará porque ya está instalado
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
# Ahora apt podrá verificar el certificado porque ca-certificates está instalado
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

# Actualizar lista de paquetes (incluyendo el nuevo repositorio de Cloudflare)
sudo apt-get update -y
# Instalar cloudflared
sudo apt-get install cloudflared -y
echo_success "Cloudflared instalado."


# Iniciar túnel en segundo plano usando --url http://localhost:80
echo_status "Iniciando túnel Cloudflare apuntando a localhost:80..."
# Usamos un archivo temporal para capturar la salida inicial, incluyendo la URL trycloudflare.com
CLOUDFLARED_LOG="/tmp/cloudflared_tunnel_$(date +%s).log"
# Ejecutar cloudflared en segundo plano, redirigiendo stdout y stderr al archivo de log
cloudflared tunnel --url http://localhost:3000 &> "$CLOUDFLARED_LOG" &
# Esperar un poco para que cloudflared se inicie y genere la URL
sleep 10 # Aumentado un poco el tiempo de espera para dar más margen

echo_info "Cloudflare Tunnel está corriendo en segundo plano."


echo -e "\n\033[1;33mAccede a tu sitio web a través de la URL temporal de Cloudflare:\033[0m"

# Intentar encontrar la URL trycloudflare.com en el log
# Buscar líneas que contengan "INF" y "https://...trycloudflare.com"
# Asegúrate de que el log exista y tenga contenido antes de grep
if [ -s "$CLOUDFLARED_LOG" ]; then
    TRY_CF_URL=$(grep "INF" "$CLOUDFLARED_LOG" | grep -o 'https://[^ ]*\.trycloudflare\.com' | head -n 1)
    if [ -n "$TRY_CF_URL" ]; then
        echo -e "  \033[1;32m$TRY_CF_URL\033[0m"
        echo_info "Esta URL es temporal y cambiará si el túnel se detiene y se reinicia sin un nombre de túnel registrado."
    else
        echo -e "  \033[1;31mNo se pudo encontrar la URL trycloudflare.com en el log.\033[0m"
        echo_info "El túnel debería estar corriendo. Intenta ejecutar 'grep \"INF\" $CLOUDFLARED_LOG' para ver la salida."
    fi
else
    echo -e "  \033[1;31mEl archivo de log de cloudflared ($CLOUDFLARED_LOG) no se creó o está vacío.\033[0m"
    echo_info "Puede que cloudflared no se haya iniciado correctamente. Revisa la salida de error si la hubo."
    echo_info "Puedes intentar ejecutar 'cloudflared tunnel --url http://localhost:80' manualmente en una nueva terminal para ver la URL."
fi


echo_info "El archivo de log de cloudflared está en $CLOUDFLARED_LOG"
