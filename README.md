# Bannerlord Co-op Campaign у CubeCoders AMP

Експериментальний Generic deployment template для Ubuntu/Debian amd64: один
AMP-контейнер із Wine, Xvfb і PTY. Власний Dockerfile не потрібен.

**Ще не перевірено на справжньому AMP:** Create Instance, entitled Workshop
download, готовність гри, підключення гравців, Stop зі збереженням і відновлення
кампанії. Steam login і Steam Guard тепер проходять через діалог AMP Update.
Цей репозиторій не є підтвердженим production-ready рішенням.

## Додати шаблон у ADS

Додайте опублікований репозиторій у
**ADS → Configuration → Instance Deployment → Configuration Repositories**:

```text
ZifeRRoT/MnB-Bannerlord-co-op-AMP-template:main
```

Натисніть **Fetch Latest**, оновіть браузер. У Create Instance шукайте
`Community / Bannerlord Co-op Campaign (experimental)`, Docker залиште увімкненим.

Для локального підключення без GitHub знайдіть реальний каталог ADS:

```bash
ampinstmgr list
find /home/amp /opt -type d -name DeploymentTemplates 2>/dev/null
```

У клоні цього репозиторію, від імені системного користувача ADS:

```bash
read -r -p 'Absolute ADS DeploymentTemplates directory: ' DEPLOYMENT_DIR
test -d "$DEPLOYMENT_DIR" || exit 1
LOCAL_TEMPLATE="$DEPLOYMENT_DIR/LOCAL-BannerlordCoop-main"
mkdir -p "$LOCAL_TEMPLATE"
cp manifest.json bannerlord-coop.kvp bannerlord-coopconfig.json \
  bannerlord-coopmetaconfig.json bannerlord-coopports.json \
  bannerlord-coopupdates.json "$LOCAL_TEMPLATE/"
```

Додайте repository `LOCAL/BannerlordCoop:main`, натисніть Fetch, оновіть сторінку.
LOCAL-механізм описаний офіційною wiki; вашу збірку AMP 2.8.0.10 ще треба перевірити.
Не використовуйте припущений шлях `/home/amp/.ampdata` без перевірки.

## Перше встановлення нового інстансу

Вимкніть автозапуск нового інстансу до авторизації. У налаштуваннях заповніть
Campaign save, Autosave minutes, Engine region. **Steam username (optional)**
залиште порожнім: один акаунт із кешу AMP вибирається автоматично. Це поле
потрібне лише для вибору між кількома вже авторизованими акаунтами.
Ручне копіювання скриптів, raw GitHub URL і вхід у контейнер для login не потрібні.

## Steam Guard, встановлення й оновлення

Потрібен Steam-акаунт із Bannerlord (`261550`). Завантажується Workshop item
`3770450698`, який сторонній dedicated launcher використовує як джерело
`DedicatedServer`, bundled engine та .NET. Повний клієнт через app_update не потрібен.

Натисніть **Update** у новому інстансі. У штатному діалозі AMP введіть Steam login,
пароль та Steam Guard. Пароль вводиться саме у діалозі, а не в Console або JSON.
AMP може знову запитувати дані при наступних Update: увімкнено
`SteamForceLoginPrompt=True`, як у штатному upstream-шаблоні.

Послідовність Update:

1. Встановлення вбудованого runtime.
2. Штатний `SteamCMD` stage для app `228980` (Steamworks Common Redistributables),
   який викликає авторизацію AMP. Може додатково завантажити Windows redistributables;
   вони не запускаються й не є повним клієнтом Bannerlord.
3. `Executable` stage завантажує Co-op Workshop через встановлений AMP SteamCMD,
   використовуючи ту саму `.virtualhome`. У нього stdin закрито та ввімкнено
   `NoPromptForPassword`: пароль ніколи не запитується через Python/AMP Console.

Цей підхід повторює Linux Workshop Login/Download stages офіційного шаблону
`halo3-project-reclaimer`. Python не копіює токен, не друкує config.vdf і не
використовує кеш інших інстансів. Якщо токена немає/він застарів, повторіть Update
й авторизацію у вікні AMP. Якщо mobile approval не створює reusable cache,
введіть код Steam Guard у діалозі AMP, як рекомендує upstream-шаблон.

Update блокується на помилці. Start не оновлює гру автоматично.
Точна версія Workshop не закріплена, тому до Update робіть backup.
Runtime-файл встановлюється з вбудованої у template перевіреної копії.
Після редагування runtime.py розробник має виконати
`python3 tools/build_template.py`; `--check` перевіряє відповідність.

## Перехід із попереднього шаблону

