```markdown
# 📘 User Guide: MTProto Proxy Deployment

Это подробное руководство администратора по развёртыванию, настройке и обслуживанию MTProto прокси на Ubuntu 22.04.

## 📋 Оглавление

1. [Архитектура](#архитектура)
2. [Требования](#требования)
3. [Автоматическая установка](#автоматическая-установка)
4. [Ручная установка (Step-by-Step)](#ручная-установка)
   - [Подготовка ОС](#подготовка-ос)
   - [Установка Docker](#установка-docker)
   - [Конфигурация и секреты](#конфигурация-и-секреты)
   - [Запуск](#запуск)
5. [Управление и обслуживание](#управление-и-обслуживание)
6. [Безопасность (Hardening)](#безопасность)
7. [Устранение неполадок](#устранение-неполадок)

---

## 🏗 Архитектура

Решение базируется на официальном образе `telegrammessenger/proxy`.

```text
[Telegram Client] 
       ⬇️ (Зашифрованный трафик MTProto over Fake TLS)
[Ubuntu 22.04 Server] :443
       ⬇️ (UFW Firewall)
[Docker Container] (mtproxy)
       ⬇️ (Resource Limits: 512MB RAM, 1 CPU)
[Host System]

Ключевые компоненты:

    Port 443: Стандартный порт HTTPS. Прокси маскирует свой трафик под посещение сайта www.telegram.org, что позволяет обходить простые эвристические блокировки.
    Docker Compose: Оркестрация контейнера с параметрами безопасности.
    Watchtower: Фоновый сервис для автоматического обновления образов.

🛠 Требования

    ОС: Ubuntu 22.04 LTS (чистая установка рекомендуется).
    Доступ: Root или пользователь с правами sudo.
    Сеть: Статический IP адрес.
    Порты: 
        22/tcp (SSH) — обязательно.
        443/tcp (Прокси) — обязательно.
    Ресурсы: Минимум 512 MB RAM, 1 vCPU.

🚀 Автоматическая установка
Используйте этот метод для быстрого развёртывания. Скрипт выполнит все шаги ручной установки автоматически.

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install_mtproxy.sh
chmod +x install_mtproxy.sh
sudo bash install_mtproxy.sh
```

Скрипт спросит подтверждение на создание пользователя proxyadmin и настройку файрвола. После завершения он выведет ссылку для подключения.
📖 Ручная установка
Если вы предпочитаете контролировать каждый этап или хотите понять процесс глубже.
Подготовка ОС

    1. Обновление пакетов:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ufw fail2ban openssl xxd jq
```
    2. Настройка пользователя (Best Practice):
Не работайте под root постоянно.
```bash
sudo adduser --disabled-password --gecos "" proxyadmin
sudo usermod -aG sudo proxyadmin
```

    3. Настройка файрвола (UFW):

    ```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment "SSH"
sudo ufw allow 443/tcp comment "MTProxy"
sudo ufw --force enable
```

Установка Docker
Устанавливаем официальную версию Docker Engine (избегаем snap-пакетов):

```bash
# Удаление старых версий
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

# Добавление ключа GPG
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Добавление репозитория
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER
newgrp docker
```

Конфигурация и секреты

    1. Создание директории:

    ```bash
mkdir -p /opt/mtproto-proxy/{config,data}
cd /opt/mtproto-proxy
```
    2. Генерация секрета:
    Секрет должен быть hex-строкой (32 символа для 16 байт).

    ```bash
SECRET=$(head -c 16 /dev/urandom | xxd -p | tr -d '\n')
echo "Сгенерированный секрет: $SECRET"
```
    3.Создание .env:

    ```bash
cat > .env <<EOF
PORT=443
SECRET=${SECRET}
TAG=d00df00d
TLS_DOMAIN=www.telegram.org
EOF
chmod 600 .env
```
    4.Создание docker-compose.yml:

    ```yaml
version: "3.9"
services:
  mtproxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproxy
    restart: unless-stopped
    network_mode: host
    env_file: .env
    environment:
      - PORT=${PORT}
      - SECRET=${SECRET}
      - TAG=${TAG}
      - TLS_DOMAIN=${TLS_DOMAIN}
    volumes:
      - ./config:/config
      - .//data
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
```

Запуск

```bash
docker compose up -d
```

Для автообновления установите Watchtower:

```bash
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 86400 \
  --cleanup \
  mtproxy
```

🎛 Управление и обслуживание
В папке /opt/mtproto-proxy создается скрипт manage.sh.
Команда
	
Описание
./manage.sh link
	
Показать ссылку tg:// и https:// для подключения.
./manage.sh rotate
	
Сгенерировать новый секрет, обновить конфиг и перезапустить прокси.
./manage.sh logs
	
Вывод логов контейнера в реальном времени.
./manage.sh stop
	
Остановить контейнер.
./manage.sh start
	
Запустить контейнер.
Как получить ссылку вручную:

```bash
IP=$(curl -s ifconfig.me)
SECRET=$(grep SECRET .env | cut -d= -f2)
echo "tg://proxy?server=$IP&port=443&secret=$SECRET"
```

🔒 Безопасность
В этом решении применены следующие практики безопасности:

    1. Ограничение ресурсов (DoS Protection):
    В docker-compose.yml установлены лимиты: memory: 512M, cpus: '1.0'. Это предотвращает захват всех ресурсов сервера при атаке.
    2. No-New-Privileges:
    Опция security_opt: - no-new-privileges:true запрещает процессам внутри контейнера повышать свои привилегии, даже если найдут уязвимость.
    3. Файрвол:
    UFW настроен в режим "Default Deny". Открыты только необходимые порты.
    4. Изоляция секретов:
    Файл .env содержит чувствительные данные и имеет права доступа 600 (только владелец может читать).
    5. Логирование:
    Настроена ротация логов (max 3 файла по 10Мб), чтобы злоумышленник не мог переполнить диск логами.

🛠 Устранение неполадок
Контейнер не запускается
Проверьте логи:

```bash
docker logs mtproxy
```

Частая причина: Порт 443 занят другим сервисом (nginx, apache). Остановите их или смените порт в .env (но тогда потребуется открыть новый порт в UFW).
Telegram не подключается

    1.Проверьте статус файрвола: sudo ufw status. Порт 443 должен быть ALLOW.
    2.Проверьте правильность секрета. В ссылке не должно быть пробелов.
    3.Убедитесь, что ваш провайдер не блокирует исходящие соединения на порт 443 нестандартным образом (редко).

Ошибка "Secret not found"
Убедитесь, что вы находитесь в директории /opt/mtproto-proxy и файл .env существует. Проверьте права доступа.
Сервер тормозит
Проверьте потребление ресурсов: docker stats. Если контейнер упирается в лимиты, увеличьте их в docker-compose.yml и сделайте docker compose up -d.
📜 Лицензия
MIT License. См. корневой файл LICENSE.
