# Mount & Blade II: Bannerlord Co-op для AMP

Експериментальний Generic template для Ubuntu/Debian amd64: один контейнер
`cubecoders/ampbase:wine-stable`, Bash, jq, Wine, Xvfb і PTY. Python та base64
прибрано. Власний Dockerfile не потрібен. Це сервер спільної кампанії.

Реальне Workshop-завантаження, підключення гравців і Stop зі збереженням кампанії
ще потребують перевірки на вашому AMP. На наданому скриншоті Steam Guard уже
повернув OK; це підтверджує вхід, але не завершення Update.

## Підключення

ADS → Configuration → Instance Deployment → Configuration Repositories → **+**:

```text
ZifeRRoT/MnB-Bannerlord-co-op-AMP-template:main
```

Натисніть Fetch Latest, оновіть браузер і знайдіть у Create Instance
**Mount & Blade II: Bannerlord Co-op**. Префікс Community прибрано.
Docker залиште увімкненим. У Wine-образі перевірено Bash, jq, Wine, wineboot,
wineserver, Xvfb, xauth, script і timeout.

Файли: `manifest.json`, `mount-and-blade2-coop.kvp`,
`mount-and-blade2-coopconfig.json`, `mount-and-blade2-coopmetaconfig.json`,
`mount-and-blade2-coopports.json`, `mount-and-blade2-coopupdates.json`,
`mount-and-blade2-coop.sh`.

Для локальної перевірки знайдіть справжній DeploymentTemplates вашого ADS через
`ampinstmgr list` та `find /home/amp /opt -type d -name DeploymentTemplates`.
Як власник ADS скопіюйте manifest.json та файли mount-and-blade2-coop* у новий
підкаталог LOCAL-BannerlordCoop-main, додайте repository LOCAL/BannerlordCoop:main,
виконайте Fetch. Runtime все одно завантажується з опублікованої main.

## Налаштування

| Поле AMP | Дія |
| --- | --- |
| Server password | Приховане поле пароля гравців; порожнє значення вимикає пароль |
| Campaign save | Ім'я сейву без розширення: ASCII-літери, цифри, `_`, `-` |
| Autosave minutes | Автозбереження, 1–1440 хвилин |

Зміни застосовуються на наступному **Start**. Server password — не Steam-пароль.
Поле Steam username видалено. Акаунт визначається з кешу AMP; якщо старих акаунтів
кілька, скрипт перевіряє токени без пароля й використовує перший придатний.
Старий steam_username у settings.json ігнорується.
Регіон engine зафіксовано як EU у скрипті; старий ключ region також ігнорується.

Пароль зберігається у приватному settings.json, а під час Start через jq
переноситься в data/server-config.json. Значення не передається через argv чи
environment і не друкується runtime. Лапки, слеші та Unicode екрануються jq.
Приховане поле UI не шифрує файли на диску: резервні копії зберігайте приватно.

## Steam Guard та Update

Потрібен Steam-акаунт із Bannerlord (`261550`). Натисніть Update і пройдіть
Steam login/пароль/Guard у штатному діалозі AMP, а не в Console.

Update має три етапи:

1. FetchURL завантажує відкритий mount-and-blade2-coop.sh із цього репозиторію.
2. Штатний SteamCMD stage 228980 (Common Redistributables) проводить авторизацію
   AMP. Може завантажити Windows redistributables; це не повна гра.
3. Bash завантажує Workshop item 3770450698 через той самий SteamCMD і
   .virtualhome. Stdin закритий, NoPromptForPassword=1, timeout — 2 години.

Це схема Login/Workshop Download зі штатного halo3-project-reclaimer.
Якщо Guard уже OK, але стоїть `app_update 228980 validate`, виконується другий
етап; shell-завантаження Co-op ще не почалося. При тривалій відсутності прогресу
перевірте Steam content_log.txt. При відсутності reusable cache повторіть
Update і введіть код Guard у діалозі AMP.

Update перевіряє підтвердження успішного download і файли bundled engine/.NET.
Start не оновлює гру автоматично. Main і Workshop mutable: користуйтеся
перевіреною ревізією та робіть backup. Shell-файл необхідно опублікувати разом
із шаблоном; інакше FetchURL не спрацює. Генерація шаблону більше не потрібна.

## Перехід із попереднього шаблону

1. Штатно зупиніть гру й зробіть backup.
2. Після публікації: ADS → Instance Deployment → **Fetch Latest**.
3. На плитці Co-op інстансу: права кнопка → **Refresh Configuration**.
4. Перевірте нові поля й задайте **Server password** перед Start. Порожнє поле
   означає відкритий сервер і замінить пароль, який раніше задавали вручну в JSON.
5. Виконайте Update, потім Start.

AppConfigId збережено. Через перейменування файлів конкретна збірка ADS може
не знайти старий ConfigRoot під час Refresh. У такому разі не видаляйте інстанс:
потрібна перевірка його прив'язки до template. Цей перехід ще не перевірено на
реальному AMP. Friendly name наявного інстансу можна змінити окремо.

