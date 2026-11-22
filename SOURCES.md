# Джерела та межі перевірки — 22.11.2026

- [AMP Generic wiki](https://github.com/CubeCoders/AMP/wiki/Configuring-the-%27Generic%27-AMP-module): manifest, Git/LOCAL repositories, Executable update stage, STDIO/ExitMethod.
- [AMP custom images](https://github.com/CubeCoders/AMP/wiki/Using-custom-Docker-images-with-AMP-and-the-generic-module): base image та bind mount `/AMP`.
- [AMPTemplates](https://github.com/CubeCoders/AMPTemplates/tree/5b57587ab959a89b34aea48a1c508295a9ce081f): порівняно skyrim-together-reborn, abiotic-factor, conan-exiles, arma3 для Wine, SteamCMD, String stop та ChildPorts.Offset.
- [Правила подання](https://github.com/CubeCoders/AMPTemplates#readme): перед поданням треба перевірити життєвий цикл на Windows і Linux; власні scripts дозволені для Update/Pre-start, не startup. Штатний halo3-project-reclaimer використовує xvfb-run як стандартний Linux compatibility wrapper і містить Windows-гілку.
- Автоматизація EULA: [lib/license.sh server-manager](https://github.com/PlodyIce/bannerlordcoop-server-manager/blob/ac80c8a079de91f4291e2045fd7a573dea565d26/lib/license.sh) та docs/ARCHITECTURE.md описують серверний DS_ACCEPT_EULA=true і запис eula.txt самим engine починаючи з Coop v0.1.6. Це стороннє джерело; на справжньому build механізм тут ще не перевірено. Опція AMP за замовчуванням false і не генерує файл прийняття самостійно.
- У тій самій ревізії `halo3-project-reclaimerupdates.json` містить Linux Workshop Login stage `SteamCMD`, app `228980`, Windows platform, потім Executable download через `$FullRootDir/steamcmd.sh` і `../.virtualhome/Steam/config/config.vdf`. Його KVP має SteamUpdateAnonymousLogin=False і SteamForceLoginPrompt=True. Новий шаблон повторює цей спосіб без завантаження повної гри.
- [Steam login у AMP](https://discourse.cubecoders.com/t/why-is-amp-asking-for-my-steam-login-details/2310): штатний діалог і кеш SteamCMD; дані входу не журналюються AMP.
- [Оновлення конфігурації наявного інстансу](https://discourse.cubecoders.com/t/satisfactory-template-update/4998): Fetch Latest → Refresh Configuration → Update.
- [Сторонній dedicated launcher](https://github.com/geofmigliacci/egg-bannerlord-coop/tree/aac59029ba1e25c544df68b8780da03e784ffea9): .NET engine invocation, Workshop layout, ports, save seeding, TTY, commands/ready marker. Це не офіційний AMP-компонент. Його код не включений; runtime написано тут.
- [Офіційний Co-op](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/tree/81827688001aca48a15b925bd92aece227b219c7): README посилається на Workshop 3770450698; deploy/Server Instructions.md вимагає однакові версії та зберігати .sav разом із .json; doc/ServerDataLocations.md описує BANNERLORD_USER_DIR/COOP_DATA_DIR.
- Steam advertising: server-config поле steam присутнє в сторонньому dedicated launcher. [Конфігурація server-manager](https://github.com/PlodyIce/bannerlordcoop-server-manager/blob/main/docs/CONFIGURATION.md) описує STEAM_ADVERTISE як runtime-рекламу сервера. Офіційний source/Coop.Core/Server/ServerModule.cs у перевіреній ревізії реєструє Steam advertiser тільки при SessionDiscovery.SteamAvailable; інакше використовує NoopSessionAdvertiser. Наявність SteamCMD-кешу не є підтвердженням доступності runtime Steam API. UI перемикач задає steam=true/false; фактичну появу сервера в Steam ще не перевірено.

Публічний код офіційного репозиторію не містить актуальної реалізації
BannerlordCoopServer.exe / @DS@ CLI. Команди, ready marker й пара портів узяті зі
стороннього launcher, а не підтверджені запуском Workshop binary. Точні engine,
.NET і game versions перевіряйте після entitled download у release-info.txt.

Registry повернув linux/amd64 manifest:
`sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Завантажений index digest:
`sha256:d3fd4f741da84e7be0d74ce59b153047d6eaea187459c934ffe4a9c3a07bc76b`.
У запущеному cubecoders/ampbase:wine-stable перевірено Wine 11.0, jq,
xvfb-run, xauth, socat, wineboot, wineserver. SteamCMD у PATH немає;
тепер його встановлення та авторизацію проводить штатний AMP SteamCMD stage.

Тег mutable. Для відтворення замініть Meta.SpecificDockerImage на
`cubecoders/ampbase@sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Workshop і SteamCMD bootstrap mutable; для відкату потрібен локальний backup.

Підготовку виконує mount-and-blade2-coop.sh, який завершується до запуску гри.
Startup запускає стандартні env/xvfb-run/socat/Wine executable у Linux Docker;
власних scripts у startup немає. Нативну Windows-гілку видалено в ConfigVersion 12.
Python та base64 відсутні. FetchURL бере helpers із main. Це mutable URL:
для відтворення вкажіть перевірений commit у UpdateSourceData або відновіть
відповідну версію runtime з backup. jq читає пароль із JSON-файлу, не з argv.

Користувач надав встановлений SubModule.xml: Id=Coop, Version=v0.1.7,
CoopNightly зазначено як несумісний модуль. Тому App.AppSettings.CoopModuleId=Coop.
Pre-start перевіряє відповідність ID, а не змінює XML мода.

Це приватний експериментальний шаблон. Схожість із
AMPTemplates не є підтвердженням приймання CubeCoders чи runtime-сумісності AMP 2.8.
Нові тести перевіряють auth/cache на штучних даних, пароль, порядок Update,
staging лише в керованому server/, збереження сейвів, відмову при неправильному
module ID і відсутність запуску гри з Pre-start. Реальна Steam Guard сесія,
Workshop download і приймання кампанії у Linux/Docker ще потребують перевірки.

Wine smoke перевіряє створення prefix, data path і stop через той самий
env/xvfb-run/socat ланцюжок. Це перевірка механізму, не запуск гри.

22.11.2026: за рішенням користувача підтримку нативного Windows AMP припинено.
Видалено PowerShell helper, Windows Update/Pre-start stages і відповідні тести.
Windows-бінарні файли Workshop та ForceDownloadPlatform=Windows залишено:
їх використовує Wine всередині Linux-контейнера. Шаблон не заявляє відповідність
кросплатформній вимозі офіційного AMPTemplates.
