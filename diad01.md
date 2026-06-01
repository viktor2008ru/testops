Понял, задача критическая: **диск `/allure` заполнен на 92% (осталось 84 ГБ)**. Нужно быстро освободить место и понять, кто «виноват».

Вот план действий: диагностика → быстрая очистка → мониторинг.

---

## 🚨 Шаг 1: Быстрая диагностика (что занимает место)

### А. Проекты с наибольшим объёмом аттачментов (только те, что связаны с проектом)
```sql
-- Сохрани как report_projects.sql и запусти:
-- psql -h localhost -U testops -d testops -W -f report_projects.sql -o /tmp/projects.txt

WITH cutoff AS (SELECT (EXTRACT(EPOCH FROM (NOW() - INTERVAL '30 days')) * 1000)::bigint AS ms)
SELECT 
    COALESCE(p.id, 0) AS project_id,
    COUNT(*) AS files,
    ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2) AS gb,
    ROUND(100.0 * COUNT(*) FILTER (WHERE a.created_date < cutoff.ms) / COUNT(*), 1) AS old_pct
FROM test_result_attachment a
JOIN test_result tr ON a.test_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
LEFT JOIN project p ON l.project_id = p.id
WHERE a.content_length > 0 AND a.storage_key IS NOT NULL
GROUP BY COALESCE(p.id, 0), cutoff.ms
ORDER BY gb DESC
LIMIT 20;
```

### Б. Топ расширений по объёму (все таблицы)
```sql
-- report_ext.sql
SELECT 
    COALESCE(NULLIF(extension, ''), 'unknown') AS ext,
    COUNT(*) AS files,
    ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2) AS gb
FROM (
    SELECT extension, content_length FROM test_result_attachment WHERE content_length > 0
    UNION ALL SELECT extension, content_length FROM test_fixture_result_attachment WHERE content_length > 0
    UNION ALL SELECT extension, content_length FROM test_case_attachment WHERE content_length > 0
) t
GROUP BY COALESCE(NULLIF(extension, ''), 'unknown')
ORDER BY gb DESC
LIMIT 15;
```

### В. «Мёртвые» аттачменты фикстур (493 ГБ) — главный кандидат на очистку
```sql
-- orphaned_tfra.sql — покажет, сколько можно освободить
SELECT 
    ROUND(SUM(a.content_length)::numeric / 1024 / 1024, 0) AS mb_orphaned,
    COUNT(*) AS count_orphaned,
    MIN(TO_TIMESTAMP(a.created_date/1000)) AS oldest,
    MAX(TO_TIMESTAMP(a.created_date/1000)) AS newest
FROM test_fixture_result_attachment a
LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
WHERE tr.id IS NULL AND a.content_length > 0 AND a.storage_key IS NOT NULL;
```

---

## 🗑 Шаг 2: Экстренная очистка (освободить ~493 ГБ)

Эти 2.4 млн записей — «сироты»: ссылки на несуществующие `test_result`. Файлы есть в MinIO, но в БД они «потеряны». Их можно безопасно удалить через штатный механизм `blob_remove_task`.

