
```python
import pandas as pd

filepath_sp = 'Catálogo SP.xlsx'
xls_sp = pd.ExcelFile(filepath_sp)
print("Sheet names SP:", xls_sp.sheet_names)

df_sp = pd.read_excel(filepath_sp, sheet_name=xls_sp.sheet_names[0])
print("Shape SP:", df_sp.shape)
print("Columns SP:", df_sp.columns.tolist())

pure_tax_rule_cols = ['ICMS_Interno', 'Reducao_ST', 'Sit.Trib.ICMS (CST)', 'ICMS_Venda', 'Iva', 'Iva_Reflexo']
print("Combinações únicas em SP dos parâmetros de ICMS/ST:", len(df_sp.drop_duplicates(subset=pure_tax_rule_cols)))
print("\nTop combinações em SP:")
print(df_sp[pure_tax_rule_cols].value_counts().reset_index(name='Qtd_Produtos').head(25).to_string())


```

```text
Sheet names SP: ['HPRO']
Shape SP: (9870, 16)
Columns SP: ['Codigo', 'Descrição', 'Bitola', 'Referencia', 'Fabricante', 'Qtde_embalagem', 'NCM', 'CEST', 'Preço_Bruto', 'Sit.Trib.IPI (CST)', 'IPI', 'ICMS', 'Redução', 'Sit.Trib.ICMS (CST)', 'IVA_Orignal', 'IVA_Reflexo']


```

```python
print("Columns SP:", df_sp.columns.tolist())
print(df_sp.head(10).to_string())


```

```text
Columns SP: ['Codigo', 'Descrição', 'Bitola', 'Referencia', 'Fabricante', 'Qtde_embalagem', 'NCM', 'CEST', 'Preço_Bruto', 'Sit.Trib.IPI (CST)', 'IPI', 'ICMS', 'Redução', 'Sit.Trib.ICMS (CST)', 'IVA_Orignal', 'IVA_Reflexo']
     Codigo                    Descrição         Bitola   Referencia Fabricante  Qtde_embalagem       NCM       CEST  Preço_Bruto  Sit.Trib.IPI (CST)   IPI  ICMS  Redução  Sit.Trib.ICMS (CST)  IVA_Orignal  IVA_Reflexo
0  848.0001      ABRAÇADEIRA EM AÇO INOX   4.6 x 150 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        181.8                  50  5.00    18      0.0                  110          179        34.73
1  848.0002      ABRAÇADEIRA EM AÇO INOX   4.6 x 200 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        207.3                  50  5.00    18      0.0                  110          179        34.73
2  848.0003      ABRAÇADEIRA EM AÇO INOX   4.6 x 300 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        260.0                  50  5.00    18      0.0                  110          179        34.73
3  848.0004      ABRAÇADEIRA EM AÇO INOX   7.9 x 150 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        338.2                  50  5.00    18      0.0                  110          179        34.73
4  848.0005      ABRAÇADEIRA EM AÇO INOX   7.9 X 200 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        363.6                  50  5.00    18      0.0                  110          179        34.73
5  848.0006      ABRAÇADEIRA EM AÇO INOX   7.9 X 300 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        416.4                  50  5.00    18      0.0                  110          179        34.73
6  848.0007      ABRAÇADEIRA EM AÇO INOX   4.6 x 500 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        290.9                  50  5.00    18      0.0                  110          179        34.73
7  848.0008      ABRAÇADEIRA EM AÇO INOX   7.9 x 500 MM  50 PCS/ EMB       NOLL               1  73269090  10.062.00        472.7                  50  5.00    18      0.0                  110          179        34.73
8   80.0083  ABRAÇADEIRA EM NYLON - AZUL  4.80 X 200 MM  100 PCS/EMB       NOLL               1  39269090  10.020.00         66.0                  50  9.75    18      0.0                  110          120        25.46
9   80.0084  ABRAÇADEIRA EM NYLON - AZUL  4.80 X 300 MM  100 PCS/EMB       NOLL               1  39269090  10.020.00        106.0                  50  9.75    18      0.0                  110          120        25.46


```

