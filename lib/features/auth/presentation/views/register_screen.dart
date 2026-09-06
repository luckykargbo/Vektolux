// lib/features/auth/presentation/views/register_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Multi-Role Registration Wizard
// Stepped registration with animated role cards and business profile fields.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../mobility/presentation/views/mobility_home_screen.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentStep = 0;

  // Form field controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _tinController = TextEditingController();

  UserRole? _selectedRole;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _countryCode = '+232'; // Sierra Leone default

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    _tinController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onSubmit() {
    if (_selectedRole == null) return;

    final rawPhone = _phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '');
    final fullPhone = '$_countryCode$rawPhone';

    context.read<AuthBloc>().add(RegisterSubmittedEvent(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: fullPhone,
      password: _passwordController.text,
      role: _selectedRole!,
      businessName: _selectedRole!.requiresBusinessInfo
          ? _businessNameController.text.trim()
          : null,
      tinNumber: _selectedRole!.requiresBusinessInfo
          ? _tinController.text.trim()
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated && state.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MobilityHomeScreen(
                currentUserId: state.user!.id,
              ),
            ),
          );
        } else if (state.status == AuthStatus.error && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Create Account'),
          leading: _currentStep > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: () => _goToStep(_currentStep - 1),
                )
              : null,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text('Sign In'),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Step Progress Indicator ─────────────────────────
            _StepProgressBar(currentStep: _currentStep),

            // ── Stepped Pages ───────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildRoleSelectionStep(),
                  _buildDetailsFormStep(),
                  _buildReviewStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 1: ROLE SELECTION
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRoleSelectionStep() {
    final roles = [
      UserRole.client,
      UserRole.agent,
      UserRole.merchant,
      UserRole.driver,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Role',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select how you primarily intend to operate on Vektolux',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.95,
              children: roles.map((role) {
                final isSelected = _selectedRole == role;
                return _RoleSelectionCard(
                  role: role,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() => _selectedRole = role);
                    context.read<AuthBloc>().add(RoleSelectedEvent(role));
                  },
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedRole != null ? () => _goToStep(1) : null,
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 2: FORM DETAILS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDetailsFormStep() {
    final requiresBusiness = _selectedRole?.requiresBusinessInfo ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account Information',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Registering as ${_selectedRole?.displayName ?? "User"}',
              style: const TextStyle(
                color: AppColors.emeraldDark,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),

            // Full Name
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'e.g. Lamin Kamara',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Full name is required';
                if (v.trim().length < 3) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'lamin@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Phone with country code selector
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _countryCode,
                      dropdownColor: const Color(0xFFF8FAFC),
                      iconEnabledColor: const Color(0xFF0F172A),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '+232',
                          child: Text('SL +232', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                        ),
                        DropdownMenuItem(
                          value: '+234',
                          child: Text('NG +234', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                        ),
                        DropdownMenuItem(
                          value: '+233',
                          child: Text('GH +233', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                        ),
                        DropdownMenuItem(
                          value: '+1',
                          child: Text('US +1', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                        ),
                        DropdownMenuItem(
                          value: '+44',
                          child: Text('UK +44', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _countryCode = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '76 123 456',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Phone is required';
                      final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                      if (digits.length < 7) return 'Enter a valid phone number';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Min. 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm Password
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              validator: (v) {
                if (v != _passwordController.text) return 'Passwords do not match';
                return null;
              },
            ),

            // Optional Business Registration / TIN field for agents and merchants
            if (requiresBusiness) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Business Verification Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Provide business credentials for expedited verification',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _businessNameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  labelText: 'Business / Company Name',
                  hintText: 'e.g. Freetown Realty Ltd',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tinController,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  labelText: 'TIN / Business Registration Number',
                  hintText: 'Optional registration code',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState?.validate() == true) {
                    _goToStep(2);
                  }
                },
                child: const Text('Review Information'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 3: REVIEW & SUBMIT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm Details',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please review your registration details before creating your account',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Summary Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SummaryRow(label: 'Role', value: _selectedRole?.displayName ?? '—', isHighlight: true),
                const Divider(height: 20),
                _SummaryRow(label: 'Name', value: _nameController.text),
                const Divider(height: 20),
                _SummaryRow(label: 'Email', value: _emailController.text),
                const Divider(height: 20),
                _SummaryRow(label: 'Phone', value: '$_countryCode ${_phoneController.text}'),
                if (_selectedRole?.requiresBusinessInfo == true) ...[
                  const Divider(height: 20),
                  _SummaryRow(
                    label: 'Business',
                    value: _businessNameController.text.isNotEmpty
                        ? _businessNameController.text
                        : 'Not provided',
                  ),
                  const Divider(height: 20),
                  _SummaryRow(
                    label: 'TIN',
                    value: _tinController.text.isNotEmpty
                        ? _tinController.text
                        : 'Not provided',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Trust / Verification Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: AppColors.emeraldDark, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'An offline-first wallet will be created for you on the Vektolux platform. Transactions are cryptographically secured.',
                    style: TextStyle(
                      color: AppColors.emeraldDark,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final isSubmitting = state.status == AuthStatus.registering;
              return SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : _onSubmit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Complete Registration'),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//                      SUPPORTING WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  const _StepProgressBar({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(3, (index) {
          final isPastOrCurrent = index <= currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isPastOrCurrent ? AppColors.emerald : AppColors.gray200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < 2) const SizedBox(width: 8),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _RoleSelectionCard extends StatelessWidget {
  final UserRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleSelectionCard({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _roleIcon => switch (role) {
        UserRole.client => Icons.person_outline,
        UserRole.agent => Icons.home_work_outlined,
        UserRole.merchant => Icons.directions_car_outlined,
        UserRole.driver => Icons.local_taxi_outlined,
        UserRole.admin => Icons.admin_panel_settings_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.emeraldSurface : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.emerald : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.emerald.withValues(alpha: 0.15)
                      : AppColors.gray100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _roleIcon,
                  color: isSelected ? AppColors.emerald : AppColors.gray500,
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                role.displayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                role.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 4),
                const Icon(Icons.check_circle, color: AppColors.emerald, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: isHighlight ? AppColors.emeraldDark : AppColors.obsidian,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
