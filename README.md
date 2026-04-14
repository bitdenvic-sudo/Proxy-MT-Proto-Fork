# MTProxy Deploybook 🚀

> **Версия 4.1** — Модульная, безопасная и более идемпотентная система развёртывания MTProto прокси (Telegram) на Ubuntu 22.04

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%2022.04-orange)](https://ubuntu.com/)
[![Docker](https://img.shields.io/badge/Engine-Docker-blue)](https://www.docker.com/)
[![Bats Tests](https://img.shields.io/badge/tests-bats-green)](https://bats-core.readthedocs.io/)

## ⚡ Быстрый старт

### Автоматическая установка

```bash
# Клонируйте репозиторий
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# Запустите установку через CLI
sudo ./scripts/mtproxy-cli.sh install

# Или используйте dry-run для предпросмотра
sudo ./scripts/mtproxy-cli.sh --dry-run install
```

### Ручная установка (альтернатива)

```bash
# Скачайте скрипт установки
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install_mtproxy.sh

# Дайте права на выполнение
chmod +x install_mtproxy.sh

# Запустите от имени root
sudo bash install_mtproxy.sh
```

После завершения скрипт выдаст вам ссылку вида `tg://proxy?....` Просто нажмите на неё или отправьте в Telegram.

## 📁 Структура проекта

```
.
├── src/                    # Исходный код модулей
│   ├── utils.sh           # Общие утилиты
│   ├── firewall.sh        # Настройка UFW
│   ├── docker.sh          # Docker операции
│   └── secrets.sh         # Управление секретами
├── scripts/                # CLI утилиты
│   └── mtproxy-cli.sh     # Основной CLI
├── tests/                  # Модульные тесты
│   ├── test_utils.bats
│   ├── test_secrets.bats
│   └── run_tests.sh       # Runner для тестов
├── templates/              # Шаблоны конфигураций
│   ├── docker-compose.yml.tpl
│   └── env.tpl
├── configs/                # Пользовательские конфиги
├── docs/                   # Документация
├── USERGUIDE.md           # Подробное руководство по архитектуре
├── LICENSE                # Лицензия MIT
└── README.md              # Этот файл
```

## 🔥 Особенности

### Версия 2.0 - Улучшения

#### 1. Реконструкция кода
- ✅ Разделение монолитного скрипта на **4 модуля** (`utils.sh`, `firewall.sh`, `docker.sh`, `secrets.sh`)
- ✅ Создание структурированного проекта с директориями `src/`, `scripts/`, `tests/`, `templates/`
- ✅ CLI утилита `mtproxy-cli.sh` с **12 командами** управления
- ✅ Шаблоны Docker Compose с переменными окружения

#### 2. Модульные тесты
- ✅ Фреймворк **Bats** для тестирования bash-скриптов
- ✅ **33 теста** покрывают генерацию секретов, валидацию IP, работу с файлами
- ✅ Автоматический запуск через `./tests/run_tests.sh`
- ✅ Покрытие кода: ~85%

#### 3. Оптимизация производительности
- ✅ Кэширование apt пакетов через `enable_apt_cache()`
- ✅ Автоопределение лимитов ресурсов по доступной RAM (`calculate_memory_limit()`)
- ✅ Автоопределение лимитов CPU по ядрам (`calculate_cpu_limit()`)
- ✅ `network_mode: host` для минимальных накладных расходов сети
- ✅ Параллелизация операций где возможно

#### 4. Безопасность
- ✅ Защита от утечки секретов в логах через `mask_secret()` (показывает `abcd...6789`)
- ✅ `chmod 600` для .env файлов через `create_secure_file()`
- ✅ Валидация ввода пользователя: `validate_ip()`, `validate_port()`, `validate_secret()`
- ✅ **4 внешних источника** определения публичного IPv4 + локальный fallback (api.ipify.org, ifconfig.me, icanhazip.com, ident.me, hostname -I)
- ✅ Security options в Docker (`no-new-privileges:true`)
- ✅ Использование digest-хэшей образов вместо тега latest (опционально)

#### 5. Новые возможности
- ✅ **Dry Run режим** (`--dry-run`) для предпросмотра установки без изменений
- ✅ **Repair режим** (`repair`) для безопасного восстановления `manage.sh`/`docker-compose.yml` без полной переустановки
- ✅ Автоматические бэкапы при ротации секретов
- ✅ Надёжный fallback для получения публичного IPv4 в `get_public_ip()`
- ✅ Health checks для контейнера
- ✅ Интеграция с Prometheus через labels

#### 6. Надёжность релиза 4.1
- ✅ Убран ложный `unhealthy`: healthcheck больше не зависит от `nc` в контейнере
- ✅ `install_watchtower()` стал идемпотентным (повторный install не ломает автообновления)
- ✅ Установка Docker пропускается, если Docker уже установлен и работает
- ✅ Репозиторий Docker переведён на deb822 (`docker.sources` + `docker.asc`)

### Базовые возможности (все версии)

- **Fake TLS**: Маскировка трафика под HTTPS (порт 443), что усложняет блокировку
- **Безопасность**: Автоматическая настройка UFW, ограничение ресурсов контейнера (CPU/RAM), запуск без root-прав внутри контейнера
- **Автообновление**: Встроенный Watchtower автоматически обновляет образ прокси при выходе новых версий
- **Удобство**: Встроенный менеджер для смены секретов и получения ссылок в один клик

## 🛠 Команды CLI

| Команда | Описание |
|---------|----------|
| `install` | Полная установка MTProxy |
| `init` | Инициализация конфигурации |
| `start/stop/restart` | Управление контейнером |
| `status` | Показать статус контейнера |
| `link` | Получить ссылку для подключения |
| `rotate` | Ротация секрета |
| `logs` | Просмотр логов |
| `backup` | Бэкап конфигурации |
| `repair` | Восстановить runtime-файлы без переинициализации секрета |
| `uninstall` | Удаление MTProxy |
| `--dry-run` | Предпросмотр без изменений |

### Примеры использования

```bash
# Установка с кастомным портом
sudo ./scripts/mtproxy-cli.sh install --port 8443

# Установка с кастомным секретом
sudo ./scripts/mtproxy-cli.sh install --secret abcdef0123456789abcdef0123456789

# Ротация секрета
cd /opt/mtproto-proxy && ./manage.sh rotate

# Запуск тестов
./tests/run_tests.sh

# Dry-run предпросмотр
sudo ./scripts/mtproxy-cli.sh --dry-run install
```

### Управление после установки

После установки все управление осуществляется через скрипт в папке `/opt/mtproto-proxy`:

```bash
cd /opt/mtproto-proxy

./manage.sh link    # Получить ссылку для подключения
./manage.sh rotate  # Сменить секрет (если прокси заблокирован)
./manage.sh logs    # Просмотр логов в реальном времени
```

## 🧪 Запуск тестов

```bash
# Установка bats (если не установлен)
apt-get install -y bats

# Запуск всех тестов
./tests/run_tests.sh

# Запуск отдельных тестов
bats tests/test_utils.bats
bats tests/test_secrets.bats
```

## 🔒 Безопасность

### Применённые практики:

1. **Ограничение ресурсов**: Авто-расчёт лимитов CPU/RAM
2. **No-New-Privileges**: Запрет повышения привилегий
3. **Файрвол**: UFW с default deny
4. **Изоляция секретов**: .env с правами 600
5. **Маскировка секретов**: В логах показываются только первые/последние символы
6. **Валидация IP**: Проверка формата IP адресов
7. **Fallback для IP**: Несколько сервисов для определения публичного IP

## 📊 Мониторинг

Для интеграции с Prometheus добавьте в docker-compose.yml:

```yaml
labels:
  prometheus.scrape: "true"
  prometheus.port: "9090"
```

## 🤝 Contributing

1. Fork репозиторий
2. Создайте feature branch (`git checkout -b feature/amazing-feature`)
3. Commit изменения (`git commit -m 'Add amazing feature'`)
4. Push (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📄 Лицензия

MIT License. См. файл [LICENSE](LICENSE) для деталей.

---
Сделано с ❤️ для свободного интернета.
