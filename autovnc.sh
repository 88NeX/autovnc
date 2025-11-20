 cat autovnc.sh
#!/bin/bash

# ==========================================================
# Настройка Ubuntu как headless-рабочей станции с VNC
# Пользователь: master
# Режим: X11 (Wayland отключён)
# Автовход + отключение спящего режима + VNC к реальному сеансу
# ==========================================================

set -e  # Завершать при любой ошибке

USERNAME="master"
VNC_PASSWD="ChangeMe123"  # <-- измените на свой пароль или оставьте для интерактивного ввода

# Проверка: запущен ли от root?
if [ "$EUID" -ne 0 ]; then
  echo "❌ Этот скрипт должен запускаться от root (или через sudo)."
  exit 1
fi

echo "🔧 Начинаем настройку..."

# === 1. Создание пользователя master (если не существует) ===
if ! id "$USERNAME" &>/dev/null; then
  echo "👤 Пользователь $USERNAME не найден — создаём..."
  adduser --disabled-password --gecos "" "$USERNAME"

  # Установка пароля (интерактивно или из переменной)
  if [ -z "$VNC_PASSWD" ] || [ "$VNC_PASSWD" == "ChangeMe123" ]; then
    echo "🔒 Установите пароль для пользователя $USERNAME (для входа в систему и VNC):"
    passwd "$USERNAME"
  else
    echo "$USERNAME:$VNC_PASSWD" | chpasswd
    echo "✅ Пароль для $USERNAME установлен."
  fi

  # Добавление в sudo (опционально)
  usermod -aG sudo "$USERNAME"
else
  echo "✅ Пользователь $USERNAME уже существует."
  if [ -n "$VNC_PASSWD" ] && [ "$VNC_PASSWD" != "ChangeMe123" ]; then
    echo "$USERNAME:$VNC_PASSWD" | chpasswd
    echo "✅ Пароль обновлён."
  fi
fi

USER_HOME="/home/$USERNAME"
USER_UID=$(id -u "$USERNAME")

# === 2. Отключение Wayland и настройка автовхода в GDM ===
GDM_CONF="/etc/gdm3/custom.conf"

if [ -f "$GDM_CONF" ]; then
  echo "🖥️ Отключаем Wayland и настраиваем автовход..."
  cp "$GDM_CONF" "${GDM_CONF}.bak.$(date +%Y%m%d_%H%M%S)"

  # Включить секцию [daemon], если отсутствует
  if ! grep -q "^\[daemon\]" "$GDM_CONF"; then
    echo -e "\n[daemon]" >> "$GDM_CONF"
  fi

  # Установить параметры
  sed -i 's/^#WaylandEnable=.*/WaylandEnable=false/' "$GDM_CONF"
  sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$GDM_CONF"
  if ! grep -q "^WaylandEnable=" "$GDM_CONF"; then
    sed -i "/^\[daemon\]/a WaylandEnable=false" "$GDM_CONF"
  fi

  sed -i 's/^#AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' "$GDM_CONF"
  sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' "$GDM_CONF"
  if ! grep -q "^AutomaticLoginEnable=" "$GDM_CONF"; then
    sed -i "/^\[daemon\]/a AutomaticLoginEnable=true" "$GDM_CONF"
  fi

  sed -i "s/^#AutomaticLogin=.*/AutomaticLogin=$USERNAME/" "$GDM_CONF"
  sed -i "s/^AutomaticLogin=.*/AutomaticLogin=$USERNAME/" "$GDM_CONF"
  if ! grep -q "^AutomaticLogin=" "$GDM_CONF"; then
    sed -i "/^\[daemon\]/a AutomaticLogin=$USERNAME" "$GDM_CONF"
  fi

  echo "✅ GDM настроен: Wayland отключён, автовход для $USERNAME включён."
else
  echo "⚠️ GDM не найден. Убедитесь, что установлена Ubuntu с GNOME."
fi

# === 3. Отключение спящего режима и блокировки (настройки пользователя) ===
echo "⏳ Отключаем спящий режим и блокировку экрана для $USERNAME..."

