WITH REGRAS_GENERICAS AS (
    SELECT DISTINCT
        NVL(ICM.CODTRIB, -1) AS CODTRIB,
        NVL(ICM.IDALIQ, -1) AS IDALIQ
    FROM TGFICM ICM
    WHERE NVL(TO_CHAR(ICM.CODRESTRICAO), '-1') IN ('-1', '0')
      AND NVL(TO_CHAR(ICM.CODRESTRICAO2), '-1') IN ('-1', '0')
)
SELECT
    COUNT(*) AS REGRAS_GENERICAS_DISTINTAS,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFITE ITE
                WHERE NVL(ITE.CODTRIB, -1) = R.CODTRIB
                  AND ITE.CODPROD IS NOT NULL
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS COM_MATCH_CODTRIB_TGFITE,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFITE ITE
                WHERE NVL(ITE.IDALIQICMS, -1) = R.IDALIQ
                  AND ITE.CODPROD IS NOT NULL
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS COM_MATCH_IDALIQ_TGFITE,
    SUM(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM TGFITE ITE
                WHERE (
                    NVL(ITE.CODTRIB, -1) = R.CODTRIB
                    OR NVL(ITE.IDALIQICMS, -1) = R.IDALIQ
                )
                  AND ITE.CODPROD IS NOT NULL
                  AND ROWNUM = 1
            )
            THEN 1
            ELSE 0
        END
    ) AS COM_MATCH_HISTORICO_TOTAL
FROM REGRAS_GENERICAS R