Після публікації нової ревізії:

1. Штатно зупиніть гру й зробіть backup.
2. ADS → Configuration → Instance Deployment → **Fetch Latest**.
3. На плитці **саме Co-op інстансу** натисніть правою кнопкою → **Refresh Configuration**.
4. Відкрийте інстанс і натисніть **Update**; пройдіть Steam login/Guard у діалозі AMP.
5. Після успішного Update натисніть Start.

Звичайна кнопка Update не оновлює сам template: потрібен Refresh Configuration.
Старі сейви, конфігурація й Wine prefix не переміщуються і не видаляються.
Кеш попереднього ручного login у `bannerlord-coop/steam` не переноситься:
авторизуйтеся через AMP один раз. Стара копія гри залишається fallback для Start,
але після успішного Update нові Workshop-файли мають пріоритет. Це тимчасово може
подвоїти зайняте грою місце; runtime сам старі файли не видаляє.

## Запуск, консоль і порти

Start створює persistent Wine prefix, копіює `default_new_game.sav` лише за
відсутності обраного сейву й читає справжній Coop module ID з `SubModule.xml`.
Додаткові Workshop-моди поки не підтримуються.

| Allocation | Призначення |
| --- | --- |
| UDP 4200 | порт Co-op для підключення гравців |
| UDP 4201 | дочірній порт із `Offset=1`, для dedicated build |
| UDP 7210 | engine custom-server, не порт входу гравців |

Фактичні AMP allocations передаються як `GamePort` і `EnginePort`; runtime
перевіряє діапазон та відсутність накладання. Другий інстанс повинен мати власну
пару й окремий engine allocation. TCP не додано.
Офіційна інструкція описує один публічний UDP порт; пару вимагає сторонній
dedicated launcher. Потребу публічно відкривати engine/другий порт ще не доведено.

Ready regex очікує `coop server up, waiting for clients` із стороннього egg.
Якщо Workshop build змінив повідомлення, перевірте реальний лог і змініть regex;
наявність процесу не є доказом готовності приймати гравців.

Очікувані команди dedicated build: `help`, `status`, `players`, `save`, `stop`.
Звірте список `help`/`@DS@` фактично встановленої версії. AMP Stop надсилає `stop`
і чекає 180 секунд. За стороннім upstream це записує shutdown save; реальна
кампанія тут ще не тестувалася. Force Stop не гарантує збереження.

Runtime виконує exec → xvfb-run → script → Wine engine, зберігаючи stdin/stdout.
`script --return` надає Wine PTY й передає exit code; echo команд вимкнено,
а inlcr перетворює LF із AMP на CR для Windows console input.
Фоновий від'єднаний запуск гри, Docker socket і systemd не використовуються.

## Persistent дані та пароль входу

| Шлях від кореня інстансу | Вміст |
| --- | --- |
| `bannerlord-coop/data/Game Saves/` | `.sav`, однойменні `.json`, backups |
| `bannerlord-coop/data/logs/` | логи мода |
| `bannerlord-coop/data/server-config.json` | пароль входу та налаштування |
| `bannerlord-coop/data/mod-config.json` | налаштування мода |
| `bannerlord-coop/.wine/` | Wine prefix |
| `bannerlord-coop/steamcmd.sh` | SteamCMD, встановлений AMP |
| `.virtualhome/Steam/` | **секретний кеш AMP Steam**, можливі Workshop-файли |
| `bannerlord-coop/workshop/` | цільове розміщення нових Workshop-файлів |
| `bannerlord-coop/steam/` | попереднє розміщення гри/кешу, якщо вже було встановлено |

Щоб імпортувати кампанію, зупиніть інстанс, перенесіть `.sav` **разом із
однойменним `.json`** у Game Saves і задайте ім'я без розширення. Наявний сейв
не перезаписується. Ім'я підтримує літери ASCII, цифри, `_`, `-`.

Для пароля входу після першого запуску й Stop відредагуйте `password` у
`data/server-config.json`. Використовуйте стандартний JSON без коментарів.
Runtime зберігає невідомі поля й пароль, перевизначаючи порт/ім'я/автозбереження.
Некоректний JSON спричиняє помилку без стирання файлу.

Після штатного Stop створіть приватну резервну копію як власник інстансу:

```bash
read -r -p 'Absolute Co-op AMP instance directory: ' INSTANCE_DIR
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
BACKUP_FILE="$HOME/bannerlord-coop-$(date +%Y%m%d-%H%M%S).tar.gz"
umask 077
tar -C "$INSTANCE_DIR" -czf "$BACKUP_FILE" bannerlord-coop .virtualhome
```