sudo -u "$USERNAME" dbus-run-session -- bash <<EOF
# Безопасное применение gsettings: игнорируем ошибки для отсутствующих ключей
safe_set() {
  if gsettings list-keys "\$1" | grep -q "^\$2\$"; then
    gsettings set "\$1" "\$2" "\$3"
  else
    echo "⚠️ Ключ '\$2' отсутствует в схеме '\$1' — пропускаем."
  fi
}

safe_set org.gnome.desktop.session idle-delay 0
safe_set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
safe_set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
safe_set org.gnome.desktop.screensaver idle-activation-enabled false
safe_set org.gnome.settings-daemon.plugins.power idle-dim false
safe_set org.gnome.settings-daemon.plugins.power dpms-enabled false
EOF

echo "✅ Энергосбережение и блокировка отключены."

# === 4. Установка x11vnc и autocutsel ===
echo "📦 Устанавливаем x11vnc и autocutsel..."
apt update
apt install -y x11vnc autocutsel

# === 5. Подготовка структуры для VNC ===
echo "🔐 Подготавливаем окружение VNC (пароль будет задан вручную)..."

USER_HOME="/home/$USERNAME"
USER_UID=$(id -u "$USERNAME")

# Создаём каталоги
mkdir -p "$USER_HOME/.vnc"
mkdir -p "$USER_HOME/.local/bin"
mkdir -p "$USER_HOME/.config/autostart"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.vnc" "$USER_HOME/.local" "$USER_HOME/.config"

# Создаём скрипт запуска (без пароля — он должен быть уже создан)
cat > "$USER_HOME/.local/bin/start-vnc.sh" <<EOF
#!/bin/bash

# Отключаем DPMS и экранную заставку
xset s off -dpms s noblank 2>/dev/null || true

# Синхронизация буферов
autocutsel -selection PRIMARY &
autocutsel -selection CLIPBOARD &

# Запуск x11vnc (требует ~/.vnc/passwd)
x11vnc -auth /run/user/$USER_UID/gdm/Xauthority \\
       -display :0 \\
       -rfbauth $USER_HOME/.vnc/passwd \\
       -rfbport 5900 \\
       -forever -loop -noxdamage -shared \\
       -o $USER_HOME/.vnc/x11vnc.log
EOF

chown "$USERNAME":"$USERNAME" "$USER_HOME/.local/bin/start-vnc.sh"
chmod +x "$USER_HOME/.local/bin/start-vnc.sh"

# Создаём .desktop для автозапуска
cat > "$USER_HOME/.config/autostart/x11vnc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=VNC Server (Real Session)
Exec=$USER_HOME/.local/bin/start-vnc.sh
StartupNotify=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

chown "$USERNAME":"$USERNAME" "$USER_HOME/.config/autostart/x11vnc.desktop"
chmod 644 "$USER_HOME/.config/autostart/x11vnc.desktop"

echo "✅ Окружение VNC подготовлено."
echo "❗ После перезагрузки и входа в сеанс выполните ОДИН РАЗ:"
echo "      x11vnc -storepasswd ~/.vnc/passwd"
echo "   и введите желаемый пароль для VNC (4–8 символов)."

# === 6. Открытие порта (если ufw активен) ===
if ufw status | grep -q "Status: active"; then
  echo "🌐 Открываем порт 5900 в ufw..."
  ufw allow 5900/tcp
fi

echo
echo "✅ ВСЁ ГОТОВО!"
echo
echo "🔹 После перезагрузки система автоматически:"
echo "   — Войдёт в сеанс $USERNAME под X11"
echo "   — Отключит спящий режим и блокировку"
echo "   — Запустит VNC-сервер на порту 5900"
echo
echo "🔹 Подключайтесь с Windows через VNC-клиент:"
echo "   Адрес: <IP_вашего_сервера>:5900"
echo "   Пароль: $VNC_PASSWD"
echo
echo "⚠️  Совет: для безопасности используйте SSH-туннель:"
echo "   ssh -L 5901:localhost:5900 $USERNAME@<IP>"
echo "   → затем подключайтесь к localhost:5901"
echo
echo "🔄 Выполняю перезагрузку через 10 секунд... (нажмите Ctrl+C для отмены)"
sleep 10
reboot
