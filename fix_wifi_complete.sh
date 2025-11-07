#!/bin/bash
#
# SENTINEL IoT v2.0 - Script de Corrección Completa de Wi-Fi
#
# Este script limpia configuraciones incorrectas y configura todo correctamente
#

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root (sudo)"
    exit 1
fi

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║     SENTINEL IoT - Corrección Completa de Wi-Fi          ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Variables
IOT_INTERFACE="wlan1"
IOT_GATEWAY="192.168.100.1"
WIFI_SSID="SENTINEL_IoT"
WIFI_PASSWORD="Sentinel2024"

# ============================================================================
# FASE 1: LIMPIEZA COMPLETA
# ============================================================================

echo -e "${YELLOW}═══ FASE 1: LIMPIEZA DE CONFIGURACIONES INCORRECTAS ═══${NC}"
echo ""

log_info "Deteniendo todos los servicios relacionados..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop wpa_supplicant 2>/dev/null || true
sleep 2
log_success "Servicios detenidos"

log_info "Matando procesos residuales..."
killall wpa_supplicant 2>/dev/null || true
killall hostapd 2>/dev/null || true
killall dnsmasq 2>/dev/null || true
sleep 1
log_success "Procesos limpiados"

log_info "Limpiando interfaz $IOT_INTERFACE..."
ip link set $IOT_INTERFACE down 2>/dev/null || true
ip addr flush dev $IOT_INTERFACE 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true
log_success "Interfaz limpiada"

log_info "Desactivando NetworkManager en $IOT_INTERFACE..."
nmcli device set $IOT_INTERFACE managed no 2>/dev/null || true
log_success "NetworkManager desactivado en $IOT_INTERFACE"

log_info "Haciendo backup de archivos de configuración antiguos..."
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    log_success "Backup de dnsmasq.conf creado"
fi

if [ -f /etc/hostapd/hostapd.conf ]; then
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    log_success "Backup de hostapd.conf creado"
fi

echo ""
log_success "Limpieza completada"
echo ""

# ============================================================================
# FASE 2: CONFIGURACIÓN CORRECTA
# ============================================================================

echo -e "${YELLOW}═══ FASE 2: CONFIGURACIÓN CORRECTA ═══${NC}"
echo ""

# Configurar interfaz wlan1
log_info "Configurando interfaz $IOT_INTERFACE..."
ip link set $IOT_INTERFACE up
sleep 1
ip addr add $IOT_GATEWAY/24 dev $IOT_INTERFACE 2>/dev/null || true
sleep 1

# Verificar que tiene IP
if ip addr show $IOT_INTERFACE | grep -q "$IOT_GATEWAY"; then
    log_success "IP $IOT_GATEWAY asignada a $IOT_INTERFACE"
else
    log_error "No se pudo asignar IP a $IOT_INTERFACE"
    exit 1
fi

# Crear archivo de configuración de dnsmasq LIMPIO
log_info "Creando configuración de dnsmasq..."
cat > /etc/dnsmasq.conf << 'EOF'
# SENTINEL IoT - Configuración de dnsmasq
interface=wlan1
dhcp-range=192.168.100.10,192.168.100.250,255.255.255.0,24h
dhcp-option=3,192.168.100.1
dhcp-option=6,192.168.100.1
EOF

log_success "Configuración de dnsmasq creada"

# Crear directorio y archivo de leases
log_info "Creando archivo de leases..."
mkdir -p /var/lib/misc
touch /var/lib/misc/dnsmasq.leases
chmod 644 /var/lib/misc/dnsmasq.leases
log_success "Archivo de leases creado"

# Crear archivo de configuración de hostapd LIMPIO
log_info "Creando configuración de hostapd..."
mkdir -p /etc/hostapd

cat > /etc/hostapd/hostapd.conf << EOF
# SENTINEL IoT - Configuración de hostapd
interface=$IOT_INTERFACE
driver=nl80211
ssid=$WIFI_SSID
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1

# Seguridad WPA2
wpa=2
wpa_passphrase=$WIFI_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP

# Control de acceso
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

log_success "Configuración de hostapd creada"

# Configurar hostapd para usar el archivo de configuración
log_info "Configurando daemon de hostapd..."
if [ -f /etc/default/hostapd ]; then
    sed -i 's|^#*DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd
fi
log_success "Daemon de hostapd configurado"

# Habilitar IP forwarding
log_info "Habilitando IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
log_success "IP forwarding habilitado"

# Configurar NAT
log_info "Configurando NAT..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$MAIN_INTERFACE" ]; then
    MAIN_INTERFACE="eth0"
fi
log_info "Interfaz principal detectada: $MAIN_INTERFACE"

nft add table ip nat 2>/dev/null || true
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true
nft add rule ip nat postrouting oifname "$MAIN_INTERFACE" masquerade 2>/dev/null || true
log_success "NAT configurado"

# Desactivar wpa_supplicant permanentemente
log_info "Desactivando wpa_supplicant..."
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl mask wpa_supplicant 2>/dev/null || true
log_success "wpa_supplicant desactivado"

