# WinUserMigrator - Инструмент для переноса профилей пользователей Windows

## Описание

WinUserMigrator - это PowerShell-скрипт для удобного переноса профилей пользователей Windows с системного диска C: на другие диски с последующим созданием символической ссылки. Это позволяет освободить место на системном диске, сохраняя при этом корректную работу всех программ и системы в целом.

## Особенности

- Пошаговое перемещение профилей пользователей между дисками
- Автоматическое создание символических ссылок для бесшовной работы системы
- Поддержка управления учетными записями администратора
- Удобный и понятный русскоязычный интерфейс
- Подробное логирование всех операций
- Интеллектуальная обработка ошибок и возможность восстановления
- Автоматическое определение непрерывности операций
- Проверка прав администратора для выполнения операций
- Проверка состояния перенесенных профилей

## Требования

- Windows 10 или Windows 11
- PowerShell 5.1 или выше
- Права администратора для запуска скрипта
- Наличие дополнительного диска для переноса профилей

## Принцип работы

Скрипт выполняет следующие основные операции:

1. **Проверка прав доступа и учетной записи администратора**:
   - Проверяет права администратора
   - Определяет, запущен ли скрипт от имени встроенной учетной записи администратора
   - При необходимости предлагает включить учетную запись администратора

2. **Выбор и миграция профиля**:
   - Обнаружение профилей пользователей на системном диске
   - Выбор профиля для миграции
   - Выбор целевого диска для переноса
   - Копирование всех файлов профиля с сохранением атрибутов
   - Создание символической ссылки между исходным и новым расположением

3. **Завершение операции**:
   - Проверка успешности создания ссылки
   - Включение учетной записи мигрированного пользователя
   - Предложение перезагрузить компьютер

4. **Проверка состояния перенесенных профилей**:
   - Анализ профилей пользователей на предмет символических ссылок
   - Проверка доступности целевых папок
   - Отображение общей статистики по перенесенным профилям

## Использование

### Первый запуск (из обычной учетной записи)

1. Запустите скрипт от имени администратора через WinUserMigrator.bat или правая кнопка мыши -> "Запустить с PowerShell"
2. Скрипт проверит статус встроенной учетной записи администратора:
   - Если включена: предложит отключить ее для безопасности
   - Если отключена: предложит включить ее для полноценной миграции

3. При включении учетной записи администратора текущая сессия будет завершена
4. Войдите в систему под учетной записью администратора
5. Запустите скрипт снова

### Запуск из учетной записи администратора

1. Выберите пункт "Начать миграцию профиля пользователя"
2. Следуйте инструкциям пошагового мастера:
   - Выберите профиль для миграции
   - Выберите целевой диск
   - Подтвердите параметры миграции
   - Скрипт скопирует файлы и создаст символическую ссылку
   - После завершения процесса перезагрузите компьютер

### Управление учетными записями

1. Выберите пункт "Управление учетными записями пользователей" для:
   - Включения или отключения учетных записей пользователей

2. Выберите пункт "Управление учетной записью администратора" для:
   - Включения или отключения встроенной учетной записи администратора

### Проверка результатов миграции

1. Выберите пункт "Проверить состояние перенесенных профилей" для:
   - Просмотра списка перенесенных профилей с указанием целевых путей
   - Проверки доступности целевых папок
   - Получения статистики по перенесенным профилям

### Обработка существующих профилей

Если профиль с таким же именем уже существует на целевом диске, скрипт предложит следующие варианты:

1. **Переименовать целевой профиль** - Существующий профиль на целевом диске будет переименован в `{имя}_old`, и миграция продолжится как обычно.

2. **Переименовать исходный профиль** - Исходный профиль (в C:\Users) будет переименован в `{имя}_old`, и на его месте будет создана символическая ссылка на существующий целевой профиль. В этом случае копирование данных не производится.

3. **Заменить существующий профиль** - Существующий профиль на целевом диске будет удален и заменен содержимым исходного профиля.

В случае многократных переименований, к имени профиля добавляется временная метка для предотвращения конфликтов.

## Безопасность

- Скрипт создает резервную копию профиля перед созданием символической ссылки
- В случае ошибок автоматически восстанавливает исходное состояние
- Логирует все операции в файл для возможности анализа
- Поддерживает отключение учетной записи администратора после использования

## Логирование

Все действия скрипта записываются в лог-файл `MoveUserProfile_YYYY-MM-DD_HHMMSS.log` в папке `Logs` рядом со скриптом.

## Известные ограничения

- Не рекомендуется перемещать профиль текущего пользователя
- Профиль должен быть закрыт (пользователь не должен быть авторизован) во время миграции
- Требуется достаточно свободного места на целевом диске

## Дополнительная информация

Скрипт использует стандартные средства Windows:
- `robocopy` для надежного копирования файлов с сохранением всех атрибутов
- `mklink` для создания символических ссылок
- PowerShell командлеты для управления учетными записями

## Автор - CriDos

© 2025