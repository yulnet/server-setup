#!/bin/bash
# =============================================================================
#  Отключение логирования. Запускать ТОЛЬКО когда сервер стабильно работает.
#  ВНИМАНИЕ: после этого диагностика проблем будет крайне затруднена.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Запустите от root.${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠  Это действие отключит rsyslog и journald.${NC}"
echo -e "${YELLOW}   Диагностика проблем станет крайне сложной.${NC}"
read -p "Продолжить? (yes/N): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Отменено."
    exit 0
fi

# rsyslog
if systemctl list-unit-files | grep -q rsyslog.service; then
    systemctl stop rsyslog
    systemctl disable rsyslog
    echo -e "${GREEN}[✓]${NC} rsyslog отключён."
fi

# journald
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/discard.conf << 'EOF'
[Journal]
Storage=none
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToWall=no
EOF

systemctl restart systemd-journald
echo -e "${GREEN}[✓]${NC} journald переведён в Storage=none."

# Очистка старых логов
journalctl --vacuum-time=1s 2>/dev/null || true
rm -f /var/log/syslog /var/log/messages /var/log/auth.log /var/log/kern.log 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} Накопленные логи очищены."