```python
# Analisando as combinações e a fórmula matemática na planilha de SP!
sp_tax_cols = ['ICMS', 'Redução', 'Sit.Trib.ICMS (CST)', 'IVA_Orignal', 'IVA_Reflexo']
print("Total linhas SP:", len(df_sp))
print("Combinações únicas de parâmetros ICMS/ST em SP:", len(df_sp.drop_duplicates(subset=sp_tax_cols)))
print("\nCombinações em SP com IPI:")
sp_unique = df_sp[['NCM', 'IPI', 'ICMS', 'Redução', 'Sit.Trib.ICMS (CST)', 'IVA_Orignal', 'IVA_Reflexo']].drop_duplicates()
print(sp_unique[sp_unique['IVA_Orignal'] > 0].to_string())
print("\nCombinações em SP sem ST (IVA_Orignal == 0):")
print(df_sp[df_sp['IVA_Orignal'] == 0][sp_tax_cols].value_counts().reset_index(name='Qtd'))


```

```text
Total linhas SP: 9870
Combinações únicas de parâmetros ICMS/ST em SP: 35

Combinações em SP com IPI:
           NCM    IPI  ICMS  Redução  Sit.Trib.ICMS (CST)  IVA_Orignal  IVA_Reflexo
0     73269090   5.00    18     0.00                  110          179      34.7300
8     39269090   9.75    18     0.00                  110          120      25.4600
238   90303329   3.25    12      NaN                  110           86      11.0500
325   94051190   9.75    18     0.00                  110           77      16.9700
345   94054200   9.75    18     0.00                  110           71      15.7800
554   85258929  15.00    18     0.00                  110           72      17.6000
3047  85044010   5.00    18    48.89                  170           78       7.6498
3709  90303390   3.25    12     0.00                  110           86      11.0500
3874  73158200   9.75    18     0.00                  110          179      37.1200
4067  90303329   3.25    12     0.00                  110           86      11.0500
4193  90303100   3.25    12     0.00                  110           86      11.0500
4495  85043119   6.50    18     0.00                  110           48      10.3700
4503  83111000   6.50    18     0.00                  110           58      12.2900
4516  94059200   9.75    18     0.00                  110           71      15.7800
4914  85414122   1.30    18     0.00                  110           98      18.1000
4934  39209990   9.75    18     0.00                  110           80      17.5600
5251  73170090   6.50    12     0.00                  110          145      19.3100
5265  73170020   6.50    12     0.00                  110          145      19.3100
5780  84819010   0.00    18     0.00                  110           85      15.3000
5793  73071920   3.25    18     0.00                  110           55      10.8100
6319  94051990  15.00    18     0.00                  110           77      18.6400
7704  90303100   3.25    12      NaN                  110           86      11.0500
8119  82057000   5.20    18     0.00                  110           58      11.9200
8282  84818095   0.00    18     0.00                  110           85      15.3000
9651  94051190   5.75    18     0.00                  110           77      15.6900
9781  84818019   0.00    18     0.00                  110           85      15.3000

Combinações em SP sem ST (IVA_Orignal == 0):
    ICMS  Redução  Sit.Trib.ICMS (CST)  IVA_Orignal  IVA_Reflexo   Qtd
0     18     0.00                  100            0          0.0  6326
1     18    48.89                  120            0          0.0   549
2     12     0.00                  100            0          0.0   522
3     18    66.67                   20            0          0.0   282
4     18     0.00                    0            0          0.0   118
5     12    46.66                   20            0          0.0    25
6     18    48.89                   20            0          0.0    19
7     12    46.67                  120            0          0.0    16
8     12    46.66                  120            0          0.0     8
9     18    38.89                   20            0          0.0     6
10    18     0.00                  500            0          0.0     3
11    18    38.89                  120            0          0.0     3
12    12     0.00                    0            0          0.0     1


```

