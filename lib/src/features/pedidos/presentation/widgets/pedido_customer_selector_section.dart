import 'package:flutter/material.dart';

import '../../../../core/models/cliente.dart';
import '../../../../core/models/domain_types.dart';

/// Renders the customer picker (autocomplete) and sale-purpose dropdown used
/// by the pedido item editor. Purely presentational: all state is owned by
/// the parent, which supplies the current values and callbacks.
class PedidoCustomerSelectorSection extends StatelessWidget {
  const PedidoCustomerSelectorSection({
    super.key,
    required this.compact,
    required this.customerController,
    required this.customerFocusNode,
    required this.clientes,
    required this.loadingClientes,
    required this.customerReadDenied,
    required this.customerInputError,
    required this.saving,
    required this.selectedSalePurpose,
    required this.selectedClienteId,
    required this.formatClienteLabel,
    required this.normalizeSearch,
    required this.findClienteById,
    required this.findClienteByTypedText,
    required this.inputDecoration,
    required this.onSelectCustomerById,
    required this.onCustomerInputErrorChanged,
    required this.onClearSelectedClienteReference,
    required this.onSalePurposeChanged,
  });

  final bool compact;
  final TextEditingController customerController;
  final FocusNode customerFocusNode;
  final List<Cliente> clientes;
  final bool loadingClientes;
  final bool customerReadDenied;
  final String? customerInputError;
  final bool saving;
  final SalePurpose selectedSalePurpose;
  final String selectedClienteId;
  final String Function(Cliente cliente) formatClienteLabel;
  final String Function(String value) normalizeSearch;
  final Cliente? Function(String customerId) findClienteById;
  final Cliente? Function(String raw) findClienteByTypedText;
  final InputDecoration Function({required String label}) inputDecoration;
  final Future<void> Function(String customerId) onSelectCustomerById;
  final void Function(String? message) onCustomerInputErrorChanged;
  final VoidCallback onClearSelectedClienteReference;
  final Future<void> Function(SalePurpose value) onSalePurposeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 8,
        compact ? 3 : 4,
        compact ? 6 : 8,
        compact ? 4 : 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RawAutocomplete<Cliente>(
            textEditingController: customerController,
            focusNode: customerFocusNode,
            displayStringForOption: formatClienteLabel,
            optionsBuilder: (textEditingValue) {
              final query = normalizeSearch(textEditingValue.text);
              if (query.isEmpty) {
                return clientes.take(25);
              }

              final filtered = clientes.where((cliente) {
                final label = normalizeSearch(formatClienteLabel(cliente));
                final nome = normalizeSearch(cliente.nome);
                final documento = normalizeSearch(cliente.documento);
                return label.contains(query) ||
                    nome.contains(query) ||
                    documento.contains(query);
              });
              return filtered.take(25);
            },
            onSelected: (cliente) {
              onSelectCustomerById(cliente.id);
              // Close the keyboard automatically after picking a customer
              // from the suggestions list instead of leaving it open.
              customerFocusNode.unfocus();
            },
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    enabled: !saving && !loadingClientes && !customerReadDenied,
                    decoration: inputDecoration(label: 'Cliente').copyWith(
                      hintText: 'Digite para buscar e selecione da lista',
                      helperText: customerReadDenied
                          ? 'Sem permissão para listar clientes neste perfil.'
                          : null,
                      errorText: customerInputError,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: compact ? 8 : 12,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Limpar cliente',
                        onPressed: saving || loadingClientes || customerReadDenied
                            ? null
                            : () {
                                onSelectCustomerById('');
                              },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onSubmitted: (_) {
                      final typed = textEditingController.text.trim();
                      if (typed.isEmpty) {
                        onSelectCustomerById('');
                        return;
                      }
                      final matched = findClienteByTypedText(typed);
                      if (matched != null) {
                        onSelectCustomerById(matched.id);
                        return;
                      }
                      onCustomerInputErrorChanged(
                        'Selecione um cliente existente da lista.',
                      );
                    },
                    onChanged: (value) {
                      if (customerInputError != null) {
                        onCustomerInputErrorChanged(null);
                      }

                      final selected = findClienteById(selectedClienteId);
                      if (selected == null) {
                        return;
                      }

                      final selectedLabel = normalizeSearch(
                        formatClienteLabel(selected),
                      );
                      if (normalizeSearch(value) != selectedLabel) {
                        onClearSelectedClienteReference();
                      }
                    },
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              final optionList = options.toList(growable: false);
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 680,
                      maxHeight: 240,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: optionList.length,
                      itemBuilder: (context, index) {
                        final cliente = optionList[index];
                        return ListTile(
                          dense: true,
                          title: Text(cliente.nome),
                          subtitle: Text(
                            [
                              if (cliente.documento.trim().isNotEmpty)
                                cliente.documento.trim(),
                              if (cliente.estado.trim().isNotEmpty)
                                cliente.estado.trim().toUpperCase(),
                            ].join(' · '),
                          ),
                          onTap: () => onSelected(cliente),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          if (loadingClientes) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<SalePurpose>(
            initialValue: selectedSalePurpose,
            isExpanded: true,
            decoration: inputDecoration(label: 'Finalidade da venda').copyWith(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: compact ? 8 : 12,
              ),
            ),
            items: SalePurpose.values
                .map(
                  (item) => DropdownMenuItem<SalePurpose>(
                    value: item,
                    child: Text(item.label),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) async {
                    if (value == null) {
                      return;
                    }
                    await onSalePurposeChanged(value);
                  },
          ),
        ],
      ),
    );
  }
}
