WITH CODTRIB_GENERICO AS (
    SELECT DISTINCT NVL(ICM.CODTRIB, -1) AS CODTRIB
    FROM TGFICM ICM
    WHERE NVL(TO_CHAR(ICM.CODRESTRICAO), '-1') IN ('-1', '0')
      AND NVL(TO_CHAR(ICM.CODRESTRICAO2), '-1') IN ('-1', '0')
)
SELECT
    COUNT(*) AS CODTRIB_DISTINTOS_GENERICOS,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFPRO PRO
                WHERE PRO.ATIVO = 'S'
                  AND NVL(PRO.GRUPOICMS, -1) = C.CODTRIB
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS CODTRIB_COM_MATCH_GRUPOICMS,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFPRO PRO
                WHERE PRO.ATIVO = 'S'
                  AND NVL(PRO.GRUPOICMS2, -1) = C.CODTRIB
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS CODTRIB_COM_MATCH_GRUPOICMS2,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFPRO PRO
                WHERE PRO.ATIVO = 'S'
                  AND (
                    NVL(PRO.GRUPOICMS, -1) = C.CODTRIB
                    OR NVL(PRO.GRUPOICMS2, -1) = C.CODTRIB
                  )
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS CODTRIB_COM_MATCH_EM_QUALQUER_GRUPO
FROM CODTRIB_GENERICO C
