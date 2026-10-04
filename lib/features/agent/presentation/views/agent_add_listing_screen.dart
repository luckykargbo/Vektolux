// lib/features/agent/presentation/views/agent_add_listing_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent "Add Listing" flow (5 steps).
//   1 Type & title · 2 Photos & video · 3 Details · 4 Price & location · 5 Review
//
// Uses the existing realEstate:createPropertyListing mutation (the server enforces role
// approval + an active subscription and refuses media that never reached storage). Photos and
// videos upload to the existing Convex storage with real progress; only confirmed uploads are
// attached. The PUBLIC location (town/district) and the PRIVATE verification address + contact
// phone are separate inputs. After submitting, the listing's REAL status is read back.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sl_location_picker.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import '../widgets/listing_media_editor.dart';
import 'agent_shell.dart';

/// Amenity names offered to the agent (stored as plain strings on the listing).
const List<String> kAgentAmenities = [
  'Parking',
  '24/7 Security',
  'Water supply',
  'Generator / backup power',
  'Solar power',
  'Fenced compound',
  'Furnished',
  'Air conditioning',
  'Internet',
  'Garden',
  'Balcony',
  'Swimming pool',
];

class AgentAddListingScreen extends StatefulWidget {
  /// Device picker by default; a fake in tests.
  final ListingMediaSource mediaSource;

  /// Upload transport (tests); by default each upload uses its own HTTP client.
  final http.Client? uploadClient;

  const AgentAddListingScreen({super.key, this.mediaSource = const DeviceListingMediaSource(), this.uploadClient});

  @override
  State<AgentAddListingScreen> createState() => _AgentAddListingScreenState();
}

class _AgentAddListingScreenState extends State<AgentAddListingScreen> {
  static const _steps = ['Type & title', 'Photos & video', 'Details', 'Price & location', 'Review'];
  static const _mediaStep = 1;

  int _step = 0;
  String? _stepError;

  String _category = 'sale';
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _beds = TextEditingController();
  final _baths = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();
  final _hourly = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  String? _district;
  String? _town;
  final Set<String> _amenities = {};
  ListingMediaController? _media;
  bool _publishNow = true;

  bool _submitting = false;
  String? _submitError;