Каталог даних залишається **bannerlord-coop/**: сейви, Wine prefix і кеш не
переміщуються. Старий runtime.py можна залишити на диску — новий KVP його не
використовує. Спочатку Update встановлює shell-файл, потім можна робити Start.

## Порти й консоль

| Allocation | Призначення |
| --- | --- |
| UDP 4200 | Co-op, порт входу гравців |
| UDP 4201 | Дочірній порт із Offset=1 для dedicated build |
| UDP 7210 | Engine custom-server, не порт входу гравців |

AMP передає фактичні GamePort та EnginePort у shell. Другому інстансу потрібні
власні порти. Офіційна інструкція мода описує один публічний UDP порт, сторонній
dedicated launcher — пару; потребу відкривати другий/engine порт назовні ще
треба перевірити. TCP не додано.

Ready marker: `coop server up, waiting for clients`. Очікувані команди: help,
status, players, save, stop; звірте з help/@DS@ встановленого build.
AMP Stop надсилає stop і чекає 180 секунд. Реальне збереження кампанії ще
потрібно перевірити. Force Stop не гарантує збереження.

ANSI-коди кольору/курсора очищаються у виводі shell SteamCMD; для виводу гри
також задано Console.FilterMatchRegex. Звичайний текст і Unicode зберігаються.
Очищення штатного SteamCMD login-stage залежить від обробки виводу самим AMP;
shell-фільтр працює на наступному Workshop-етапі. Старі рядки консолі не змінюються.

Ланцюжок запуску: exec → xvfb-run → script → Wine engine. PTY має
`stty -echo inlcr`, script --return зберігає exit code. Пароля в цій команді
немає. Додаткові Workshop-моди поки не підтримуються.

## Дані та backup

| Шлях від кореня інстансу | Вміст |
| --- | --- |
| bannerlord-coop/settings.json | Налаштування AMP, пароль гравців |
| bannerlord-coop/data/Game Saves/ | Сейви .sav і однойменні .json |
| bannerlord-coop/data/logs/ | Логи мода |
| bannerlord-coop/data/server-config.json | Застосована конфігурація |
| bannerlord-coop/.wine/ | Wine prefix |
| .virtualhome/Steam/ | Приватний кеш Steam і можливі Workshop-файли |
| bannerlord-coop/workshop/ | Нові Workshop-файли |
| bannerlord-coop/steam/ | Старе розміщення, якщо вже встановлювали раніше |

Для імпорту кампанії при зупиненій грі перенесіть .sav разом із однойменним
.json у Game Saves і задайте ім'я без розширення. Наявний сейв не перезаписується.
Runtime зберігає невідомі поля server-config.json; потрібен JSON без коментарів.
Некоректний JSON спричиняє помилку без стирання оригіналу.

Після Stop, як власник інстансу:

```bash
read -r -p 'Absolute Co-op AMP instance directory: ' INSTANCE_DIR
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
BACKUP_FILE="$HOME/bannerlord-coop-$(date +%Y%m%d-%H%M%S).tar.gz"
umask 077
tar -C "$INSTANCE_DIR" -czf "$BACKUP_FILE" bannerlord-coop .virtualhome
```

Архів містить токени й паролі. Для відкату зупиніть гру та цей інстанс у ADS,
перемістіть поточні каталоги в нові поруч і відновіть перевірений backup:

```bash
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
read -r -p 'Absolute backup archive path: ' BACKUP_FILE
test -f "$BACKUP_FILE" || exit 1
tar -tzf "$BACKUP_FILE" # перевірте власний архів
mv "$INSTANCE_DIR/bannerlord-coop" "$INSTANCE_DIR/bannerlord-coop.before-rollback-$(date +%Y%m%d-%H%M%S)"
if [ -d "$INSTANCE_DIR/.virtualhome" ]; then
  mv "$INSTANCE_DIR/.virtualhome" "$INSTANCE_DIR/.virtualhome.before-rollback-$(date +%Y%m%d-%H%M%S)"
fi
tar -xzf "$BACKUP_FILE" -C "$INSTANCE_DIR"
```

Відновлюйте runtime, template, engine і дані з відповідних ревізій разом.

## Перевірки

Локально потрібні Bash, jq, awk і стандартні Unix tools:

```bash
bash tests/test_shell.sh
```

На Linux Docker з кореня репозиторію:

```bash
docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
  --mount "type=bind,source=$PWD,target=/work,readonly" -w /work \
  cubecoders/ampbase:wine-stable tests/test_shell.sh
docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
  --mount "type=bind,source=$PWD,target=/work,readonly" -w /work \
  cubecoders/ampbase:wine-stable tests/container_smoke.sh
```

Shell-тести перевіряють пароль/JSON/argv, кеш на штучних даних, порти,
розміщення гри, підтвердження Workshop download і запуск із тестовими командами.
Smoke-тест створює Wine prefix і перевіряє stop/exit code Windows cmd через PTY.
Це не запуск гри й не перевірка реального Steam-сеансу.

Локальний результат: усі 16 shell-перевірок пройшли в Linux AMP Wine image;
ShellCheck не виявив зауважень. Wine smoke-тест повернув WINE_PREFIX_OK та
WINE_STDIO_STOP_AND_EXIT_STATUS_OK. Пароль перевірено зі спецсимволами й Unicode;
тест запуску підтвердив його відсутність у командному рядку.

Приймання на AMP: template видно; Update успішний; клієнт підключається;
неправильний пароль відхиляється; Stop зберігає кампанію; повторний Start і
пересоздання контейнера з тим самим bind mount відновлюють прогрес.
