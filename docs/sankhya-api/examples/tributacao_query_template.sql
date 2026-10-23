-- Consulta de referencia para alimentar o motor de tributacao do SFA.
-- Objetivo: entregar contrato principal do tax_rules e metadados DIFAL/FCP.

SELECT
    'active' AS STATUS,

    -- NCM prioriza restricao por NCM; se nao houver, usa NCM do produto
    -- quando a restricao for por produto.
    CASE
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN NCM1.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4')
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN NCM2.CODNCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN PRO1.NCM
        WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN PRO2.NCM
        ELSE NULL
    END AS NCM,

    -- CEST vem do produto quando a regra estiver atrelada a item.
    CASE
        WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
            THEN PRO1.CODESPECST
        WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
             AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
            THEN PRO2.CODESPECST
        ELSE NULL
    END AS CEST,

    NVL(UFO.UF, 'ANY') AS UFORIGEM,
    NVL(UFD.UF, 'ANY') AS UFDESTINO,

    -- O importador do SFA aceita apenas MVA ou PMC.
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.PAUTAVLRSTFIXO), '')) NOT IN ('', '0', '0,0', '0,00', '0.0', '0.00', 'N') THEN 'pmc'
        ELSE 'mva'
    END AS TIPOST,

    -- Opcional: preco de referencia para calculo ST por MVA.
    TO_CHAR(NULL) AS PRECOPARACALCULOST,

    -- Para MVA, o importador exige reducao base (0 quando nao houver).
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.REDBASEST), '')) IN ('', 'N') THEN '0'
        ELSE TO_CHAR(ICM.REDBASEST)
    END AS REDUCAOBASEICMSST,

    -- Para PMC, o importador usa base fixa da pauta.
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.PAUTAVLRSTFIXO), '')) IN ('', 'N') THEN '0'
        ELSE TO_CHAR(ICM.PAUTAVLRSTFIXO)
    END AS BASECALCULOICMSST,

    -- Aliquota destino: prefere ST explicita e depois internas da regra.
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.ALIQSUBTRIB), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.ALIQSUBTRIB)
        WHEN TRIM(NVL(TO_CHAR(ICM.ALIQINTDEST), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.ALIQINTDEST)
        WHEN TRIM(NVL(TO_CHAR(ICM.ALIQUOTA), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.ALIQUOTA)
        ELSE '0'
    END AS ALIQUOTADESTINO,

    -- Aliquota credito/propria.
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.ALIQUOTA), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.ALIQUOTA)
        WHEN TRIM(NVL(TO_CHAR(ICM.ALIQINTDEST), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.ALIQINTDEST)
        ELSE '0'
    END AS ALIQUOTACREDITO,

    -- ALIQUOTADIFAL no contrato principal.
    -- Durante rollout, manter nulo e usar metadados auxiliares abaixo.
    TO_CHAR(NULL) AS ALIQUOTADIFAL,

    TO_CHAR(ICM.CSOSN) AS CST_CSOSN,

    -- MVA efetiva: prioriza original e fallback para simplificada.
    CASE
        WHEN TRIM(NVL(TO_CHAR(ICM.MVAORIGINAL), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.MVAORIGINAL)
        WHEN TRIM(NVL(TO_CHAR(ICM.MVASIMPLIFICADO), '')) NOT IN ('', 'N') THEN TO_CHAR(ICM.MVASIMPLIFICADO)
        ELSE '0'
    END AS MVA,

    -- Campo livre para observacao da origem da regra no Sankhya.
    (
        'TIPRESTRICAO=' || NVL(TO_CHAR(ICM.TIPRESTRICAO), '-') ||
        ';CODRESTRICAO=' || NVL(TO_CHAR(ICM.CODRESTRICAO), '-') ||
        ';TIPRESTRICAO2=' || NVL(TO_CHAR(ICM.TIPRESTRICAO2), '-') ||
        ';CODRESTRICAO2=' || NVL(TO_CHAR(ICM.CODRESTRICAO2), '-') ||
        ';TIPCALCDIFAL=' || NVL(TO_CHAR(ICM.TIPCALCDIFAL), '-')
    ) AS EXCECAOFISCAL,

    ICM.DTINICIOVIGENCIA AS VIGENCIAINICIAL,
    ICM.DTFIMVIGENCIA AS VIGENCIAFINAL,

    -- Prioridade maior para regra mais especifica.
    TO_CHAR(
        CASE
            WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 300000 + NVL(ICM.SEQUENCIA, 0)
            WHEN TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4')
                 AND TO_CHAR(ICM.CODRESTRICAO) NOT IN ('-1', '0')
                THEN 200000 + NVL(ICM.SEQUENCIA, 0)
            WHEN TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4')
                 AND TO_CHAR(ICM.CODRESTRICAO2) NOT IN ('-1', '0')
                THEN 190000 + NVL(ICM.SEQUENCIA, 0)
            ELSE 100000 + NVL(ICM.SEQUENCIA, 0)
        END
    ) AS PRIORIDADE,

    -- Colunas extras para rastreio, reconciliacao e evolucao DIFAL/FCP.
    TO_CHAR(ICM.CODTRIB) AS GRUPOFISCALID,
    TO_CHAR(ICM.CODTAB) AS CODTAB,
    TO_CHAR(ICM.SEQUENCIA) AS SEQUENCIA,
    TO_CHAR(ICM.IDALIQ) AS IDALIQ,
    TO_CHAR(ICM.TIPCALCDIFAL) AS TIPOCALCULODIFAL,
    TO_CHAR(ICM.PERCICMSFCP) AS PERCENTUALFCP,
    TO_CHAR(ICM.PERCICMSFCPINT) AS PERCENTUALFCPINTERNO,
    TO_CHAR(ICM.FORMCALFCPDIFAL) AS FORMULAFCPDIFAL,
    TO_CHAR(ICM.CODFORMCALCDIFAL) AS FORMULADIFAL,
    TO_CHAR(ICM.CODFORMBASDIFAL) AS FORMULABASEDIFAL,
    TO_CHAR(ICM.REPDIFALFCP) AS REPASSEDIFALFCP

FROM TGFICM ICM
LEFT JOIN TSIUFS UFO
    ON ICM.UFORIG = UFO.CODUF
LEFT JOIN TSIUFS UFD
    ON ICM.UFDEST = UFD.CODUF
LEFT JOIN TGFPRO PRO1
    ON TO_CHAR(ICM.TIPRESTRICAO) IN ('P', '1')
    AND ICM.CODRESTRICAO = PRO1.CODPROD
LEFT JOIN TGFPRO PRO2
     ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('P', '1')
    AND ICM.CODRESTRICAO2 = PRO2.CODPROD
LEFT JOIN TGFNCM NCM1
    ON TO_CHAR(ICM.TIPRESTRICAO) IN ('N', '4')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO), '0') = LTRIM(REPLACE(NCM1.CODNCM, '.', ''), '0')
LEFT JOIN TGFNCM NCM2
    ON TO_CHAR(ICM.TIPRESTRICAO2) IN ('N', '4')
   AND LTRIM(TO_CHAR(ICM.CODRESTRICAO2), '0') = LTRIM(REPLACE(NCM2.CODNCM, '.', ''), '0')

WHERE
    ICM.DTINICIOVIGENCIA IS NULL
    OR ICM.DTINICIOVIGENCIA <= SYSDATE

ORDER BY
    UFORIGEM,
    UFDESTINO,
    PRIORIDADE DESC,
    NCM,
    CEST
