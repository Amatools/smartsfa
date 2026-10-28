Guia rapido de Regras de Tributacao (versao para usuarios)

> Nota: para a especificacao tecnica completa e atualizada do motor de tributacao, ver [tributacao_motor_especificacao_tecnica.md](tributacao_motor_especificacao_tecnica.md). Este guia e uma versao simplificada para usuario final.

Para simplificar o dia a dia da sua empresa, o sistema calcula os impostos automaticamente na venda.
Ele cruza 3 grupos de informacoes:

- Regra fiscal cadastrada no portal.
- Cadastro do cliente.
- Cadastro do produto.

Este guia explica, em linguagem simples, quando voce precisa criar uma regra nova e quando o sistema apenas aplica ajustes.

1) O que realmente cria uma regra nova

No modelo simplificado do SmartSFA, uma nova linha de regra fiscal e criada quando muda a combinacao abaixo:

- NCM + CEST do produto.
- UF de origem da venda.
- UF de destino (estado do cliente).

Resumo pratico:
- Mudou NCM, CEST, origem ou destino: cria nova regra.
- Nao mudou esses 4 pontos: em geral reaproveita a mesma regra.

2) O que NAO cria regra nova (apenas ajusta o calculo)

As informacoes abaixo funcionam como "chaves de comportamento" em cima da regra ja encontrada:

- Perfil tributario do cliente (contribuinte ou nao contribuinte).
- Finalidade da venda (revenda ou uso e consumo).
- ZFM / SUFRAMA (quando aplicavel).
- Origem da mercadoria no produto (nacional/importado).
- IPI no cadastro do produto.

Ou seja: essas informacoes alteram o resultado final do imposto, mas nao exigem uma nova linha para cada cliente.

3) Como o cadastro do cliente altera o calculo

- Perfil tributario:
	- Cliente contribuinte: segue fluxo normal de ICMS e regras de ST quando aplicaveis.
	- Cliente nao contribuinte: o sistema prioriza a logica de diferenca de aliquota (DIFAL) quando o cenario exigir.

- Finalidade da venda:
	- Revenda: segue fluxo comercial de revenda.
	- Uso e consumo: muda o enquadramento fiscal da operacao e o comportamento de ST/DIFAL.

- ZFM / SUFRAMA:
	- Quando o cliente estiver elegivel, o sistema aplica o tratamento fiscal especial previsto na configuracao.

4) Como o cadastro do produto altera o calculo

- NCM e CEST:
	- Sao a base para localizar a regra correta.

- Origem da mercadoria:
	- Influencia o tratamento de ICMS da operacao conforme configuracao fiscal.

- IPI:
	- O percentual vem do cadastro do produto e entra no calculo do item.

5) Checklist para o calculo funcionar bem

Antes de validar os valores do pedido, confirme:

- Produto com NCM preenchido.
- Produto com CEST preenchido (quando aplicavel ao NCM).
- Produto com origem da mercadoria preenchida.
- Produto com aliquota de IPI preenchida (quando houver IPI).
- Cliente com UF correta.
- Cliente com perfil tributario correto.
- Cliente com finalidade de venda correta.
- Cliente com indicacao ZFM/SUFRAMA correta (quando aplicavel).
- Regra fiscal cadastrada para o par UF origem x UF destino.

6) Escopo desta simplificacao

Este modelo foi pensado para a operacao comercial padrao do projeto, sem foco em segmentos com tributacao excepcional (por exemplo: armas, bebidas alcoolicas e veiculos com regras altamente especificas).

Nesses segmentos especiais, pode ser necessario detalhamento fiscal adicional.

7) Regra de ouro

Se o cadastro estiver correto e a combinacao NCM + CEST + UF origem/destino estiver coberta, o sistema consegue calcular o pedido com consistencia no modelo simplificado.