  // Result (after the server accepted the listing)
  String? _createdId;
  AgentListing? _created;
  String? _statusReadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_media == null) {
      final scope = AgentShellScope.of(context);
      _media = ListingMediaController(client: scope.convexClient, httpClient: widget.uploadClient);
      if (scope.user.hasPhone) _phone.text = scope.user.phone.trim();
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _beds, _baths, _area, _price, _hourly, _address, _phone]) {
      c.dispose();
    }
    _media?.dispose();
    super.dispose();
  }

  ListingMediaController get media => _media!;

  // ─── Validation ─────────────────────────────────────────────────────

  int? _optInt(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
  double? _optDouble(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  String? _validate(int step) {
    switch (step) {
      case 0:
        if (_title.text.trim().length < 5) return 'Enter a title of at least 5 characters.';
        if (_description.text.trim().length < 20) return 'Describe the property in at least 20 characters.';
        return null;
      case _mediaStep:
        if (!media.hasPhoto) return 'Add at least one photo.';
        if (media.photos.every((p) => p.state == ListingMediaState.failed)) {
          return 'No photo uploaded yet. Tap a failed photo to retry.';
        }
        return null;
      case 2:
        for (final (c, label) in [(_beds, 'Bedrooms'), (_baths, 'Bathrooms')]) {
          if (c.text.trim().isNotEmpty) {
            final n = int.tryParse(c.text.trim());
            if (n == null || n < 0 || n > 100) return '$label must be a whole number.';
          }
        }
        if (_area.text.trim().isNotEmpty) {
          final a = double.tryParse(_area.text.trim());
          if (a == null || a <= 0) return 'Enter the area in square metres, or leave it empty.';
        }
        return null;
      case 3:
        final price = double.tryParse(_price.text.trim());
        if (price == null || price <= 0) return 'Enter a valid price.';
        if (_category == 'hourly_guesthouse') {
          final rate = double.tryParse(_hourly.text.trim());
          if (rate == null || rate <= 0) return 'Enter the hourly rate.';
        }
        if (_district == null) return 'Choose the public district.';
        if (_address.text.trim().length < 3) return 'Enter the private verification address.';
        final phone = _phone.text.replaceAll(RegExp(r'[\s\-()]'), '');
        if (phone.isNotEmpty && !RegExp(r'^\+?\d{8,15}$').hasMatch(phone)) return 'Enter a valid contact phone number.';
        return null;
      default:
        return null;
    }
  }

  /// Media must be settled before submitting: nothing still uploading, nothing failed.
  String? _validateUploads() {
    if (media.isUploading) return 'Wait for the uploads to finish.';
    if (media.failedCount > 0) return 'Retry or remove the media that failed to upload.';
    if (media.uploadedPhotoIds.isEmpty) return 'Add at least one photo.';
    return null;
  }

  void _next() {
    final err = _validate(_step);
    setState(() => _stepError = err);
    if (err == null && _step < _steps.length - 1) setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _step--;
        _stepError = null;
      });
    }
  }

  // ─── Submit ─────────────────────────────────────────────────────────

  Future<void> _submit() async {
    for (var i = 0; i < _steps.length - 1; i++) {
      final err = _validate(i);
      if (err != null) {
        setState(() {
          _step = i;
          _stepError = err;
        });
        return;
      }
    }
    final uploadErr = _validateUploads();
    if (uploadErr != null) {
      setState(() => _stepError = uploadErr);
      return;
    }
    final cubit = context.read<AgentWorkspaceCubit>();
    setState(() {
      _submitting = true;
      _submitError = null;
      _stepError = null;
    });
    final phone = _phone.text.replaceAll(RegExp(r'[\s\-()]'), '');
    final listing = NewPropertyListing(
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category,
      price: double.parse(_price.text.trim()),
      hourlyRate: _category == 'hourly_guesthouse' ? double.tryParse(_hourly.text.trim()) : null,
      privateAddress: _address.text.trim(),
      privateContactPhone: phone.isEmpty ? null : phone,
      town: _town,
      district: _district,
      bedrooms: _optInt(_beds),
      bathrooms: _optInt(_baths),
      areaSqM: _optDouble(_area),
      amenities: _amenities.toList(),
      // Only files Convex confirmed are attached, in the agent's order (first photo = cover).
      imageStorageIds: media.uploadedPhotoIds,
      videoStorageIds: media.uploadedVideoIds,
      publish: _publishNow,
    );
    try {
      final id = await cubit.api.createListing(listing);
      AgentListing? created;
      String? readError;
      try {
        final mine = await cubit.api.myListings();
        for (final l in mine) {
          if (l.id == id) created = l;
        }
        if (created == null) readError = 'The listing was not found in your listings yet.';
      } catch (e) {
        readError = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _createdId = id;
        _created = created;
        _statusReadError = readError;
      });
      cubit.loadListings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.toString();
      });
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_createdId != null) return agentTextScale(_resultView());
    final status = context.watch<AgentWorkspaceCubit>().state.status;
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: const Text('Add Property', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).maybePop()),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 2, AgentTokens.gutter, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_steps[_step],
                            key: const Key('agent-add-step-title'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                      ),
                      Text('${_step + 1}/${_steps.length}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 5,
                            decoration: BoxDecoration(
                              color: i <= _step ? AppColors.emeraldDark : AppColors.gray100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 6, AgentTokens.gutter, 24),
                children: [
                  ..._stepBody(status),
                  if (_stepError != null) ...[
                    const SizedBox(height: 12),
                    Text(_stepError!,
                        key: const Key('agent-add-error'),
                        style: const TextStyle(color: AppColors.errorDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 10, AgentTokens.gutter, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _back,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: AppColors.gray700,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(_step == 0 ? 'Cancel' : 'Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _step < _steps.length - 1
                          ? ElevatedButton(
                              key: const Key('agent-add-next'),
                              onPressed: _next,
                              style: agentPrimaryButtonStyle(),
                              child: const Text('Next'),
                            )
                          : ElevatedButton(
                              key: const Key('agent-add-submit'),
                              onPressed: _submitting || !status.canPostProperty ? null : _submit,
                              style: agentPrimaryButtonStyle(),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(_publishNow ? 'Submit & publish' : 'Save unpublished'),
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepBody(ProfessionalStatus status) => switch (_step) {
        0 => _basicStep(),
        _mediaStep => [ListingMediaEditor(controller: media, source: widget.mediaSource)],
        2 => _detailsStep(),
        3 => _priceLocationStep(),
        _ => _reviewStep(status),
      };

  InputDecoration _input(String label, {String? hint, String? prefix, IconData? icon}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: AppColors.gray400),
        filled: true,
        fillColor: AppColors.gray50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.emeraldDark, width: 1.5)),
      );

  List<Widget> _basicStep() => [
        Row(
          children: [
            for (final (i, (value, label, icon)) in const [
              ('sale', 'For Sale', Icons.sell_outlined),
              ('long_term_rent', 'For Rent', Icons.key_outlined),
              ('hourly_guesthouse', 'Short Stay', Icons.hotel_outlined),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _TypeCard(
                  key: Key('agent-add-category-$value'),
                  selected: _category == value,
                  icon: icon,
                  label: label,
                  onTap: () => setState(() => _category = value),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('agent-add-title'),
          controller: _title,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: _input('Title', hint: 'e.g. Modern 3 bedroom house'),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('agent-add-description'),
          controller: _description,
          maxLines: 5,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: _input('Description', hint: 'Rooms, condition, access road, nearby services…'),
        ),
      ];

  List<Widget> _detailsStep() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('agent-add-beds'),
              controller: _beds,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: _input('Beds', icon: Icons.bed_outlined),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('agent-add-baths'),
              controller: _baths,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: _input('Baths', icon: Icons.bathtub_outlined),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('agent-add-area'),
        controller: _area,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: _input('Size (m²)', hint: 'Optional', icon: Icons.square_foot_rounded),
      ),
      const SizedBox(height: 18),
      const Text('Features', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in kAgentAmenities)
            FilterChip(
              key: Key('agent-add-amenity-$a'),
              label: Text(a),
              selected: _amenities.contains(a),
              showCheckmark: true,
              selectedColor: AppColors.emeraldSurface,
              checkmarkColor: AppColors.emeraldDark,
              backgroundColor: Colors.white,
              side: BorderSide(color: _amenities.contains(a) ? AppColors.emeraldDark : AppColors.border),
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _amenities.contains(a) ? AppColors.emeraldDark : AppColors.obsidian,
              ),
              onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
            ),
        ],
      ),
    ];
  }

  List<Widget> _priceLocationStep() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final label = switch (_category) {
      'long_term_rent' => 'Rent per year',
      'hourly_guesthouse' => 'Overnight price',
      _ => 'Sale price',
    };
    return [
      TextField(
        key: const Key('agent-add-price'),
        controller: _price,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        decoration: _input(label, prefix: 'SLE  '),
      ),
      if (_category == 'hourly_guesthouse') ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('agent-add-hourly'),
          controller: _hourly,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: _input('Hourly rate', prefix: 'SLE  '),
        ),
      ],
      const SizedBox(height: 16),
      _PrivacyCard(
        key: const Key('agent-add-public-location'),
        icon: Icons.public_rounded,
        title: 'Public location',
        tag: 'Buyers see this',
        color: AppColors.emeraldDark,
        background: AppColors.emeraldSurface,
        child: SierraLeoneLocationPicker(
          requireDistrict: true,
          initialDistrict: _district,
          initialTown: _town,
          onChanged: (district, town) => setState(() {
            _district = district;
            _town = town;
          }),
        ),
      ),
      const SizedBox(height: 12),
      _PrivacyCard(
        key: const Key('agent-add-private-details'),
        icon: Icons.lock_outline_rounded,
        title: 'Private details',
        tag: 'Never published',
        color: AppColors.obsidian,
        background: AppColors.gray100,
        child: Column(
          children: [
            TextField(
              key: const Key('agent-add-address'),
              controller: _address,
              maxLength: 200,
              decoration: _input('Verification address', hint: 'Street and house number', icon: Icons.home_outlined),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('agent-add-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]'))],
              decoration: _input('Contact phone', hint: 'Optional', icon: Icons.call_outlined),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _reviewStep(ProfessionalStatus status) {
    final preview = AgentListing(
      id: 'preview',
      title: _title.text.trim(),
      category: _category,
      price: double.tryParse(_price.text.trim()) ?? 0,
      hourlyRate: double.tryParse(_hourly.text.trim()),
      town: _town,
      district: _district,
      bedrooms: _optInt(_beds),
      bathrooms: _optInt(_baths),
      areaSqM: _optDouble(_area),
    );
    final cover = media.coverThumbnail;
    return [
      ListenableBuilder(
        listenable: media,
        builder: (context, _) => AgentCard(
          key: const Key('agent-add-preview'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover != null
                        ? Image.memory(cover, fit: BoxFit.cover, cacheWidth: 900)
                        : Container(
                            color: AppColors.gray100,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined, color: AppColors.gray400, size: 36),
                          ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          _MediaCount(icon: Icons.photo_outlined, count: media.uploadedPhotoIds.length),
                          if (media.uploadedVideoIds.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _MediaCount(icon: Icons.videocam_rounded, count: media.uploadedVideoIds.length),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview.categoryLabel != null) AgentCategoryTag(listing: preview),
                    const SizedBox(height: 6),
                    Text(preview.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                    const SizedBox(height: 4),
                    Text(preview.priceLabel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
                    const SizedBox(height: 6),
                    AgentLocationLine(text: preview.publicLocation),
                    if (AgentListingSpecs.hasAny(preview)) ...[
                      const SizedBox(height: 8),
                      AgentListingSpecs(listing: preview),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      AgentCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            _ReviewLine(icon: Icons.lock_outline_rounded, label: 'Private address', value: _address.text.trim()),
            if (_phone.text.trim().isNotEmpty)
              _ReviewLine(icon: Icons.call_outlined, label: 'Private phone', value: _phone.text.trim()),
            _ReviewLine(
              icon: Icons.checklist_rounded,
              label: 'Features',
              value: _amenities.isEmpty ? 'None' : '${_amenities.length} selected',
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      AgentCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: SwitchListTile.adaptive(
          key: const Key('agent-add-publish-toggle'),
          contentPadding: EdgeInsets.zero,
          value: _publishNow,
          activeTrackColor: AppColors.emeraldDark,
          onChanged: (v) => setState(() => _publishNow = v),
          title: const Text('Publish now', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
          subtitle: Text(_publishNow ? 'Visible to buyers once saved' : 'Only you can see it',
              style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
        ),
      ),
      if (!status.canPostProperty) ...[
        const SizedBox(height: 10),
        AgentInfoNote(
          key: const Key('agent-add-blocked'),
          icon: Icons.lock_clock_outlined,
          color: AppColors.amberDark,
          background: AppColors.amberSurface,
          text: status.postingBlockedReason ?? 'Posting is not available right now.',
        ),
      ],
      if (_submitError != null) ...[
        const SizedBox(height: 10),
        AgentInfoNote(
          key: const Key('agent-add-submit-error'),
          icon: Icons.error_outline_rounded,
          color: AppColors.errorDark,
          background: AppColors.errorLight,
          text: _submitError!,
        ),
      ],
    ];
  }

  Widget _resultView() {
    final created = _created;
    final status = created?.liveStatus;
    final (title, message) = switch (status) {
      ListingLiveStatus.live => ('Your listing is live', 'Buyers can find it on Vektolux now.'),
      ListingLiveStatus.unpublished => ('Saved, not published', 'Publish it from My Listings when ready.'),
      null => ('Listing submitted', 'Its status could not be loaded. Check My Listings.'),
      _ => ('Listing saved', 'Current status: ${status.label}.'),
    };
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.emeraldSurface,
                  child: Icon(Icons.check_rounded, color: AppColors.emeraldDark, size: 36),
                ),
              ),
              const SizedBox(height: 18),
              Text(title,
                  key: const Key('agent-add-result-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppColors.gray600, height: 1.4)),
              if (status == null && _statusReadError != null) ...[
                const SizedBox(height: 4),
                Text(_statusReadError!,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.gray400)),
              ],
              if (status != null) ...[
                const SizedBox(height: 14),
                Center(child: AgentStatusPill(status: status)),
              ],
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: agentPrimaryButtonStyle(),
                child: const Text('Back to My Listings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TypeCard({super.key, required this.selected, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.emeraldSurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.emeraldDark : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.emeraldDark : AppColors.gray500, size: 24),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.emeraldDark : AppColors.obsidian,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String tag;
  final Color color;
  final Color background;
  final Widget child;

  const _PrivacyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.tag,
    required this.color,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AgentCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
                child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MediaCount extends StatelessWidget {
  final IconData icon;
  final int count;
  const _MediaCount({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReviewLine({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.gray500),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.gray500)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
          ),
        ],
      ),
    );
  }
}
