#!/usr/bin/env bash
# Prepara una VM Ubuntu 22.04/24.04 (GCP Compute Engine) para correr Brevetto con Docker Compose.
# Uso, dentro de la VM:  bash deploy/setup-vm.sh
set -euo pipefail

echo "==> Instalando Docker Engine y el plugin Compose"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER" || true

echo "==> Creando 2 GB de swap (la compilación de Next.js necesita memoria)"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "==> Listo. Cierre la sesión SSH y vuelva a entrar para usar 'docker' sin sudo."
echo "    Luego, desde la carpeta BrevettoGCP:"
echo "           cp deploy/.env.prod.example .env.prod && nano .env.prod"
echo "           docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build"
