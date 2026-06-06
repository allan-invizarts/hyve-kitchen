-- Add user to stock-related groups
INSERT INTO res_groups_users_rel (uid, gid)
SELECT 7, 28 WHERE NOT EXISTS (SELECT 1 FROM res_groups_users_rel WHERE uid=7 AND gid=28)
UNION ALL
SELECT 7, 29 WHERE NOT EXISTS (SELECT 1 FROM res_groups_users_rel WHERE uid=7 AND gid=29)
UNION ALL
SELECT 7, 30 WHERE NOT EXISTS (SELECT 1 FROM res_groups_users_rel WHERE uid=7 AND gid=30)
UNION ALL
SELECT 7, 33 WHERE NOT EXISTS (SELECT 1 FROM res_groups_users_rel WHERE uid=7 AND gid=33)
UNION ALL
SELECT 7, 35 WHERE NOT EXISTS (SELECT 1 FROM res_groups_users_rel WHERE uid=7 AND gid=35);

-- Verify
SELECT ru.id, ru.login, array_agg(rg.name->>'en_US') as groups
FROM res_users ru
LEFT JOIN res_groups_users_rel rgur ON ru.id = rgur.uid
LEFT JOIN res_groups rg ON rg.id = rgur.gid
WHERE ru.id = 7
GROUP BY ru.id, ru.login;