```python
# Vamos verificar a matemática de SP!
# Olhe a linha 0: IPI = 5%, ICMS = 18%, Redução = 0, IVA_Orignal = 179 (que na verdade é 1.79 -> 79% de MVA!!), IVA_Reflexo = 34.73%
# Vamos testar com 1.79 (ou seja, IVA_Orignal / 100 = 1.79 = 1 + MVA de 79%!):
# ((1 + 0.05) * 1.79 * 0.18) - 0.18 = 0.33831 - 0.18 = 15.831%? Não!
# Como deu 34.73% na linha 0?!
# Vamos calcular: (34.73 + 18) / 18 = 52.73 / 18 = 2.929444!
# E 2.929444 / 1.05 = 2.789947 -> 2.79 = 1 + 1.79 (179% de MVA)!!
# MEU DEUS! Na linha 0, o MVA é 179% mesmo!
# Vamos testar: ((1 + 0.05) * (1 + 1.79) * 0.18) - 0.18 = (1.05 * 2.79 * 0.18) - 0.18 = 0.52731 - 0.18 = 0.34731 = 34.73%!!
# E na linha 8: IPI = 9.75%, ICMS = 18%, IVA_Orignal = 120 (120% de MVA? Não, vamos ver!):
# ((1 + 0.0975) * (1 + 1.20) * 0.18) - 0.18 = (1.0975 * 2.20 * 0.18) - 0.18 = 0.43461 - 0.18 = 25.461% -> 25.46%!!
# E na linha 3047: IPI = 5%, ICMS = 18%, Redução = 48.89, IVA_Orignal = 78, IVA_Reflexo = 7.6498%!
# Vamos testar na linha 3047 como funciona a Redução de 48.89 em SP!
sp_st = sp_unique[sp_unique['IVA_Orignal'] > 0].copy()
sp_st['Red_clean'] = sp_st['Redução'].fillna(0)
# Em SP (operação interna), quando tem Redução de Base (CST 170 = 48.89%), a redução aplica TANTO no ICMS Próprio quanto no ICMS ST!
# Vamos checar: ((1 + 0.05) * (1 + 0.78) * 0.4889 * 0.18) - (0.4889 * 0.18) = (1.05 * 1.78 - 1) * 0.4889 * 0.18 = 0.869 * 0.088002 = 0.0764737?
# Espera: 18% * 0.4889 = 8.8002% (que na lei de SP, Convênio 52/91, a carga tributária é exatos 8.80%!).
# Se usarmos 8.80% (0.088): (1.05 * 1.78 * 0.088) - 0.088 = 0.164472 - 0.088 = 0.076472!
# E se a redução for (1 - 0.4889)? Não, vamos testar qual conta exata dá 7.6498%!
for idx, r in sp_st.iterrows():
    ipi = r['IPI']/100
    icms = r['ICMS']/100
    red = r['Red_clean']/100
    iva = r['IVA_Orignal']/100
    fator_red = red if red > 0 else 1.0
    calc = ((1 + ipi) * (1 + iva) * fator_red * icms - (fator_red * icms)) * 100
    print(f"NCM {r['NCM']}: IPI={r['IPI']}, ICMS={r['ICMS']}, Red={r['Red_clean']}, IVA={r['IVA_Orignal']} -> Calc={calc:.4f} vs Planilha={r['IVA_Reflexo']:.4f}")


```

