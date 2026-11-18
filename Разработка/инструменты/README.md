# Инструменты разработки

Всё для проверки и пересборки XP-версии. Интернет не нужен — зависимости Babel
уже установлены в `node_modules`.

## Главное

| Файл | Что делает |
|---|---|
| `пересобрать-XP.bat` | **двойной щелчок**: проверка синтаксиса + пересборка XP + копия базы |
| `build_xp.ps1` | то же из консоли (можно указать свои пути `-Source` / `-Target`) |
| `build_xp.js` | сам сборщик: ES5 под Firefox 52, `_blobText`, compat-CSS, полифилл flex-gap, XP-загрузчик базы |
| `extract_js.py` | достаёт главный `<script>` из `index.html` (для `node --check`) |
| `dxf_audit.py` | проверка выгруженного DXF: миллиметры и реальная хорда |
| `package.json` | зависимости сборщика (`@babel/core`, `@babel/preset-env`) |

## Автоматическая история

| Файл | Что делает |
|---|---|
| `watch-history.ps1` | «часовой»: следит за папкой программы и сам обновляет архив (см. ниже) |
| `история-включить.bat` | **двойной щелчок**: запустить слежение (свёрнутым окном) |
| `история-выключить.bat` | остановить слежение |
| `история-состояние.bat` | работает ли слежение, автозапуск, когда была синхронизация |
| `история-обновить-сейчас.bat` | разово обновить архив, не дожидаясь слежения |
| `история-автозапуск.bat` | прописать слежение в автозапуск Windows |

Что делает один проход синхронизации:

1. копирует в `программа\` изменённые `index.html`, `airfoil-base.js`, файлы `XP\`;
2. если менялся `index.html` — **сам пересобирает XP-версию** и кладёт свежий файл
   и в архив, и в рабочую папку программы (если сборка упала — старый файл не трогает,
   ошибку пишет в журнал);
3. делает снимок `история\снимки\index-ГГГГ-ММ-ДД_ЧЧММСС.html` (хранятся последние 40);
4. дописывает запись в `история\ЖУРНАЛ-ИЗМЕНЕНИЙ.md` (файл, размер, число строк);
5. не чаще раза в 30 минут обновляет `AirfoilStudio-Разработка.zip` для переноса;
6. обновляет `история\СОСТОЯНИЕ.txt` (даты, размеры, SHA256).

Слежение ждёт 20 секунд после последнего изменения — чтобы не снимать копию
в середине правки.

Команды из консоли:

```bat
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1            rem работать постоянно
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -Once       rem один проход
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -Status     rem состояние
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -Stop       rem остановить
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -InstallStartup   rem автозапуск вкл
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -RemoveStartup    rem автозапуск выкл
powershell -ExecutionPolicy Bypass -File инструменты\watch-history.ps1 -Once -NoBuild    rem без пересборки XP
```

## Типичные команды

```bat
rem пересобрать XP-версию (из корня папки разработки)
powershell -ExecutionPolicy Bypass -File инструменты\build_xp.ps1

rem только проверить синтаксис программы
python инструменты\extract_js.py программа\index.html check.js
node --check check.js

rem проверить DXF: единицы и габарит против хорды 250 мм
python инструменты\dxf_audit.py C:\путь\профиль.dxf 250
```

## Что должно быть в выводе сборки

```json
{ "gridGapAdded": true, "blobTextPatched": true, "fontPatched": true }
```

Если `WARN: loader tag not found` — в `index.html` нет
`<script src="./airfoil-base.js"></script>`.

## Переустановка зависимостей (если node_modules потеряна)

```bat
cd инструменты
npm install
```
