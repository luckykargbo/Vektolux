// lib/features/agent/presentation/views/viewing_requests_entry.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Viewing requests for a Real Estate OWNER (no agent workspace).
// The same Accept / Decline screen the agent uses, with its own small workspace state. The server
// lets the listing's owner or its active authorised agent answer a request, and nobody else.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import 'agent_viewings_screen.dart';

Future<void> openViewingRequests(BuildContext context, {required ConvexClientWrapper client, required UserEntity user}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BlocProvider(
      create: (_) => AgentWorkspaceCubit(
        api: AgentApi(client: client, userId: user.id, sessionToken: user.sessionToken),
        // Only the viewing requests are used here; every action is authorised again by the server.
        status: const ProfessionalStatus(role: 'real_estate_owner', roleApproved: true),
      ),
      child: const AgentViewingsScreen(),
    ),
  ));
}