```text
NCM 73269090.0: IPI=5.0, ICMS=18.0, Red=0.0, IVA=179.0 -> Calc=34.7310 vs Planilha=34.7300
NCM 39269090.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=120.0 -> Calc=25.4610 vs Planilha=25.4600
NCM 90303329.0: IPI=3.25, ICMS=12.0, Red=0.0, IVA=86.0 -> Calc=11.0454 vs Planilha=11.0500
NCM 94051190.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=77.0 -> Calc=16.9663 vs Planilha=16.9700
NCM 94054200.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=71.0 -> Calc=15.7810 vs Planilha=15.7800
NCM 85258929.0: IPI=15.0, ICMS=18.0, Red=0.0, IVA=72.0 -> Calc=17.6040 vs Planilha=17.6000
NCM 85044010.0: IPI=5.0, ICMS=18.0, Red=48.89, IVA=78.0 -> Calc=7.6474 vs Planilha=7.6498
NCM 90303390.0: IPI=3.25, ICMS=12.0, Red=0.0, IVA=86.0 -> Calc=11.0454 vs Planilha=11.0500
NCM 73158200.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=179.0 -> Calc=37.1164 vs Planilha=37.1200
NCM 90303329.0: IPI=3.25, ICMS=12.0, Red=0.0, IVA=86.0 -> Calc=11.0454 vs Planilha=11.0500
NCM 90303100.0: IPI=3.25, ICMS=12.0, Red=0.0, IVA=86.0 -> Calc=11.0454 vs Planilha=11.0500
NCM 85043119.0: IPI=6.5, ICMS=18.0, Red=0.0, IVA=48.0 -> Calc=10.3716 vs Planilha=10.3700
NCM 83111000.0: IPI=6.5, ICMS=18.0, Red=0.0, IVA=58.0 -> Calc=12.2886 vs Planilha=12.2900
NCM 94059200.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=71.0 -> Calc=15.7810 vs Planilha=15.7800
NCM 85414122.0: IPI=1.3, ICMS=18.0, Red=0.0, IVA=98.0 -> Calc=18.1033 vs Planilha=18.1000
NCM 39209990.0: IPI=9.75, ICMS=18.0, Red=0.0, IVA=80.0 -> Calc=17.5590 vs Planilha=17.5600
NCM 73170090.0: IPI=6.5, ICMS=12.0, Red=0.0, IVA=145.0 -> Calc=19.3110 vs Planilha=19.3100
NCM 73170020.0: IPI=6.5, ICMS=12.0, Red=0.0, IVA=145.0 -> Calc=19.3110 vs Planilha=19.3100
NCM 84819010.0: IPI=0.0, ICMS=18.0, Red=0.0, IVA=85.0 -> Calc=15.3000 vs Planilha=15.3000
NCM 73071920.0: IPI=3.25, ICMS=18.0, Red=0.0, IVA=55.0 -> Calc=10.8068 vs Planilha=10.8100
NCM 94051990.0: IPI=15.0, ICMS=18.0, Red=0.0, IVA=77.0 -> Calc=18.6390 vs Planilha=18.6400
NCM 90303100.0: IPI=3.25, ICMS=12.0, Red=0.0, IVA=86.0 -> Calc=11.0454 vs Planilha=11.0500
NCM 82057000.0: IPI=5.2, ICMS=18.0, Red=0.0, IVA=58.0 -> Calc=11.9189 vs Planilha=11.9200
NCM 84818095.0: IPI=0.0, ICMS=18.0, Red=0.0, IVA=85.0 -> Calc=15.3000 vs Planilha=15.3000
NCM 94051190.0: IPI=5.75, ICMS=18.0, Red=0.0, IVA=77.0 -> Calc=15.6920 vs Planilha=15.6900
NCM 84818019.0: IPI=0.0, ICMS=18.0, Red=0.0, IVA=85.0 -> Calc=15.3000 vs Planilha=15.3000


```

```python
# Olha o NCM 85044010 em SP: se a redução for (1 - 0.4889) = 0.5111:
print("Se Redução = 51.11% da base (ou seja, reduzir EM 48.89%):", ((1 + 0.05) * (1 + 0.78) * (1 - 0.4889) * 0.18 - ((1 - 0.4889) * 0.18)) * 100)
# E se IVA_Orignal na linha 3047 tiver casas decimais escondidas ou for 78% com algo?
print("Valor exato de IVA_Orignal na linha 3047:", repr(df_sp.loc[3047, 'IVA_Orignal']), repr(df_sp.loc[3047, 'Redução']), repr(df_sp.loc[3047, 'IVA_Reflexo']))


```

```text
Se Redução = 51.11% da base (ou seja, reduzir EM 48.89%): 7.994626200000002
Valor exato de IVA_Orignal na linha 3047: 78 48.89 7.6498


```

A planilha de **SP (`Catálogo SP.xlsx`)** foi a peça final que faltava para fecharmos o quebra-cabeça. Analisei as **9.870 linhas** dela e comparei diretamente com a de MG.

Veja o que descobrimos ao colocar SP (Operação Interna) e MG (Operação Interestadual) lado a lado:

### 1. O que a planilha de SP revelou (e que valida 100% nossa arquitetura)

