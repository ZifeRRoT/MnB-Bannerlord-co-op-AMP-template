# Джерела та межі перевірки — 21.11.2026

- [AMP Generic wiki](https://github.com/CubeCoders/AMP/wiki/Configuring-the-%27Generic%27-AMP-module): manifest, Git/LOCAL repositories, Executable update stage, STDIO/ExitMethod.
- [AMP custom images](https://github.com/CubeCoders/AMP/wiki/Using-custom-Docker-images-with-AMP-and-the-generic-module): base image та bind mount `/AMP`.
- [AMPTemplates](https://github.com/CubeCoders/AMPTemplates/tree/5b57587ab959a89b34aea48a1c508295a9ce081f): порівняно skyrim-together-reborn, abiotic-factor, conan-exiles, arma3 для Wine, SteamCMD, String stop та ChildPorts.Offset.
- У тій самій ревізії `halo3-project-reclaimerupdates.json` містить Linux Workshop Login stage `SteamCMD`, app `228980`, Windows platform, потім Executable download через `$FullRootDir/steamcmd.sh` і `../.virtualhome/Steam/config/config.vdf`. Його KVP має SteamUpdateAnonymousLogin=False і SteamForceLoginPrompt=True. Новий шаблон повторює цей спосіб без завантаження повної гри.
- [Steam login у AMP](https://discourse.cubecoders.com/t/why-is-amp-asking-for-my-steam-login-details/2310): штатний діалог і кеш SteamCMD; дані входу не журналюються AMP.
- [Оновлення конфігурації наявного інстансу](https://discourse.cubecoders.com/t/satisfactory-template-update/4998): Fetch Latest → Refresh Configuration → Update.
- [Сторонній dedicated launcher](https://github.com/geofmigliacci/egg-bannerlord-coop/tree/aac59029ba1e25c544df68b8780da03e784ffea9): .NET engine invocation, Workshop layout, ports, save seeding, TTY, commands/ready marker. Це не офіційний AMP-компонент. Його код не включений; runtime написано тут.
- [Офіційний Co-op](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/tree/81827688001aca48a15b925bd92aece227b219c7): README посилається на Workshop 3770450698; deploy/Server Instructions.md вимагає однакові версії та зберігати .sav разом із .json; doc/ServerDataLocations.md описує BANNERLORD_USER_DIR/COOP_DATA_DIR.

Публічний код офіційного репозиторію не містить актуальної реалізації
BannerlordCoopServer.exe / @DS@ CLI. Команди, ready marker й пара портів узяті зі
стороннього launcher, а не підтверджені запуском Workshop binary. Точні engine,
.NET і game versions перевіряйте після entitled download у release-info.txt.

Registry повернув linux/amd64 manifest:
`sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Завантажений index digest:
`sha256:d3fd4f741da84e7be0d74ce59b153047d6eaea187459c934ffe4a9c3a07bc76b`.
У запущеному cubecoders/ampbase:wine-stable перевірено Wine 11.0, Python 3.13,
xvfb-run, xauth, script, wineboot, winepath. SteamCMD у PATH немає;
тепер його встановлення та авторизацію проводить штатний AMP SteamCMD stage.

Тег mutable. Для відтворення замініть Meta.SpecificDockerImage на
`cubecoders/ampbase@sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Workshop і SteamCMD bootstrap mutable; для відкату потрібен локальний backup.

Runtime тепер звичайний Bash-файл mount-and-blade2-coop.sh; Python та base64
прибрано. FetchURL бере його з main цього репозиторію. Це mutable URL:
для відтворення вкажіть перевірений commit у UpdateSourceData або відновіть
відповідну версію runtime з backup. jq читає пароль із JSON-файлу, не з argv.

Результати локальних контейнерних перевірок: SteamCMD bootstrap і +quit успішні;
PTY передає stop і код 7; Wine prefix створено після вимкнення Mono/Gecko
installer та завершення wineserver; Windows cmd отримує stop через Wine/PTY
(stty inlcr) і повертає код 7. Це перевірка механізму, не ігрового сервера.

Це приватний експериментальний шаблон. Схожість із
AMPTemplates не є підтвердженням приймання CubeCoders чи runtime-сумісності AMP 2.8.
Нові shell-тести перевіряють auth/cache на штучних даних, пароль, argv,
порядок Update stages, збереження старих файлів гри й сейвів. Реальна
Steam Guard сесія після shell-переходу та приймання кампанії ще не перевірені.

У Linux AMP Wine image пройшли всі 16 shell-перевірок і ShellCheck.
Новий shell smoke-тест підтвердив створення Wine prefix та передачу stop
Windows cmd через PTY із кодом завершення 7. jq уже є в перевіреному образі,
тому додаткові пакети контейнера не встановлюються.
