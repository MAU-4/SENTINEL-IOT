#!/bin/bash

################################################################################
# Script de Corrección Automática para SENTINEL IoT
# Soluciona problemas de PATH y comandos faltantes
################################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SENTINEL IoT - Script de Corrección${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} Este script debe ejecutarse como root (sudo)"
   exit 1
fi

# Paso 1: Instalar comandos faltantes
echo -e "${YELLOW}[1/5]${NC} Instalando comandos faltantes..."
apt-get update -qq
apt-get install -y which iproute2 nftables > /dev/null 2>&1
echo -e "${GREEN}✓${NC} Comandos instalados"
echo ""

# Paso 2: Copiar frontend
echo -e "${YELLOW}[2/5]${NC} Copiando archivos del frontend..."
if [ -d "/home/niko/sentinel-iot-final/frontend/public" ]; then
    mkdir -p /opt/sentinel-iot/frontend/public
    cp -r /home/niko/sentinel-iot-final/frontend/public/* /opt/sentinel-iot/frontend/public/
    chmod -R 755 /opt/sentinel-iot/frontend/
    echo -e "${GREEN}✓${NC} Frontend copiado"
else
    echo -e "${RED}✗${NC} No se encontró el directorio frontend"
    echo -e "${YELLOW}[INFO]${NC} Buscando en ubicaciones alternativas..."
    
    # Buscar en ubicaciones alternativas
    if [ -d "~/sentinel-iot-final/frontend/public" ]; then
        mkdir -p /opt/sentinel-iot/frontend/public
        cp -r ~/sentinel-iot-final/frontend/public/* /opt/sentinel-iot/frontend/public/
        chmod -R 755 /opt/sentinel-iot/frontend/
        echo -e "${GREEN}✓${NC} Frontend copiado desde ~"
    else
        echo -e "${RED}[ERROR]${NC} No se pudo encontrar el directorio frontend"
    fi
fi
echo ""

# Paso 3: Crear archivo de leases de dnsmasq
echo -e "${YELLOW}[3/5]${NC} Creando archivo de leases..."
mkdir -p /var/lib/misc
touch /var/lib/misc/dnsmasq.leases
chmod 644 /var/lib/misc/dnsmasq.leases
echo -e "${GREEN}✓${NC} Archivo de leases creado"
echo ""

# Paso 4: Actualizar servicio systemd con PATH correcto
echo -e "${YELLOW}[4/5]${NC} Actualizando servicio systemd..."
cat > /etc/systemd/system/sentinel-backend.service << 'EOF'
[Unit]
Description=SENTINEL IoT Backend Service
After=network.target nftables.service hostapd.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/sentinel-iot/backend
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/sentinel-iot/venv/bin"
ExecStart=/opt/sentinel-iot/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo -e "${GREEN}✓${NC} Servicio actualizado"
echo ""

# Paso 5: Reiniciar servicio
echo -e "${YELLOW}[5/5]${NC} Reiniciando servicio..."
systemctl restart sentinel-backend
sleep 3
echo -e "${GREEN}✓${NC} Servicio reiniciado"
echo ""

# Verificación
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verificación del Sistema${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Verificar estado del servicio
if systemctl is-active --quiet sentinel-backend; then
    echo -e "${GREEN}✓${NC} Backend está activo"
else
    echo -e "${RED}✗${NC} Backend no está activo"
fi

# Verificar que el puerto 8000 está escuchando
if netstat -tlnp 2>/dev/null | grep -q ":8000"; then
    echo -e "${GREEN}✓${NC} Puerto 8000 está escuchando"
else
    echo -e "${RED}✗${NC} Puerto 8000 no está escuchando"
fi

# Verificar archivos del frontend
if [ -f "/opt/sentinel-iot/frontend/public/index.html" ]; then
    echo -e "${GREEN}✓${NC} Frontend instalado correctamente"
else
    echo -e "${RED}✗${NC} Frontend no encontrado"
fi

# Verificar comandos
if command -v nft &> /dev/null; then
    echo -e "${GREEN}✓${NC} Comando 'nft' disponible"
else
    echo -e "${RED}✗${NC} Comando 'nft' no disponible"
fi

if command -v ip &> /dev/null; then
    echo -e "${GREEN}✓${NC} Comando 'ip' disponible"
else
    echo -e "${RED}✗${NC} Comando 'ip' no disponible"
fi

if command -v which &> /dev/null; then
    echo -e "${GREEN}✓${NC} Comando 'which' disponible"
else
    echo -e "${RED}✗${NC} Comando 'which' no disponible"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}¡Corrección Completada!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Accede al dashboard en:${NC}"
echo -e "  http://127.0.0.1:8000"
echo -e "  http://192.168.50.1:8000"
echo ""
echo -e "${YELLOW}Ver logs:${NC}"
echo -e "  sudo journalctl -u sentinel-backend -f"
echo ""