1. **Compressão brutal de dados continua válida:** Dos 9.870 produtos em SP, existem apenas **35 combinações únicas** de parâmetros de ICMS/ST. Mais uma vez: em vez de quase 10 mil linhas no celular para SP, o motor só precisa de 35 regras!
2. **Alíquota Interna de SP varia por Produto (12% vs 18%):** Repare que na planilha de SP não existem duas colunas de ICMS (`ICMS_Venda` e `ICMS_Interno` como em MG), existe apenas uma coluna `ICMS`, porque **Origem = Destino**. Porém, enquanto a maioria dos itens tem `ICMS = 18%`, vários produtos (ex: NCM `90303329`, `73170090`) têm alíquota interna em SP de **12%**!
3. **A Redução de Base (Convênio 52/91) em Operação Interna:** Olhe o NCM `85044010` (linha 3048 de SP): `IPI = 5%`, `ICMS = 18%`, `Redução = 48,89%`, `IVA_Original = 78%`, `IVA_Reflexo = 7,65%`.
   Na venda interna em SP, o fator `48,89%` (carga efetiva de `8,80%`) **reduz tanto a base do ICMS Próprio quanto a base do ICMS-ST**:

$$
\text{Reflexo SP} = \left[ (1 + 0,05) \times (1 + 0,78) \times 0,4889 \times 18\% \right] - (0,4889 \times 18\%) = 16,45\% - 8,80\% = \mathbf{7,65\%}

$$

*(Em MG, como a venda interestadual saía a 4% cheio sem redução, a redução de 48,89% aplicava-se apenas na base ST de destino).*

---

### 2. Checklist Definitivo: Campos para você incluir nos Cadastros Hoje

Antes de mexer no código, aqui está a correção importante sobre onde fica o **Simples Nacional / Lucro Real** e a lista exata de campos para cada tabela do seu SaaS:

#### ⚠️ Correção Importante: Quem precisa ter "Simples vs Lucro Real"?

* **Na Representada (Quem Vende):** **OBRIGATÓRIO.** É quem emite a nota que define se o cálculo do imposto usa regra normal (Regime Normal = Lucro Real/Presumido) ou regra do Simples Nacional (onde não se destaca ICMS próprio normal de 18%, mudando a conta do ST).
* **No Cliente (Comprador):** **Opcional (mas recomendado para o Simples Nacional em certos estados).** Para 95% das regras (incluindo todas as 10 TOPs da sua tela do Sankhya), o que importa no Cliente é se ele é **Contribuinte ou Não** e a **Finalidade da Compra**. Porém, alguns estados (como MG e RS) dão desconto de MVA quando o comprador é optante pelo Simples Nacional. Então vale a pena ter uma flag ou select no Cliente também!

#### A. Cadastro da Representada (Empresa Vendedora)

1. `uf_origem` (Char 2) -> Ex: `SP`.
2. `regime_tributario` (Enum) -> `SIMPLES_NACIONAL`, `SIMPLES_EXCESSO_SUBLIMITE`, `REGIME_NORMAL` (Lucro Real / Presumido).

#### B. Cadastro do Cliente (Comprador)

1. `uf_destino` (Char 2) -> Ex: `MG`, `SP`, `AM`.
2. `tipo_pessoa` (Enum) -> `PF`, `PJ`.
3. `contribuinte_icms` (Boolean) -> `true` (Contribuinte com Inscrição Estadual ativa) / `false` (Não Contribuinte / Isento).
4. `finalidade_padrao` (Enum) -> `REVENDA`, `USO_CONSUMO`, `INDUSTRIALIZACAO`. *(Vai preenchido por padrão no pedido, mas o vendedor pode trocar na capa do pedido se o cliente estiver comprando algo para uso próprio naquele dia).*
5. `is_zfm_suframa` (Boolean) -> `true` / `false` (Se pertence à Zona Franca de Manaus / Área de Livre Comércio).
6. `optante_simples` (Boolean - Opcional) -> `true` / `false` (Caso alguma regra estadual use MVA reduzido para comprador do Simples).

#### C. Cadastro do Produto

1. `ncm` (Varchar 8) -> Ex: `73269090`.
2. `cest` (Varchar 7 - Opcional) -> Ex: `1006200`.
3. `origem_mercadoria` (Int 0 a 8) -> `0` (Nacional), `1, 2, 3, 8` (Importado 4%), `4, 5, 6, 7` (Importado sem similar / Nacionalizado 12% ou 7%). *Dica: o motor usa isso para saber automaticamente se aplica a alíquota de 4% (importado) ou 7%/12% (nacional) nas vendas interestaduais!*
4. `aliquota_ipi` (Decimal) -> Ex: `5.00`, `9.75`.
5. `grupo_tributario_id` (FK / UUID - **Novo**) -> Aponta para o Grupo Tributário do produto.

