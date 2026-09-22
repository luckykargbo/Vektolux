// lib/features/admin/presentation/views/tabs/api_health_tab.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Module 1: API Key Health, Management & Status Monitor
// Live status cards, masked secret preview, outage incident logs,
// and key rotation controls. Zero mock data.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

class ApiHealthTab extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;

  const ApiHealthTab({
    super.key,
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
  });

  @override
  State<ApiHealthTab> createState() => _ApiHealthTabState();
}

class _ApiHealthTabState extends State<ApiHealthTab> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _configs = [];
  List<Map<String, dynamic>> _incidents = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final configRes = await widget.convexClient.query(
        'adminPortal:getApiKeysConfig',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );

      final incidentRes = await widget.convexClient.query(
        'adminPortal:getApiHealthIncidents',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );

      if (mounted) {
        if (!configRes.success) {
          throw Exception(configRes.errorMessage ?? 'Failed to load configs');
        }
        setState(() {
          _configs = (configRes.value as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
          _incidents = (incidentRes.value as List<dynamic>?)
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

  Future<void> _seedDefaultKeys() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seeding API key definitions...')),
      );
      await widget.convexClient.mutation(
        'adminPortal:seedApiKeysConfig',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );
      await _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seeding keys: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showRotationDialog(Map<String, dynamic> config) {
    final controller = TextEditingController(text: config['maskedValue'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text(
          'Rotate ${config['keyName']}',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.obsidian,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Service: ${config['displayName']}',
              style: const TextStyle(fontSize: 13, color: AppColors.obsidianMedium),
            ),
            const SizedBox(height: 6),
            Text(
              'Env Var: ${config['envVarName']}',
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                color: AppColors.obsidianSoft,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Update the masked preview (e.g. ****5678) after changing the environment variable:',
              style: TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '****1234',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () async {
              final val = controller.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.convexClient.mutation(
                  'adminPortal:rotateApiKeyMask',
                  args: {
                    'adminId': widget.adminId,
                    if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
                    'configId': config['id'],
                    'newMaskedValue': val,
                  },
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rotated ${config['keyName']} successfully.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
                await _fetchData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to rotate: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Save Preview', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                'Failed to load API keys',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.obsidian),
              ),
            ],
          ),
        ),
      );
    }

    final hasOutage = _configs.any((c) => c['healthStatus'] == 'outage');
    final hasDegraded = _configs.any((c) => c['healthStatus'] == 'degraded');

    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Status Overview Banner ──────────────────────────────────
          if (hasOutage || hasDegraded) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hasOutage ? AppColors.errorLight : AppColors.amberSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasOutage ? AppColors.error : AppColors.amber,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasOutage ? Icons.warning_rounded : Icons.info_outline,
                    color: hasOutage ? AppColors.errorDark : AppColors.amberDark,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasOutage
                            ? 'CRITICAL: Service Outage Detected'
                            : 'WARNING: Degraded Service Performance',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: hasOutage ? AppColors.errorDark : AppColors.amberDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Payment gateway errors reported. Inspect incident logs below.',
                          style: TextStyle(fontSize: 11, color: AppColors.obsidianMedium),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Header & Seed Action ────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Platform Gateways & APIs',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    '${_configs.length} services configured',
                    style: const TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
                  ),
                ],
              ),
              if (_configs.isEmpty)
                ElevatedButton.icon(
                  onPressed: _seedDefaultKeys,
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('Seed Gateways', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.obsidian),
                  onPressed: _fetchData,
                  tooltip: 'Refresh Status',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ─── API Config Cards ────────────────────────────────────────
          if (_configs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(Icons.vpn_key_off_outlined, size: 48, color: AppColors.obsidianSoft),
                    const SizedBox(height: 12),
                    const Text(
                      'No Gateway Configs Initialized',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Click "Seed Gateways" to register Orange, Afrimoney, Moneroo & SMS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _seedDefaultKeys,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
                      child: const Text('Seed Gateways Now', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._configs.map((config) => _buildApiKeyCard(config)),

          const SizedBox(height: 24),

          // ─── Incident Logs Section ───────────────────────────────────
          Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppColors.obsidian),
              const SizedBox(width: 8),
              const Text(
                'Recent Gateway Incidents',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.obsidian,
                ),
              ),
              const Spacer(),
              Text(
                '${_incidents.length} logs',
                style: const TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_incidents.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.emeraldSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.emeraldLight, width: 0.8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.emerald, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'All gateways operating normally. Zero outages logged.',
                    style: TextStyle(fontSize: 12, color: AppColors.emeraldDark, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            ..._incidents.map((incident) => _buildIncidentTile(incident)),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard(Map<String, dynamic> config) {
    final status = config['healthStatus'] as String? ?? 'operational';
    final isOperational = status == 'operational';
    final isOutage = status == 'outage';

    final Color statusColor = isOperational
        ? AppColors.emerald
        : (isOutage ? AppColors.error : AppColors.amber);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOutage ? AppColors.error : AppColors.obsidianLight.withOpacity(0.12),
          width: isOutage ? 1.5 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config['displayName'] ?? 'Gateway',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.obsidian,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  config['keyName'] ?? '',
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.obsidianMedium,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gray50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.obsidianLight.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        config['maskedValue'] ?? '****',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: config['maskedValue'] ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Masked value copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(Icons.copy, size: 12, color: AppColors.obsidianSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              config['operationalFunction'] ?? '',
              style: const TextStyle(fontSize: 11.5, color: AppColors.obsidianSoft),
            ),
            const SizedBox(height: 4),
            Text(
              'Route: ${config['usedIn'] ?? ''}',
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10.5,
                color: AppColors.obsidianMedium,
              ),
            ),
            if (config['lastErrorMessage'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, size: 14, color: AppColors.errorDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        config['lastErrorMessage'],
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.errorDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showRotationDialog(config),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Rotate Key', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(color: AppColors.obsidianLight, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentTile(Map<String, dynamic> incident) {
    final severity = incident['severity'] as String? ?? 'info';
    final isCritical = severity == 'critical';
    final color = isCritical ? AppColors.error : AppColors.amber;
    final timeStr = incident['occurredAt'] != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(incident['occurredAt'] as int))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                incident['serviceId'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 10, color: AppColors.obsidianSoft),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Endpoint: ${incident['endpoint'] ?? ''}',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AppColors.obsidianMedium),
          ),
          const SizedBox(height: 2),
          Text(
            incident['errorMessage'] ?? '',
            style: const TextStyle(fontSize: 11, color: AppColors.obsidian),
          ),
        ],
      ),
    );
  }
}
