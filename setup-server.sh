#!/bin/bash
# =============================================================================
#  Первичная настройка сервера Debian 12 / Ubuntu 22.04+
#  Репозиторий: https://github.com/yulnet/server-setup
#  Использование:
#    curl -Ls https://raw.githubusercontent.com/yulnet/server-setup/main/setup-server.sh -o setup-server.sh
#    chmod +x setup-server.sh
#    bash setup-server.sh
# =============================================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

# --- Проверка root ---
if [ "$(id -u)" -ne 0 ]; then
    err "Запустите скрипт от root."
    exit 1
fi

# --- Проверка ОС ---
if [ ! -f /etc/debian_version ]; then
    err "Скрипт поддерживает только Debian / Ubuntu."
    exit 1
fi

log "Начало настройки сервера..."

# =============================================================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ
# =============================================================================
log "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt upgrade -y
log "Система обновлена."

# =============================================================================
# 2. БАЗОВЫЕ ПАКЕТЫ
# =============================================================================
log "Установка базовых пакетов..."
apt install -y \
    curl wget nano ufw fail2ban unzip socat cron \
    ca-certificates openssl tzdata net-tools htop jq
log "Базовые пакеты установлены."

# =============================================================================
# 3. ЧАСОВОЙ ПОЯС
# =============================================================================
log "Установка часового пояса Europe/Moscow..."
timedatectl set-timezone Europe/Moscow
log "Часовой пояс: $(timedatectl show --property=Timezone --value)"

# =============================================================================
# 4. BBR + ОПТИМИЗАЦИЯ TCP
# =============================================================================
log "Включение BBR и оптимизация сетевого стека..."

SYSCTL_FILE="/etc/sysctl.d/99-network-tuning.conf"

cat > "$SYSCTL_FILE" << 'EOF'
# --- Network Optimization (BBR + TCP tuning) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.tcp_rmem = 4096 87380 26214400
net.ipv4.tcp_wmem = 4096 65536 26214400
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
vm.swappiness = 10
EOF

sysctl --system > /dev/null 2>&1
log "BBR активирован: $(sysctl -n net.ipv4.tcp_congestion_control)"

# =============================================================================
# 5. ФАЙРВОЛ (UFW) — БЕЗОПАСНОЕ ВКЛЮЧЕНИЕ
# =============================================================================
log "Настройка файрвола UFW..."

# Определяем порт SSH, чтобы не потерять доступ
SSH_PORT=$(ss -tlnp | grep -oP 'sshd.*:\K[0-9]+' | head -1)
SSH_PORT=${SSH_PORT:-22}

ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw --force enable

log "UFW включён. SSH разрешён на порту: ${SSH_PORT}"
ufw status verbose

# =============================================================================
# 6. FAIL2BAN
# =============================================================================
log "Настройка Fail2Ban..."

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ${SSH_PORT}
filter  = sshd
logpath = %(sshd_log)s
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
log "Fail2Ban запущен."

# =============================================================================
# 7. ОТКЛЮЧЕНИЕ MOTD / ПРИВЕТСТВИЙ
# =============================================================================
log "Отключение приветственных сообщений..."

touch /root/.hushlogin
systemctl disable --now motd-news.timer 2>/dev/null || true
chmod -x /etc/update-motd.d/* 2>/dev/null || true
[ -f /etc/motd ] && cp /etc/motd /etc/motd.bak && echo > /etc/motd

log "Приветствия отключены."

# =============================================================================
# 8. ОЧИСТКА СИСТЕМЫ
# =============================================================================
log "Очистка системы..."
apt clean
apt autoremove --purge -y
log "Очистка завершена."

# =============================================================================
# 9. ИТОГИ
# =============================================================================
echo ""
echo "======================================================================"
echo -e "${GREEN}  БАЗОВАЯ НАСТРОЙКА ЗАВЕРШЕНА${NC}"
echo "======================================================================"
echo ""
echo "  Что сделано:"
echo "   ✓ Система обновлена"
echo "   ✓ Базовые пакеты установлены"
echo "   ✓ Часовой пояс: Europe/Moscow"
echo "   ✓ BBR + оптимизация TCP"
echo "   ✓ UFW: разрешён только SSH (порт ${SSH_PORT})"
echo "   ✓ Fail2Ban: защита SSH"
echo "   ✓ MOTD и приветствия отключены"
echo "   ✓ Кэш APT и мусор удалены"
echo ""
echo "  СЛЕДУЮЩИЕ ШАГИ (вручную):"
echo "   1. Перезагрузить сервер:  reboot"
echo "   2. Проверить BBR:         sysctl net.ipv4.tcp_congestion_control"
echo "   3. Создать SSH-ключ и отключить вход по паролю"
echo "   4. Установить 3x-ui:"
echo "      bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
echo ""
echo "  ⚠  Отключение логов (rsyslog/journald) НЕ выполнено."
echo "     Сделайте это отдельно после проверки, что всё работает."
echo "     Скрипт: disable-logs.sh"
echo "======================================================================"
