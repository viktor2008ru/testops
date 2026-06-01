Отличный вопрос. В отчёте **~242 ГБ**, а должно быть **~815 ГБ**. Разница ~573 ГБ «потерялась», потому что скрипт `/opt/report_projects.sql` считал **только одну таблицу** — `test_result_attachment`.

Вот куда делись гигабайты:

| Источник | Объём | Почему не в отчёте |
|----------|-------|-------------------|
| `test_result_attachment` (с проектом) | ~244 ГБ | ✅ Есть в отчёте |
| `test_fixture_result_attachment` (с проектом) | ~72 ГБ | ❌ Не учитывалось в запросе |
| `test_case_attachment` (с проектом) | ~6 ГБ | ❌ Не учитывалось в запросе |
| `test_fixture_result_attachment` (орфаны) | **~493 ГБ** | ❌ Нет связи с `test_result` → не попали |
| `shared_step_attachment` | ~0 ГБ | Пусто |

---

## 🚀 Исправленный скрипт: ВСЕ таблицы + орфаны

Сохраните как `/opt/report_all_attachments.sql`:

```sql
-- Считаем ВСЕ аттачменты из 4 таблиц, с проектами и орфанами
WITH cutoff AS (
    SELECT (EXTRACT(EPOCH FROM (NOW() - INTERVAL '30 days')) * 1000)::bigint AS ms
),
all_attachments AS (
    -- 1. test_result_attachment → launch → project
    SELECT 
        CASE 
            WHEN p.id IS NOT NULL THEN p.id::text
            WHEN l.id IS NOT NULL THEN 'launch_no_project'
            WHEN tr.id IS NOT NULL THEN 'result_no_launch'
            ELSE 'orphaned_tra'
        END AS project_key,
        a.content_length,
        a.created_date
    FROM test_result_attachment a
    LEFT JOIN test_result tr ON a.test_result_id = tr.id
    LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
    LEFT JOIN project p ON l.project_id = p.id AND l.project_id IS NOT NULL
    WHERE a.content_length > 0 AND a.storage_key IS NOT NULL

    UNION ALL

    -- 2. test_fixture_result_attachment → launch → project (включая орфаны)
    SELECT 
        CASE 
            WHEN p.id IS NOT NULL THEN p.id::text
            WHEN l.id IS NOT NULL THEN 'launch_no_project'
            WHEN tr.id IS NOT NULL THEN 'result_no_launch'
            ELSE 'orphaned_tfra'  -- ← здесь те самые 493 ГБ!
        END AS project_key,
        a.content_length,
        a.created_date
    FROM test_fixture_result_attachment a
    LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
    LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
    LEFT JOIN project p ON l.project_id = p.id AND l.project_id IS NOT NULL
    WHERE a.content_length > 0 AND a.storage_key IS NOT NULL

    UNION ALL

    -- 3. test_case_attachment → project
    SELECT 
        CASE 
            WHEN p.id IS NOT NULL THEN p.id::text
            ELSE 'tc_no_project'
        END AS project_key,
        a.content_length,
        a.created_date
    FROM test_case_attachment a
    LEFT JOIN test_case tc ON a.test_case_id = tc.id
    LEFT JOIN project p ON tc.project_id = p.id AND tc.project_id IS NOT NULL
    WHERE a.content_length > 0 AND a.storage_key IS NOT NULL
)
SELECT 
    project_key,
    COUNT(*) AS files,
    ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2) AS gb,
    ROUND(100.0 * COUNT(*) FILTER (WHERE created_date < cutoff.ms) / NULLIF(COUNT(*), 0), 1) AS old_pct
FROM all_attachments
CROSS JOIN cutoff
GROUP BY project_key, cutoff.ms
ORDER BY gb DESC;
```

### 🚀 Запуск
```bash
psql -h localhost -U testops -d testops -W -f /opt/report_all_attachments.sql -o /tmp/all_projects.txt
```

### 📊 Ожидаемый результат
```
     project_key      |  files   |   gb   | old_pct
----------------------+----------+--------+---------
 orphaned_tfra        |  2414246 | 492.92 |   85.2   ← ⚠️ 493 ГБ сирот!
 30                   |  2101489 |  61.27 |   55.8
 2                    | 10304715 |  47.83 |   42.8
 1                    |   573436 |  43.00 |   60.5
 ...
```

Теперь вы увидите **все ~815 ГБ**, разбитые по проектам и группам орфанов.

---

## 🗑 Что делать с `orphaned_tfra` (493 ГБ)

Это **главный кандидат на срочную очистку** — файлы есть в MinIO, но в БД они «потеряны» (ссылаются на несуществующий `test_result`).

### Быстрая очистка (безопасно, через штатный механизм)
```sql
-- cleanup_orphaned_tfra.sql
-- Помещает орфаны в очередь на удаление (blob_remove_task)
INSERT INTO blob_remove_task (storage_key, created_at)
SELECT DISTINCT a.storage_key, NOW()
FROM test_fixture_result_attachment a
LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
WHERE tr.id IS NULL 
  AND a.storage_key IS NOT NULL
  AND a.content_length > 0
ON CONFLICT (storage_key) DO NOTHING;
```

### Запуск:
```bash
psql -h localhost -U testops -d testops -W -f /opt/cleanup_orphaned_tfra.sql
```

После этого фоновый джоб Allure удалит файлы из MinIO. Проверить прогресс:
```sql
-- Сколько уже в очереди на удаление
SELECT COUNT(*) FROM blob_remove_task WHERE created_at > NOW() - INTERVAL '1 hour';
```

---

## 📈 Топ расширений по ВСЕМ таблицам

```sql
-- report_all_ext.sql
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
ORDER BY gb DESC;
```

```bash
psql -h localhost -U testops -d testops -W -f /opt/report_all_ext.sql
```

---

## ✅ Итоговый план на сегодня

| Шаг | Действие | Ожидаемый эффект |
|-----|----------|-----------------|
| 1 | Запустить `/opt/report_all_attachments.sql` | Увидеть полную картину: кто сколько занимает |
| 2 | Запустить `cleanup_orphaned_tfra.sql` | **+493 ГБ** свободного места |
| 3 | Проверить `df -h /allure` | Убедиться, что место освободилось |
| 4 | Настроить ILM в MinIO | Автоудаление старых файлов в будущем |

```bash
# После очистки проверить диск
df -h /allure
```

Нужна помощь с запуском скрипта очистки или настройкой автоудаления через ILM? 🛠️