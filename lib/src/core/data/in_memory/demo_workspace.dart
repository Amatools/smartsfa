import '../../models/app_identity.dart';
import '../../models/cliente.dart';
import '../../models/cliente_pre_cadastro.dart';
import '../../models/cliente_reference.dart';
import '../../models/pedido.dart';
import '../../models/domain_types.dart';
import '../../models/produto.dart';
import 'in_memory_cliente_pre_cadastro_repository.dart';
import 'in_memory_cliente_repository.dart';
import 'in_memory_pedido_repository.dart';
import 'in_memory_produto_repository.dart';

class DemoWorkspace {
  DemoWorkspace({
    required this.clientes,
    required this.preCadastros,
    required this.produtos,
    required this.pedidos,
  });

  factory DemoWorkspace.seeded(AppIdentity identity) {
    final now = DateTime.now();
    final tenantId = identity.tenantId;

    return DemoWorkspace(
      clientes: InMemoryClienteRepository(
        seedItems: [
          Cliente(
            id: 'cli-001',
            tenantId: tenantId,
            nome: 'Auto Pecas Central',
            documento: '12.345.678/0001-90',
            origemCadastro: CustomerOrigin.manual,
            status: CustomerStatus.approved,
            ownerId: 'owner-001',
            gerenteId: 'ger-001',
            representanteId: 'rep-001',
            vendedorId: 'vnd-001',
            createdAt: now,
          ),
          Cliente(
            id: 'cli-002',
            tenantId: tenantId,
            nome: 'Casa do Motor',
            documento: '98.765.432/0001-10',
            origemCadastro: CustomerOrigin.erp,
            status: CustomerStatus.synchronized,
            ownerId: 'owner-001',
            gerenteId: 'ger-001',
            representanteId: 'rep-002',
            vendedorId: 'vnd-002',
            createdAt: now,
          ),
        ],
      ),
      preCadastros: InMemoryClientePreCadastroRepository(
        seedItems: [
          ClientePreCadastro(
            id: 'pre-001',
            tenantId: tenantId,
            nome: 'Mecânica do Vale',
            documento: '55.123.456/0001-77',
            status: PreRegistrationStatus.pending,
            requestedByUid: 'user-001',
            email: 'contato@mecanica.com.br',
            celular: '(11) 99999-1234',
            origemCadastro: CustomerOrigin.manual,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
      produtos: InMemoryProdutoRepository(
        seedItems: [
          Produto(
            id: 'prod-001',
            tenantId: tenantId,
            codigoInterno: 'P-1001',
            descricao: 'Filtro de oleo premium',
            origemCadastro: ProductSource.manual,
            status: ProductStatus.active,
            tabelaPrecoVersao: '2026.09',
            estoqueVersao: '2026.09.01',
            createdAt: now,
          ),
          Produto(
            id: 'prod-002',
            tenantId: tenantId,
            codigoInterno: 'P-1002',
            descricao: 'Jogo de velas iridium',
            origemCadastro: ProductSource.erp,
            status: ProductStatus.active,
            tabelaPrecoVersao: '2026.09',
            estoqueVersao: '2026.09.01',
            createdAt: now,
          ),
        ],
      ),
      pedidos: InMemoryPedidoRepository(
        seedItems: [
          Pedido(
            id: 'ped-001',
            tenantId: tenantId,
            origemPedido: OrderOrigin.manual,
            statusFila: OrderStatus.pendingSend,
            clienteReferencia: ClienteReference(
              id: 'cli-001',
              type: CustomerReferenceType.official,
              documentoSnapshot: '12.345.678/0001-90',
              nomeSnapshot: 'Auto Pecas Central',
            ),
            ownerId: 'owner-001',
            gerenteId: 'ger-001',
            representanteId: 'rep-001',
            vendedorId: 'vnd-001',
            createdAt: now,
          ),
          Pedido(
            id: 'ped-002',
            tenantId: tenantId,
            origemPedido: OrderOrigin.sync,
            statusFila: OrderStatus.sent,
            clienteReferencia: ClienteReference(
              id: 'cli-002',
              type: CustomerReferenceType.official,
              documentoSnapshot: '98.765.432/0001-10',
              nomeSnapshot: 'Casa do Motor',
            ),
            ownerId: 'owner-001',
            gerenteId: 'ger-001',
            representanteId: 'rep-002',
            vendedorId: 'vnd-002',
            createdAt: now,
          ),
        ],
      ),
    );
  }

  final InMemoryClienteRepository clientes;
  final InMemoryClientePreCadastroRepository preCadastros;
  final InMemoryProdutoRepository produtos;
  final InMemoryPedidoRepository pedidos;
}