-- 1. Контрольная сумма: все 4 таблицы (~815 ГБ)
SELECT 'ALL_TABLES' as src, 
       ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2) as gb, 
       COUNT(*) as cnt
FROM (
    SELECT content_length FROM test_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_fixture_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_case_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM shared_step_attachment WHERE content_length > 0
) t

UNION ALL

-- 2. test_result_attachment: сколько проходит до проекта
SELECT 'TRA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_result_attachment a
JOIN test_result tr ON a.test_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
LEFT JOIN project p ON l.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 3. test_fixture_result_attachment: сколько проходит до проекта
SELECT 'TFRA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_fixture_result_attachment a
JOIN test_result tr ON a.test_fixture_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
LEFT JOIN project p ON l.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 4. test_case_attachment: сколько проходит до проекта
SELECT 'TCA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_case_attachment a
JOIN test_case tc ON a.test_case_id = tc.id
LEFT JOIN project p ON tc.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 5. shared_step_attachment: всегда без проекта (считаем отдельно)
SELECT 'SHARED_STEP_NO_PROJECT', 
       ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM shared_step_attachment 
WHERE content_length > 0

UNION ALL

-- 6. test_result_attachment: отвалившиеся на джойнах
SELECT 'TRA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_result_attachment a
LEFT JOIN test_result tr ON a.test_result_id = tr.id
LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
WHERE a.content_length > 0 AND (tr.id IS NULL OR l.id IS NULL)

UNION ALL

-- 7. test_fixture_result_attachment: отвалившиеся на джойнах
SELECT 'TFRA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_fixture_result_attachment a
LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
WHERE a.content_length > 0 AND (tr.id IS NULL OR l.id IS NULL)

UNION ALL

-- 8. test_case_attachment: отвалившиеся на джойнах
SELECT 'TCA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_case_attachment a
LEFT JOIN test_case tc ON a.test_case_id = tc.id
WHERE a.content_length > 0 AND tc.id IS NULL;-- 1. Контрольная сумма: все 4 таблицы (~815 ГБ)
SELECT 'ALL_TABLES' as src, 
       ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2) as gb, 
       COUNT(*) as cnt
FROM (
    SELECT content_length FROM test_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_fixture_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_case_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM shared_step_attachment WHERE content_length > 0
) t

UNION ALL

-- 2. test_result_attachment: сколько проходит до проекта
SELECT 'TRA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_result_attachment a
JOIN test_result tr ON a.test_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
LEFT JOIN project p ON l.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 3. test_fixture_result_attachment: сколько проходит до проекта
SELECT 'TFRA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_fixture_result_attachment a
JOIN test_result tr ON a.test_fixture_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
LEFT JOIN project p ON l.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 4. test_case_attachment: сколько проходит до проекта
SELECT 'TCA_WITH_PROJECT', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_case_attachment a
JOIN test_case tc ON a.test_case_id = tc.id
LEFT JOIN project p ON tc.project_id = p.id
WHERE a.content_length > 0

UNION ALL

-- 5. shared_step_attachment: всегда без проекта (считаем отдельно)
SELECT 'SHARED_STEP_NO_PROJECT', 
       ROUND(SUM(content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM shared_step_attachment 
WHERE content_length > 0

UNION ALL

-- 6. test_result_attachment: отвалившиеся на джойнах
SELECT 'TRA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_result_attachment a
LEFT JOIN test_result tr ON a.test_result_id = tr.id
LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
WHERE a.content_length > 0 AND (tr.id IS NULL OR l.id IS NULL)

UNION ALL

-- 7. test_fixture_result_attachment: отвалившиеся на джойнах
SELECT 'TFRA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_fixture_result_attachment a
LEFT JOIN test_result tr ON a.test_fixture_result_id = tr.id
LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
WHERE a.content_length > 0 AND (tr.id IS NULL OR l.id IS NULL)

UNION ALL

-- 8. test_case_attachment: отвалившиеся на джойнах
SELECT 'TCA_ORPHANED', 
       ROUND(SUM(a.content_length)::numeric / 1024 / 1024 / 1024, 2), 
       COUNT(*)
FROM test_case_attachment a
LEFT JOIN test_case tc ON a.test_case_id = tc.id
WHERE a.content_length > 0 AND tc.id IS NULL;