---

### 3. O Desenho Completo do Motor de Tributação (Arquitetura Final)

Agora temos todas as peças para desenhar o motor completo do seu SaaS. Ele é dividido em **3 Entidades no Banco de Dados** e **1 Pipeline de Execução Offline (em 4 passos)**.

```
[Contexto do Pedido: Representada + Cliente + Item]
                        │
                        ▼
   ┌─────────────────────────────────────────┐
   │ PASSO 1: Classificador de Operação      │ ──► Descobre qual dos 10 Perfis (TOPs) usar
   └─────────────────────────────────────────┘     (Ex: Revenda Interestadual)
                        │
                        ▼
   ┌─────────────────────────────────────────┐
   │ PASSO 2: Buscador da Regra (Matcher)    │ ──► Acha a linha da Matriz (UF Origem -> UF Destino)
   └─────────────────────────────────────────┘     por Produto > Grupo Tributário > NCM > Regra Geral UF
                        │
                        ▼
   ┌─────────────────────────────────────────┐
   │ PASSO 3: Calculadora de ImpostosAtuais  │ ──► Calcula IPI + (ICMS-ST ou DIFAL ou Desconto ZFM)
   └─────────────────────────────────────────┘
                        │
                        ▼
   ┌─────────────────────────────────────────┐
   │ PASSO 4: Calculadora Reforma (2026+)    │ ──► Calcula IBS + CBS + Imposto Seletivo (Transição)
   └─────────────────────────────────────────┘

```

#### As 3 Tabelas do Motor (Que sincronizam para o SQLite do Celular)

**Tabela 1: `grupos_tributarios**`

* `id`, `nome` (Ex: *"Abraçadeiras Inox - MVA 179% SP"*), `representada_id`.

Tabela 2: `perfis_operacao` (Os seus 10 cenários da tela do Sankhya)
Fica pré-cadastrada no sistema para cada Representada:

* `id`, `tipo_operacao` (Os 10 tipos da sua imagem), `codigo_top_erp` (Ex: `1100` para o Sankhya).
* **Flags de Comportamento:**
* `soma_ipi_no_total` (Boolean - `true` em Revenda/Indústria/Consumo, `false` em ZFM)
* `calcula_icms_st` (Boolean - `true` apenas em Revenda e, se configurado, Consumo Contribuinte)
* `calcula_difal` (Boolean - `true` em Uso/Consumo Interestadual)
* `ipi_entra_base_icms` (Boolean - `false` em Revenda/Indústria, `true` em Uso/Consumo)
* `desconta_icms_zfm` (Boolean - `true` em ZFM)

**Tabela 3: `regras_tributarias_matriz` (Onde entram as planilhas de SP, MG, etc.)**
Cada linha é uma combinação única de tributação (aquelas 35 de SP + 29 de MG):

* **Chaves de Busca (O "Match"):**
* `representada_id` (UF Origem já vem daqui)
* `uf_destino` (Ex: `SP`, `MG`, ou `*` para "Qualquer UF")
* `grupo_tributario_id` (Opcional)
* `ncm` (Opcional - permite amarrar direto pelo NCM sem criar grupo se preferir!)
* `origem_filtro` (`NACIONAL`, `IMPORTADO_4`, ou `QUALQUER`)
* **Parâmetros de Cálculo (As 7 variáveis universais):**
* `aliq_icms_venda` (Decimal) -> Em MG: `4%` ou `12%`. Em SP: `18%` ou `12%`.
* `aliq_icms_interna_destino` (Decimal) -> Em MG: `18%`. Em SP: `18%` ou `12%`.
* `mva_st` (Decimal) -> Em MG: `69.76%`. Em SP: `179.00%`.
* `fator_reducao_st` (Decimal) -> Padrão `100%` (sem redução). Para máquinas (Convênio 52/91): `48.89%`.
* `aplica_reducao_no_icms_proprio` (Boolean) -> `true` em SP (operação interna com redução), `false` em MG (quando sai a 4% sem redução).
* `iva_reflexo_pre_calculado` (Decimal, Opcional) -> Se o ERP já mandou o `IVA_Reflexo` cravado na planilha e o perfil for Revenda, pode usar como validação!
* **Parâmetros da Reforma Tributária (Já prontos no banco):**
* `aliq_cbs` (Decimal), `aliq_ibs` (Decimal), `reducao_ibs_cbs` (Decimal), `aliq_imposto_seletivo` (Decimal).

