# Mount & Blade II: Bannerlord Co-op для AMP

Експериментальний Generic template для Linux amd64. Docker рекомендований.
У Docker використовується один контейнер `cubecoders/ampbase:wine-stable`, Xvfb, socat PTY
та Wine. Власний Dockerfile не потрібен. Bash працює лише в Update та Pre-start,
після чого завершується; startup-команда не викликає наші скрипти.
Python та base64 відсутні. Нативний Windows AMP не підтримується.

Локальні shell-тести та Wine smoke перевіряють підготовку й консоль на тестовому
executable. Реальний Linux/Docker запуск із Ready, підключенням гравців і Stop
зі збереженням кампанії ще потребує перевірки. Це окремий Linux-шаблон, а не
кандидат на кросплатформне подання до AMPTemplates.

## Підключення

ADS → Configuration → Instance Deployment → Configuration Repositories → **+**:

```text
ZifeRRoT/MnB-Bannerlord-co-op-AMP-template:main
```

Натисніть Fetch Latest, оновіть браузер і знайдіть у Create Instance
**Mount & Blade II: Bannerlord Co-op**. Префікс Community прибрано.
Docker рекомендований. У Wine-образі перевірено Bash, jq, Wine,
wineboot, wineserver, Xvfb, xauth, socat і timeout.
Для запуску без Docker ці залежності потрібно встановити на Linux-хості;
Wine очікується за шляхом `/usr/bin/wine`, Xvfb wrapper — `/usr/bin/xvfb-run`,
socat — `/usr/bin/socat`. Нативний запуск без контейнера ще не перевірено.
Окремий .NET runtime завантажувати не потрібно: engine містить власний.

Файли: `manifest.json`, `mount-and-blade2-coop.kvp`,
`mount-and-blade2-coopconfig.json`, `mount-and-blade2-coopmetaconfig.json`,
`mount-and-blade2-coopports.json`, `mount-and-blade2-coopupdates.json`,
`mount-and-blade2-coopstart.json`, `mount-and-blade2-coop.sh`.

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
| Register server in Steam | Вмикає поле steam; початково вимкнено, застосовується після Stop → Start |
| Accept server EULA | Явне прийняття умов серверу через DS_ACCEPT_EULA; початково вимкнено |

Зміни застосовуються на наступному **Start**. Server password — не Steam-пароль.
Поле Steam username видалено. Акаунт визначається з кешу AMP; якщо старих акаунтів
кілька, скрипт перевіряє токени без пароля й використовує перший придатний.
Старий settings.json більше не використовується. Регіон engine зафіксовано як EU.

AMP через AutoMap записує налаштування прямо у data/server-config.json, який
читає сервер. Застосування до гри потребує Stop → Start. Shell не переносить
старі defaults із settings.json. Значення пароля не передається через argv чи
environment і не друкується runtime. Лапки, слеші та Unicode екрануються jq.
Приховане поле UI не шифрує файли на диску: резервні копії зберігайте приватно.

Register server in Steam вмикає Steam advertising лише коли Steam API доступний
самому запущеному engine. Кеш SteamCMD використовується для завантажень і сам
не створює runtime Steam-сеанс. У Docker з одним SteamCMD видимість у Steam
не гарантована; реальну реєстрацію ще треба перевірити. Для вимкнення зніміть
позначку й перезапустіть гру. Pre-start зберігає вибране true/false.

### EULA без вводу в консоль

Після Update прочитайте `server/EULA.md` (або EULA.txt) та `server/LICENSE.txt`
у File Manager. Якщо погоджуєтеся, увімкніть **Accept server EULA** й виконайте
Stop → Start. AMP передасть підтримувану сервером змінну `DS_ACCEPT_EULA=true`
у Linux/Wine. Прийняття сервер записує сам у `data/eula.txt`; template
цей файл не підробляє й не надсилає `yes` у stdin. Умови після оновлень можуть
змінюватися: переглядайте їх перед Start, якщо опція залишена увімкненою.

Зняття позначки вимикає автоматичне прийняття, але не видаляє раніше записаний
сервером eula.txt. Реальний EULA-прохід установленого build ще треба перевірити;
локальні тести перевіряють вимкнений default і передачу environment-параметра.

## Steam Guard та Update

Потрібен Steam-акаунт із Bannerlord (`261550`). Натисніть Update і пройдіть
Steam login/пароль/Guard у штатному діалозі AMP, а не в Console.

Update виконує чотири етапи:

1. FetchURL завантажує shell helper із цього репозиторію.
2. Helper init створює data/server-config.json, якщо його немає. AutoMap потребує
   файла-шаблону до запуску гри. Наявний файл init не перезаписує.
3. Штатний SteamCMD stage 228980 (Common Redistributables) проводить авторизацію
   AMP. Може завантажити Windows redistributables; це не повна гра.
4. Helper завантажує Workshop item 3770450698 через той самий SteamCMD, потім
   копіює DedicatedServer у фізичний `server/`. Stdin закритий,
   NoPromptForPassword=1, timeout — 2 години.

Кеш SteamCMD розташований у `../.virtualhome/Steam/config/config.vdf`.
Це шлях з upstream-шаблону Project Reclaimer; його відповідність вашій
інсталяції AMP треба перевірити. Пароль/Guard вводяться у штатному діалозі AMP.

