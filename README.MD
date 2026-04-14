# MTProto Proxy Deploybook 🚀

> Простое, безопасное и автоматизированное развёртывание MTProto прокси (Telegram) на Ubuntu 22.04 с использованием Docker.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%2022.04-orange)](https://ubuntu.com/)
[![Docker](https://img.shields.io/badge/Engine-Docker-blue)](https://www.docker.com/)

## ⚡ Быстрый старт

Разверните свой собственный прокси за 1 минуту с помощью автоматического скрипта.

```bash
# Скачайте скрипт установки
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install_mtproxy.sh

# Дайте права на выполнение
chmod +x install_mtproxy.sh

# Запустите от имени root
sudo bash install_mtproxy.sh
```

После завершения скрипт выдаст вам ссылку вида tg://proxy?.... Просто нажмите на неё или отправьте в Telegram.
📁 Структура репозитория

    README.md — Этот файл (быстрый старт).
    USERGUIDE.md — Подробное руководство
     по архитектуре, ручной настройке и управлению.
    install_mtproxy.sh — Скрипт полной автоматизации.
    LICENSE — Лицензия MIT.

🔥 Особенности

    Fake TLS: Маскировка трафика под HTTPS (порт 443), что усложняет блокировку.
    Безопасность: Автоматическая настройка UFW, ограничение ресурсов контейнера (CPU/RAM), запуск без root-прав внутри контейнера.
    Автообновление: Встроенный Watchtower автоматически обновляет образ прокси при выходе новых версий.
    Удобство: Встроенный менеджер manage.sh для смены секретов и получения ссылок в один клик.

🛠 Управление
После установки все управление осуществляется через скрипт в папке /opt/mtproto-proxy:

```bash
cd /opt/mtproto-proxy

./manage.sh link    # Получить ссылку для подключения
./manage.sh rotate  # Сменить секрет (если прокси заблокирован)
./manage.sh logs    # Просмотр логов в реальном времени
```

📄 Лицензия
Этот проект распространяется под лицензией MIT. См. файл LICENSE
 для деталей.
Сделано с ❤️ для свободного интернета.
