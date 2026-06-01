-- 1. Сколько всего в 4 таблицах (контрольная сумма ~815 ГБ)
SELECT 'ALL_TABLES' as src, SUM(content_length)/1024/1024/1024 as gb, COUNT(*) as cnt
FROM (
    SELECT content_length FROM test_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_fixture_result_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM test_case_attachment WHERE content_length > 0
    UNION ALL SELECT content_length FROM shared_step_attachment WHERE content_length > 0
) t

UNION ALL

-- 2. Сколько проходит джойны до проекта (то, что в отчёте)
SELECT 'WITH_PROJECT', SUM(content_length)/1024/1024/1024, COUNT(*)
FROM test_result_attachment a
JOIN test_result tr ON a.test_result_id = tr.id
JOIN launch l ON tr.launch_id = l.id
WHERE a.content_length > 0

UNION ALL

-- 3. Сколько «отвалилось» на этапе launch (нет launch_id или нет в таблице launch)
SELECT 'NO_LAUNCH', SUM(a.content_length)/1024/1024/1024, COUNT(*)
FROM test_result_attachment a
LEFT JOIN test_result tr ON a.test_result_id = tr.id
LEFT JOIN launch l ON tr.launch_id = l.id AND tr.launch_id IS NOT NULL
WHERE a.content_length > 0 AND l.id IS NULL

UNION ALL

-- 4. shared_step_attachment (всегда без проекта)
SELECT 'SHARED_STEP', SUM(content_length)/1024/1024/1024, COUNT(*)
FROM shared_step_attachment WHERE content_length > 0

UNION ALL

-- 5. test_case_attachment без связи с проектом
SELECT 'TC_NO_PROJECT', SUM(a.content_length)/1024/1024/1024, COUNT(*)
FROM test_case_attachment a
LEFT JOIN test_case tc ON a.test_case_id = tc.id
WHERE a.content_length > 0 AND (tc.id IS NULL OR tc.project_id IS NULL);