### Скрипт очистки (запускай в транзакции, батчами!)
```sql
-- cleanup_orphaned_tfra.sql
-- ⚠️ Запускай в часы низкой нагрузки. Сначала протестируй на 1000 записей!

DO $$
DECLARE
    batch_size INT := 10000;
    deleted INT := 0;
    total_affected INT;
BEGIN
    -- Считаем всего орфанов
    SELECT COUNT(*) INTO total_affected
    FROM test_fixture_result_attachment a
    LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
    WHERE tr.id IS NULL AND a.storage_key IS NOT NULL;

    RAISE NOTICE 'Found % orphaned TFRA records. Starting cleanup in batches of %...', total_affected, batch_size;

    LOOP
        -- 1. Помечаем файлы на удаление в MinIO (через blob_remove_task)
        WITH batch AS (
            SELECT a.id, a.storage_key
            FROM test_fixture_result_attachment a
            LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
            WHERE tr.id IS NULL 
              AND a.storage_key IS NOT NULL
              AND a.id NOT IN (SELECT tra_id FROM attachment_candidate WHERE tra_id IS NOT NULL) -- уже в очереди
            LIMIT batch_size
        )
        INSERT INTO blob_remove_task (storage_key, created_at)
        SELECT storage_key, NOW() FROM batch
        ON CONFLICT (storage_key) DO NOTHING;

        -- 2. Считаем, сколько обработали
        GET DIAGNOSTICS batch_size = ROW_COUNT;
        EXIT WHEN batch_size = 0;
        
        deleted := deleted + batch_size;
        RAISE NOTICE 'Batch done: % records queued for deletion (total: %)', batch_size, deleted;
        
        -- Пауза, чтобы не нагружать БД
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Cleanup complete: % records queued for deletion', deleted;
END $$;
```

### Как запустить:
```bash
# 1. Подключись к БД
psql -h localhost -U testops -d testops -W

# 2. Внутри psql выполни:
\i /opt/cleanup_orphaned_tfra.sql

# 3. Следи за логами: скрипт будет выводить прогресс по батчам
```

### Что произойдёт:
1. Записи попадут в таблицу `blob_remove_task`.
2. Фоновый джоб Allure TestOps (или твой крон) обработает эту таблицу и удалит файлы из MinIO через `mc rm`.
3. После физического удаления файлы можно удалить из `test_fixture_result_attachment` (опционально).

---

## 📊 Шаг 3: Мониторинг после очистки

### Быстрый чек: сколько места освободилось в БД
```sql
-- После очистки запусти:
SELECT 
    'orphaned_tfra' as check,
    ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2) as gb_remaining
FROM test_fixture_result_attachment a
LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
WHERE tr.id IS NULL AND a.content_length > 0;
```

### Алерт в Prometheus на заполнение диска
```yaml
# /etc/prometheus/rules/minio_disk.yml
- alert: MinioDiskAlmostFull
  expr: (1 - (node_filesystem_avail_bytes{mountpoint="/allure"} / node_filesystem_size_bytes{mountpoint="/allure"})) > 0.9
  for: 5m
  labels: { severity: critical }
  annotations:
    summary: "Диск /allure заполнен на {{ $value | humanizePercentage }}"
    description: "Осталось менее 10% места. Срочно очистите старые аттачменты."
```

---

## 🎯 Итоговый чек-лист

| Действие | Команда / Скрипт | Ожидаемый эффект |
|----------|-----------------|-----------------|
| 1. Диагностика проектов | `report_projects.sql` | Увидеть топ-20 «тяжёлых» проектов |
| 2. Диагностика расширений | `report_ext.sql` | Понять, какие типы файлов чистить (html, png, video) |
| 3. Очистка 493 ГБ орфанов | `cleanup_orphaned_tfra.sql` | **+493 ГБ** свободного места |
| 4. Настройка ILM в MinIO | `mc ilm add myminio/allure --expire-days 90` | Автоудаление старых файлов в будущем |
| 5. Алерт на диск | Prometheus rule | Предупреждение до достижения 95% |

---

## 💡 Если нужно срочно освободить место «здесь и сейчас»

```bash
# 1. Найти и удалить старые неполные загрузки (multipart)
mc admin upload list myminio/allure | head -20
mc admin upload cancel myminio/allure <upload-id> --force

# 2. Удалить старые версии (если включено версионирование)
mc version info myminio/allure
# Если Enabled:
mc ilm add myminio/allure --expire-days 7 --non-current-versions

# 3. Временно перенести самые старые проекты на холодный бакет (если есть)
# Или удалить аттачменты проектов с 100% retention violations (из отчёта)
```

---

Нужна помощь с запуском скрипта очистки или настройкой ILM-политик под вашу структуру префиксов? 🛠️