# Configurar NetworkManager para no gestionar wlan1
log_info "Configurando NetworkManager..."
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    if ! grep -q "unmanaged-devices=interface-name:wlan1" /etc/NetworkManager/NetworkManager.conf; then
        cat >> /etc/NetworkManager/NetworkManager.conf << 'EOF'

[keyfile]
unmanaged-devices=interface-name:wlan1
EOF
        systemctl restart NetworkManager 2>/dev/null || true
        log_success "NetworkManager configurado"
    else
        log_success "NetworkManager ya estaba configurado"
    fi
else
    log_warning "NetworkManager no encontrado (puede ser normal)"
fi

echo ""
log_success "Configuración completada"
echo ""

# ============================================================================
# FASE 3: INICIAR SERVICIOS
# ============================================================================

echo -e "${YELLOW}═══ FASE 3: INICIANDO SERVICIOS ═══${NC}"
echo ""

# Iniciar hostapd
log_info "Iniciando hostapd..."
systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd 2>/dev/null || true
systemctl start hostapd
sleep 3

if systemctl is-active --quiet hostapd; then
    log_success "hostapd iniciado correctamente"
else
    log_error "hostapd no pudo iniciarse"
    log_info "Ver logs: journalctl -u hostapd -n 20"
    journalctl -u hostapd -n 20 --no-pager
    exit 1
fi

# Verificar que wlan1 está en modo Master
log_info "Verificando modo de $IOT_INTERFACE..."
if iwconfig $IOT_INTERFACE 2>/dev/null | grep -q "Mode:Master"; then
    log_success "$IOT_INTERFACE en modo Master"
else
    log_warning "$IOT_INTERFACE no está en modo Master, pero continuando..."
fi

# Iniciar dnsmasq
log_info "Iniciando dnsmasq..."
systemctl enable dnsmasq 2>/dev/null || true
systemctl start dnsmasq
sleep 2

if systemctl is-active --quiet dnsmasq; then
    log_success "dnsmasq iniciado correctamente"
else
    log_error "dnsmasq no pudo iniciarse"
    log_info "Ver logs: journalctl -u dnsmasq -n 20"
    journalctl -u dnsmasq -n 20 --no-pager
    exit 1
fi

echo ""
log_success "Servicios iniciados correctamente"
echo ""

# ============================================================================
# FASE 4: VERIFICACIÓN FINAL
# ============================================================================

echo -e "${YELLOW}═══ FASE 4: VERIFICACIÓN FINAL ═══${NC}"
echo ""

# Verificar servicios
echo -e "${BLUE}Estado de servicios:${NC}"
if systemctl is-active --quiet hostapd; then
    echo -e "  ${GREEN}✓${NC} hostapd: activo"
else
    echo -e "  ${RED}✗${NC} hostapd: inactivo"
fi

if systemctl is-active --quiet dnsmasq; then
    echo -e "  ${GREEN}✓${NC} dnsmasq: activo"
else
    echo -e "  ${RED}✗${NC} dnsmasq: inactivo"
fi

# Verificar interfaz
echo ""
echo -e "${BLUE}Configuración de $IOT_INTERFACE:${NC}"
ip addr show $IOT_INTERFACE | grep "inet " | awk '{print "  IP: " $2}'
iwconfig $IOT_INTERFACE 2>/dev/null | grep "Mode:" | awk '{print "  Modo: " $1 " " $2 " " $3 " " $4}'

# Verificar DHCP
echo ""
echo -e "${BLUE}Servidor DHCP:${NC}"
if ps aux | grep -v grep | grep dnsmasq > /dev/null; then
    echo -e "  ${GREEN}✓${NC} dnsmasq está corriendo"
else
    echo -e "  ${RED}✗${NC} dnsmasq NO está corriendo"
fi

# Mostrar información de conexión
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║          ¡Configuración completada con éxito!             ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Información de la red Wi-Fi:${NC}"
echo -e "  SSID: ${GREEN}$WIFI_SSID${NC}"
echo -e "  Contraseña: ${GREEN}$WIFI_PASSWORD${NC}"
echo -e "  Gateway: ${GREEN}$IOT_GATEWAY${NC}"
echo -e "  Rango DHCP: ${GREEN}192.168.100.10 - 192.168.100.250${NC}"
echo ""

echo -e "${YELLOW}Acceso al dashboard:${NC}"
echo -e "  Desde dispositivos conectados: ${GREEN}http://192.168.100.1:8000${NC}"
echo ""

echo -e "${YELLOW}Comandos útiles:${NC}"
echo "  Ver dispositivos conectados: ${GREEN}cat /var/lib/misc/dnsmasq.leases${NC}"
echo "  Ver logs de dnsmasq: ${GREEN}sudo journalctl -u dnsmasq -f${NC}"
echo "  Ver logs de hostapd: ${GREEN}sudo journalctl -u hostapd -f${NC}"
echo "  Reiniciar servicios: ${GREEN}sudo systemctl restart hostapd dnsmasq${NC}"
echo ""

log_info "Ahora puedes conectarte a la red '$WIFI_SSID' desde tus dispositivos"
log_info "Ejecuta 'sudo journalctl -u dnsmasq -f' para ver las conexiones en tiempo real"
echo ""

exit 0
