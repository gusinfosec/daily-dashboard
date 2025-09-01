#!/usr/bin/env bash
set -euo pipefail

APP_NAME="daily-dashboard"
APP_DIR="/opt/${APP_NAME}"
ENV_FILE="/etc/${APP_NAME}.env"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
PORT="5000"

# Your OpenWeather key (already filled in)
OWM_API_KEY="258cd989d922208d222bcda6c3affcb1"
CITY="Boca Raton"
COUNTRY="US"
UNITS="imperial"

# --- detect container engine ---
CE=""
if command -v podman >/dev/null 2>&1; then
  CE="podman"
elif command -v docker >/dev/null 2>&1; then
  CE="docker"
fi

function try_install_docker() {
  echo "→ Attempting to install Docker..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update -y
    sudo apt install -y docker.io
    sudo systemctl enable --now docker
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y docker
    sudo systemctl enable --now docker
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm docker
    sudo systemctl enable --now docker
  else
    echo "!! Could not auto-install Docker (unknown package manager). Install Docker or Podman manually and re-run."
    exit 1
  fi
}

if [[ -z "${CE}" ]]; then
  try_install_docker
  if command -v docker >/dev/null 2>&1; then
    CE="docker"
  else
    echo "!! No container engine found after attempted install."
    exit 1
  fi
fi

echo "→ Using container engine: ${CE}"

# --- confirm app files present ---
NEEDED=("Dockerfile" "app.py" "requirements.txt" "templates/index.html")
for f in "${NEEDED[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "!! Missing $f. Run this from the project folder with the app files."
    exit 1
  fi
done

# --- install app files ---
echo "→ Installing to ${APP_DIR}"
sudo mkdir -p "${APP_DIR}/templates"
sudo cp app.py requirements.txt Dockerfile "${APP_DIR}/"
sudo cp -r templates/* "${APP_DIR}/templates/"
sudo chown -R root:root "${APP_DIR}"

# --- build image ---
echo "→ Building image ${APP_NAME}:latest"
cd "${APP_DIR}"
sudo ${CE} build -t "${APP_NAME}:latest" .

# --- write env file ---
echo "→ Writing ${ENV_FILE}"
sudo bash -c "cat > '${ENV_FILE}'" <<EOF
OWM_API_KEY=${OWM_API_KEY}
CITY=${CITY}
COUNTRY=${COUNTRY}
UNITS=${UNITS}
PORT=${PORT}
EOF
sudo chmod 600 "${ENV_FILE}"

# --- systemd service ---
echo "→ Creating systemd service ${SERVICE_FILE}"
RUN_BIN="$(command -v ${CE})"

sudo bash -c "cat > '${SERVICE_FILE}'" <<EOF
[Unit]
Description=${APP_NAME} container
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=${ENV_FILE}
ExecStartPre=${RUN_BIN} rm -f ${APP_NAME}
ExecStart=${RUN_BIN} run --rm --name ${APP_NAME} \\
  --env-file ${ENV_FILE} \\
  -p \${PORT}:5000 \\
  ${APP_NAME}:latest
ExecStop=${RUN_BIN} stop ${APP_NAME}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "${APP_NAME}"

# --- desktop launcher (optional) ---
DESKTOP_DIR="${HOME}/.local/share/applications"
mkdir -p "${DESKTOP_DIR}"
LAUNCHER="${DESKTOP_DIR}/${APP_NAME}.desktop"
cat > "${LAUNCHER}" <<EOF
[Desktop Entry]
Type=Application
Name=Daily Dashboard
Comment=Your weather + quote dashboard
Exec=xdg-open http://localhost:${PORT}
Icon=utilities-terminal
Terminal=false
Categories=Utility;Network;
EOF

echo
echo "✅ Installed!"
echo "   Service:    ${APP_NAME} (systemd) — started"
echo "   URL:        http://localhost:${PORT}"
echo "   Env file:   ${ENV_FILE}"
echo "   Launcher:   ${LAUNCHER}"
echo
echo "Tips:"
echo " - Edit ${ENV_FILE} if you want to change city/units, then: sudo systemctl restart ${APP_NAME}"
echo " - See logs: sudo journalctl -u ${APP_NAME} -f"
