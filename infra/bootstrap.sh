#!/usr/bin/env bash
# Sıfırdan bir üretim sunucusu kurar (Ubuntu 22.04+ / AWS EC2).
#
# Mevcut sunucu elle kurulmuştu; ölmesi hâlinde yeniden kurmak kafadaki
# bilgiye bağlıydı. Bu betik o bilgiyi yazıya döker.
#
# Kullanım (yeni sunucuda, root olmayan kullanıcıyla):
#   git clone https://github.com/bahribirer/footttball.git /srv/tikitakatoe
#   cd /srv/tikitakatoe && ./infra/bootstrap.sh
#
# Betiğin YAPMADIKLARI — bunlar elle taşınmalı:
#   * backend/data/tikitakapi.db     oyuncu veritabanı (depoda değil)
#   * infra/certbot/conf/            TLS sertifikaları
#   * DNS kaydının yeni IP'ye çevrilmesi
#
# Betik yeniden çalıştırılabilir: kurulu olanı atlar.

set -euo pipefail

echo "▶ Sistem paketleri"
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg git python3 python3-venv

# --- Docker ------------------------------------------------------------
if ! command -v docker > /dev/null; then
  echo "▶ Docker kuruluyor"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "  ✓ Docker kuruldu — grup üyeliği için yeniden oturum açın"
else
  echo "✓ Docker zaten kurulu"
fi

# --- Dizinler ----------------------------------------------------------
echo "▶ Dizinler"
mkdir -p backend/data/jobs infra/certbot/conf infra/certbot/www
# run_job.sh durum dosyalarını buraya yazıyor; /health oradan okuyor.
touch backend/data/jobs/.keep

# --- Takas alanı -------------------------------------------------------
# Makinede 1.9 GB RAM var; yoğun anlarda OOM riski taşıyor.
if [ ! -f /swapfile ]; then
  echo "▶ 2 GB takas alanı"
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile > /dev/null
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
else
  echo "✓ Takas alanı zaten var"
fi

# --- Güvenlik duvarı ---------------------------------------------------
if command -v ufw > /dev/null; then
  echo "▶ Güvenlik duvarı"
  sudo ufw allow OpenSSH > /dev/null
  sudo ufw allow 80/tcp > /dev/null
  sudo ufw allow 443/tcp > /dev/null
  sudo ufw --force enable > /dev/null
  echo "  ✓ 22/80/443 açık"
fi

# --- Eksikleri bildir --------------------------------------------------
echo
echo "▶ Elle tamamlanması gerekenler"
MISSING=0
if [ ! -f backend/data/tikitakapi.db ]; then
  echo "  ✗ backend/data/tikitakapi.db yok — eski sunucudan kopyalayın"
  MISSING=1
fi
if [ ! -d infra/certbot/conf/live ]; then
  echo "  ✗ infra/certbot/conf/live yok — sertifikaları taşıyın ya da certbot çalıştırın"
  MISSING=1
fi
[ "$MISSING" = "0" ] && echo "  ✓ hepsi yerinde"

echo
echo "Sonraki adım:  ./infra/deploy.sh main"