Окрема копія `server/` дає стабільний executable та WorkingDir без
динамічного shell-launcher. Вона займає приблизно ще один обсяг dedicated build
понад Workshop-копію (поточний Workshop — близько 6.5 GB). Перед Update потрібне
місце для обох копій, Wine prefix на Linux і backup. Helper очищає тільки
керований `server/` із маркером `.amp-coop-managed`; data/ не очищається.
Після повного копіювання з'являється `.amp-coop-ready`; без нього Pre-start
блокується, щоб перерваний Update не запускав частково скопійований engine.

Це схема Login/Workshop Download зі штатного halo3-project-reclaimer.
Якщо Guard уже OK, але стоїть `app_update 228980 validate`, виконується
SteamCMD-етап; shell-завантаження Co-op ще не почалося. При тривалій відсутності прогресу
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
4. Перевірте поля й задайте **Server password** перед Start. Порожнє поле
   означає відкритий сервер і замінить пароль, який раніше задавали вручну в JSON.
5. Виконайте Update, потім Stop → Start. Після Start перевірте saveName та
   autosaveMinutes у data/server-config.json; пароль публікувати не потрібно.

Виправлення застосування налаштувань — ConfigVersion 7 і новіші: metaconfig
посилається на data/server-config.json. Самого Update недостатньо для зміни
прив'язки — спочатку потрібен Refresh Configuration. Якщо активний metaconfig.json
інстансу досі містить ConfigFile=settings.json, він ще використовує стару прив'язку.

AppConfigId збережено. Через перейменування файлів конкретна збірка ADS може
не знайти старий ConfigRoot під час Refresh. У такому разі не видаляйте інстанс:
потрібна перевірка його прив'язки до template. Цей перехід ще не перевірено на
реальному AMP. Friendly name наявного інстансу можна змінити окремо.

Каталог даних залишається **bannerlord-coop/**: сейви, Wine prefix і кеш не
переміщуються. ConfigVersion 12 залишає лише Linux і рекомендує Docker.
Для наявного Linux-інстансу виконайте Refresh Configuration. Нативний Windows-інстанс
не перетворюється на Linux-інстанс: для перенесення створіть окремий Linux/Docker
інстанс і імпортуйте кампанію при зупиненій грі.
Після Refresh обов'язково виконайте Update для створення `server/` перед Start.
Старий runtime.py новий KVP не використовує.

Підтверджений користувачем module ID — `Coop`, version `v0.1.7`. Він заданий
у внутрішньому `App.AppSettings.CoopModuleId`, не як поле UI. Pre-start звіряє
ID із staged SubModule.xml і зупиняється при несумісності. Для іншого build
потрібна перевірена зміна цього значення у template; мовчазного перейменування
CoopNightly у Coop чи зміни мод-файлів немає.

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

Вивід SteamCMD передається без ANSI-фільтрації. Консоль AMP може показувати
коди кольору/курсора як символи; це не помилка авторизації чи завантаження.

Pre-start перевіряє конфігурацію/порти/module ID, створює відсутній сейв і
ініціалізує Wine prefix на Linux, потім повертає керування AMP.
Linux startup: стандартний `env → xvfb-run → socat EXEC → Wine → bundled dotnet.exe`.
socat надає PTY із echo=0 та inlcr; EXEC не використовує shell для engine.
У startup немає викликів нашого .sh. Пароля в командному рядку немає.

Фізичний WorkingDir — `server/engine/bin/Win64_Shipping_Server`.
Стандартний env executable задає BANNERLORD_USER_DIR, COOP_DATA_DIR та DOTNET_ROOT
абсолютними Wine-шляхами Z:/… перед запуском Xvfb. Це не залежить від зміни cwd
усередині гри. Windows-бінарні файли engine потрібні для Wine й залишаються.
MonitorChildProcessName прив'язаний до dotnet/Starter та окремого EnginePort.
Додаткові Workshop-моди поки не підтримуються.

## Дані та backup

| Шлях від кореня інстансу | Вміст |
| --- | --- |
| bannerlord-coop/data/Game Saves/ | Сейви .sav і однойменні .json |
| bannerlord-coop/data/logs/ | Логи мода |
| bannerlord-coop/data/server-config.json | Налаштування AMP та конфігурація гри, зокрема пароль |
| bannerlord-coop/server/ | Керована копія executable/engine; Update її замінює |
| bannerlord-coop/.wine/ | Wine prefix |
| .virtualhome/Steam/ | Linux: приватний кеш Steam і можливі Workshop-файли |
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

Тести перевіряють пароль/JSON, кеш на штучних даних, порти, staging, збереження
сейву та відсутність запуску гри з Pre-start. Wine smoke запускає Windows cmd
через той самий xvfb-run/socat ланцюжок і перевіряє шлях до data та stop.
Це не запуск гри.

Для підтвердження роботи Linux/Docker ще потрібно перевірити:

- Template видно, Update із реальним Steam Guard/Workshop успішний.
- Start доходить до справжнього Ready; клієнт підключається.
- Пароль відхиляє неправильний ввід; зміни AMP читаються грою після Start.
- Console приймає help/status/save, Stop зберігає й доходить до Stopped.
- Повторний Start відновлює прогрес і персонажів; Linux контейнер переживає
  пересоздання з тим самим bind mount.
- CPU/RAM і process monitoring належать правильному інстансу; другий інстанс
  не конфліктує портами чи файлами.

Поки ці пункти не виконано, шаблон слід розглядати як draft. Відповідність
структури та локальні тести не означають приймання CubeCoders.
