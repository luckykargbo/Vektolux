// lib/features/admin/presentation/views/tabs/terminals_tab.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Module 2: Agent & Merchant Code Configuration
// Merchant terminal routing, clearing account management, ledger mapping,
// and real-time status toggling. Zero mock data.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

class TerminalsTab extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;

  const TerminalsTab({
    super.key,
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
  });

  @override
  State<TerminalsTab> createState() => _TerminalsTabState();
}

class _TerminalsTabState extends State<TerminalsTab> {
  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _terminals = [];

  @override
  void initState() {
    super.initState();
    _fetchTerminals();
  }

  Future<void> _fetchTerminals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.convexClient.query(
        'adminPortal:getMerchantTerminals',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          if (_statusFilter != 'all') 'statusFilter': _statusFilter,
        },
      );

      if (mounted) {
        setState(() {
          _terminals = (res.value as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showTerminalDialog({Map<String, dynamic>? existing}) {
    final isEditing = existing != null;
    final terminalCodeController =
        TextEditingController(text: existing?['terminalCode'] ?? '');
    final merchantIdController =
        TextEditingController(text: existing?['merchantId'] ?? '');
    final nameController =
        TextEditingController(text: existing?['displayName'] ?? '');
    final clearingController =
        TextEditingController(text: existing?['clearingAccount'] ?? '');
    final notesController =
        TextEditingController(text: existing?['notes'] ?? '');

    String carrier = existing?['carrierProvider'] ?? 'orange_money';
    String ledger = existing?['ledgerAccountType'] ?? 'MERCHANT_ESCROW';
    String status = existing?['status'] ?? 'active';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Edit Terminal' : 'New Merchant Terminal',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.obsidian,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Terminal Display Name',
                    hintText: 'e.g. Freetown Central HQ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: terminalCodeController,
                        enabled: !isEditing, // Immutable code on edit
                        decoration: const InputDecoration(
                          labelText: 'Terminal Code',
                          hintText: 'e.g. 001',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: merchantIdController,
                        decoration: const InputDecoration(
                          labelText: 'Merchant ID',
                          hintText: 'e.g. MER-SL-900',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: carrier,
                  decoration: const InputDecoration(
                    labelText: 'Telecom / Carrier Provider',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'orange_money',
                      child: Text('Orange Money Sierra Leone'),
                    ),
                    DropdownMenuItem(
                      value: 'africell',
                      child: Text('Africell Afrimoney'),
                    ),
                    DropdownMenuItem(
                      value: 'qmoney',
                      child: Text('QMoney Sierra Leone'),
                    ),
                    DropdownMenuItem(
                      value: 'moneroo',
                      child: Text('Moneroo Multi-Channel'),
                    ),
                  ],
                  onChanged: (v) => setSheetState(() => carrier = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clearingController,
                  decoration: const InputDecoration(
                    labelText: 'Clearing / Settlement Account',
                    hintText: 'e.g. +23276123456 or Bank Acc #',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ledger,
                  decoration: const InputDecoration(
                    labelText: 'Ledger Routing Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'MERCHANT_ESCROW',
                      child: Text('Merchant Escrow Split'),
                    ),
                    DropdownMenuItem(
                      value: 'AGENT_FLOAT',
                      child: Text('Agent Float Clearing'),
                    ),
                    DropdownMenuItem(
                      value: 'PLATFORM_REVENUE',
                      child: Text('Platform Revenue Collector'),
                    ),
                  ],
                  onChanged: (v) => setSheetState(() => ledger = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(
                    labelText: 'Initial Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'suspended', child: Text('Suspended')),
                    DropdownMenuItem(
                        value: 'maintenance', child: Text('Maintenance')),
                  ],
                  onChanged: (v) => setSheetState(() => status = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Operational Notes',
                    hintText: 'Location or assigned agent details',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      final code = terminalCodeController.text.trim();
                      final mId = merchantIdController.text.trim();
                      final dName = nameController.text.trim();
                      if (code.isEmpty || mId.isEmpty || dName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please complete required fields.'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      try {
                        await widget.convexClient.mutation(
                          'adminPortal:upsertMerchantTerminal',
                          args: {
                            'adminId': widget.adminId,
                            if (widget.sessionToken != null)
                              'sessionToken': widget.sessionToken,
                            if (isEditing) 'terminalId': existing['id'],
                            'terminalCode': code,
                            'merchantId': mId,
                            'displayName': dName,
                            'carrierProvider': carrier,
                            if (clearingController.text.trim().isNotEmpty)
                              'clearingAccount': clearingController.text.trim(),
                            'ledgerAccountType': ledger,
                            'status': status,
                            if (notesController.text.trim().isNotEmpty)
                              'notes': notesController.text.trim(),
                          },
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isEditing
                                  ? 'Terminal updated.'
                                  : 'Terminal created.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                        await _fetchTerminals();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    child: Text(
                      isEditing ? 'Update Terminal' : 'Register Terminal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStatus(Map<String, dynamic> terminal) async {
    final current = terminal['status'] as String? ?? 'active';
    final nextStatus = current == 'active' ? 'suspended' : 'active';

    try {
      await widget.convexClient.mutation(
        'adminPortal:toggleTerminalStatus',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          'terminalId': terminal['id'],
          'status': nextStatus,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Terminal ${terminal['terminalCode']} set to ${nextStatus.toUpperCase()}.'),
            backgroundColor:
                nextStatus == 'active' ? AppColors.success : AppColors.amberDark,
          ),
        );
      }
      await _fetchTerminals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status toggle failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteTerminal(Map<String, dynamic> terminal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Terminal?'),
        content: Text(
            'Are you sure you want to delete terminal ${terminal['terminalCode']} (${terminal['displayName']})? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.convexClient.mutation(
        'adminPortal:deleteMerchantTerminal',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          'terminalId': terminal['id'],
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Terminal ${terminal['terminalCode']} deleted successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _fetchTerminals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Filter Bar & Action ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('active', 'Active'),
                      const SizedBox(width: 8),
                      _buildFilterChip('suspended', 'Suspended'),
                      const SizedBox(width: 8),
                      _buildFilterChip('maintenance', 'Maintenance'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showTerminalDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // ─── Content ─────────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.emerald))
              : _errorMessage != null
                  ? Center(child: Text('Error: $_errorMessage'))
                  : _terminals.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.point_of_sale_outlined,
                                  size: 48, color: AppColors.obsidianSoft),
                              const SizedBox(height: 12),
                              const Text(
                                'No Merchant Terminals Found',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Configure carrier codes and clearing accounts for agents.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.obsidianSoft),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _showTerminalDialog(),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.emerald),
                                child: const Text('Register First Terminal',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.emerald,
                          onRefresh: _fetchTerminals,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            itemCount: _terminals.length,
                            itemBuilder: (ctx, index) =>
                                _buildTerminalCard(_terminals[index]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _statusFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _statusFilter = filterKey);
          _fetchTerminals();
        }
      },
      selectedColor: AppColors.obsidian,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : AppColors.obsidian,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
      backgroundColor: AppColors.gray50,
    );
  }

  Widget _buildTerminalCard(Map<String, dynamic> t) {
    final status = t['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final isSuspended = status == 'suspended';
    final Color badgeColor = isActive
        ? AppColors.emerald
        : (isSuspended ? AppColors.error : AppColors.amber);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppColors.obsidianLight.withOpacity(0.12),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['displayName'] ?? 'Terminal',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.obsidian,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Provider: ${(t['carrierProvider'] as String? ?? '').replaceAll('_', ' ').toUpperCase()}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.obsidianSoft),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TERMINAL CODE',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidianSoft),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            t['terminalCode'] ?? '',
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.obsidian,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text: t['terminalCode'] ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Terminal code copied'),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                            child: const Icon(Icons.copy,
                                size: 12, color: AppColors.obsidianSoft),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MERCHANT ID',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidianSoft),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t['merchantId'] ?? '',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.obsidianMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LEDGER ROUTE',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidianSoft),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t['ledgerAccountType'] ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                ),
                if (t['clearingAccount'] != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CLEARING ACCOUNT',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.obsidianSoft),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t['clearingAccount'],
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'Courier',
                            color: AppColors.obsidianMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (t['notes'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Note: ${t['notes']}',
                style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.obsidianSoft),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _toggleStatus(t),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isActive ? AppColors.errorDark : AppColors.emeraldDark,
                    side: BorderSide(
                        color: isActive ? AppColors.error : AppColors.emerald,
                        width: 0.8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isActive ? 'Suspend' : 'Activate',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showTerminalDialog(existing: t),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(
                        color: AppColors.obsidianLight, width: 0.8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Edit', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.error),
                  onPressed: () => _deleteTerminal(t),
                  tooltip: 'Delete Terminal',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