Архів містить Steam-токен і паролі. Для відкату зупиніть лише цей інстанс і його
контейнер. Перемістіть поточні каталоги bannerlord-coop і .virtualhome у нові каталоги поруч,
розпакуйте перевірений backup у INSTANCE_DIR, перевірте власника, запустіть.
Відновлюйте engine, runtime й дані разом; нова версія мода може змінити формат сейвів.

Команди відкату після зупинки гри через Stop і зупинки самого Co-op інстансу в ADS:

```bash
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
read -r -p 'Absolute backup archive path: ' BACKUP_FILE
test -f "$BACKUP_FILE" || exit 1
tar -tzf "$BACKUP_FILE"  # перевірте свій архів: bannerlord-coop/ і .virtualhome/
mv "$INSTANCE_DIR/bannerlord-coop" \
  "$INSTANCE_DIR/bannerlord-coop.before-rollback-$(date +%Y%m%d-%H%M%S)"
if [ -d "$INSTANCE_DIR/.virtualhome" ]; then
  mv "$INSTANCE_DIR/.virtualhome" \
    "$INSTANCE_DIR/.virtualhome.before-rollback-$(date +%Y%m%d-%H%M%S)"
fi
tar -xzf "$BACKUP_FILE" -C "$INSTANCE_DIR"
```

Після цього запустіть цей інстанс через ADS і перевірте кампанію.

## Тести й діагностика

Із кореня репозиторію в Linux shell з Docker:

```bash
docker run --rm --platform linux/amd64 --entrypoint python3 \
  --mount "type=bind,source=$PWD,target=/work,readonly" \
  -w /work -e PYTHONDONTWRITEBYTECODE=1 \
  cubecoders/ampbase:wine-stable -m unittest discover -s tests -v
docker run --rm --platform linux/amd64 --entrypoint python3 \
  --mount "type=bind,source=$PWD,target=/work,readonly" \
  cubecoders/ampbase:wine-stable /work/tests/container_smoke.py
```

Smoke-тест перевіряє `stop`/exit code тестового
PTY-процесу, ініціалізує Wine prefix і перевіряє ввід `stop` Windows cmd через
Wine у тимчасовому контейнері. Це не тест гри.
Штатний Steam login потребує реального AMP-сеансу й тут не емулюється.

Локально раніше пройдено: SteamCMD bootstrap/запуск без login, Python PTY stop/exit code,
Wine prefix, Windows console stop/exit code через Wine 11.0. Виправлено зависання
Mono installer (`WINEDLLOVERRIDES=mscoree,mshtml=`) та перетворення LF→CR.
Повідомлення X connection broken після закриття тестового Xvfb самі по собі не
означають збій; орієнтуйтеся на exit code та фінальні маркери тесту.
16 unit-тестів перевіряють порти, збереження пароля й невідомих полів, захист
імені сейву, некоректний JSON, відповідність bundled runtime і його встановлення
в каталог із пробілами, читання mock-кешу AMP, вибір акаунта, порядок auth/download,
закритий stdin завантажувача та сумісність старого розміщення гри.
Усі 16 пройшли; це не перевірка реальної Steam-сесії або schema завантажувачем AMP.

На цільовому AMP:

```bash
read -r -p 'Absolute Co-op AMP instance directory: ' INSTANCE_DIR
docker ps --format 'table {{.Names}}\t{{.Image}}'
read -r -p 'Exact Co-op container name: ' COOP_CONTAINER
docker exec --user amp "$COOP_CONTAINER" wine --version
docker exec --user amp "$COOP_CONTAINER" \
  python3 /AMP/bannerlord-coop/runtime.py update
docker exec "$COOP_CONTAINER" ps -eo pid,ppid,args
```

Перевірте дерево AMP → xvfb-run → script → Wine/engine до Stop й відсутність
engine після Stop. Не публікуйте config.vdf або JSON із паролями.
Усім гравцям потрібні однакові версії гри й мода.

Приймання на реальному сервері ще потрібне:

- Шаблон видно в Create Instance; створено Docker-інстанс із потрібним образом.
- Steam login і AMP Update успішні, пароль відсутній у AMP логах.
- Start доходить до справжньої готовності, гравець підключається.
- Консоль приймає help/status/save, Stop зберігає й завершує engine до timeout.
- Повторний Start відновлює прогрес і персонажів; пересоздання контейнера з тим
  самим bind mount зберігає дані.
- Другий інстанс не конфліктує портами чи файлами.

Доступу до вашого Ubuntu/AMP у сесії немає; нові локальні зміни ще треба опублікувати.
﻿