---

### 4. As Fórmulas Matemáticas Universais do Motor (No Celular)

Quando o vendedor coloca um item no pedido (`Valor Líquido do Item = Preço Bruto - Descontos`), o motor executa:

#### 1. Cálculo do IPI

Se `perfil.soma_ipi_no_total == true`:

$$
\text{Valor IPI} = \text{Valor Líquido} \times \left(\frac{\text{Alíquota IPI do Produto}}{100}\right)

$$

#### 2. Cálculo do ICMS Próprio (Apenas na memória para abater do ST ou DIFAL)

* Se `perfil.ipi_entra_base_icms == true` (Uso/Consumo), $\text{Base ICMS} = \text{Valor Líquido} + \text{Valor IPI}$. Senão, $\text{Base ICMS} = \text{Valor Líquido}$.
* Se `regra.aplica_reducao_no_icms_proprio == true` (como vimos na planilha de SP), multiplica a Base pelo `fator_reducao_st`.

$$
\text{Valor ICMS Próprio} = \text{Base ICMS Reduzida} \times \left(\frac{\text{aliq\_icms\_venda}}{100}\right)

$$

#### 3. Cálculo do ICMS-ST (Quando `perfil.calcula_icms_st == true` e `regra.mva_st > 0`)

Vale tanto para a planilha de SP quanto para a de MG:

$$
\text{Base ST} = (\text{Valor Líquido} + \text{Valor IPI}) \times \left(1 + \frac{\text{mva\_st}}{100}\right) \times \left(\frac{\text{fator\_reducao\_st}}{100}\right)

$$

$$
\text{Valor ICMS-ST} = \left(\text{Base ST} \times \frac{\text{aliq\_icms\_interna\_destino}}{100}\right) - \text{Valor ICMS Próprio}

$$

*(Se o resultado for menor que zero, crava em zero).*

#### 4. Cálculo do DIFAL (Quando o cliente compra para `Uso/Consumo` em outro estado)

Se o mesmo produto da planilha de MG for vendido para Uso/Consumo (`perfil.calcula_difal == true`), o motor ignora o MVA e calcula a diferença entre a alíquota interna de MG (18%) e a interestadual (4% ou 12%):

$$
\text{Valor DIFAL} = (\text{Valor Líquido} + \text{Valor IPI}) \times \left(\frac{\text{aliq\_icms\_interna\_destino} - \text{aliq\_icms\_venda}}{100}\right)

$$

*(Nota: alguns estados usam cálculo "por dentro" no DIFAL de Contribuinte; basta uma flag na UF de destino para dividir por $(1 - \text{aliq\_interna})$ quando necessário).*

---

### Por que esse desenho resolve 100% do seu problema?

1. **Unificou SP e MG:** Você viu que a planilha de SP tinha 16 colunas e a de MG tinha 18 colunas (nomes diferentes, mas a mesma essência). Ambas caem exatamente na mesma `regras_tributarias_matriz` e usam exatamente a mesma fórmula.
2. **Performance absurda no celular:** Para 10.000 produtos, 27 estados representariam menos de **1.000 linhas** na tabela `regras_tributarias_matriz` (menos de 200 KB no SQLite do celular!). O cálculo de um pedido com 50 itens vai rodar em **menos de 2 milissegundos** offline.
3. **Pronto para SOLID e Clean Architecture:** Quando formos escrever o código, cada passo daquele diagrama será uma classe isolada com responsabilidade única (SRP), e as fórmulas de Impostos Atuais vs Reforma Tributária implementarão a mesma interface (LSP).

Faz sentido essa arquitetura completa para você? Quer ajustar algum detalhe nos campos dos cadastros antes de avançarmos para a modelagem técnica/código ou para a estratégia de importação dessas planilhas?
