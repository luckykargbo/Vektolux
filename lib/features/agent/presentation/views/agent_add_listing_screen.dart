// lib/features/agent/presentation/views/agent_add_listing_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent "Add Listing" flow (7 steps).
//   1 Basic information · 2 Property details · 3 Photos · 4 Price & terms ·
//   5 Public location · 6 Amenities · 7 Review & submit
//
// Uses the existing realEstate:createPropertyListing mutation (the server enforces role
// approval + an active subscription) and the existing photo upload service. After submitting,
// the listing is re-read from the server and its REAL status is shown — a submission is never
// presented as "verified" or "approved".
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sl_location_picker.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
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

class _Photo {
  final String id;
  final Uint8List bytes;
  String? storageId;
  bool uploading = true;
  String? error;
  _Photo(this.id, this.bytes);
}

class AgentAddListingScreen extends StatefulWidget {
  const AgentAddListingScreen({super.key});

  @override
  State<AgentAddListingScreen> createState() => _AgentAddListingScreenState();
}

class _AgentAddListingScreenState extends State<AgentAddListingScreen> {
  static const _steps = [
    'Basic information',
    'Property details',
    'Photos',
    'Price & terms',
    'Public location',
    'Amenities & features',
    'Review & submit',
  ];

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
  String? _district;
  String? _town;
  final Set<String> _amenities = {};
  final List<_Photo> _photos = [];
  bool _publishNow = true;

  bool _submitting = false;
  String? _submitError;

  // Result (after the server accepted the listing)
  String? _createdId;
  AgentListing? _created;
  String? _statusReadError;

  @override
  void dispose() {
    for (final c in [_title, _description, _beds, _baths, _area, _price, _hourly, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Validation ─────────────────────────────────────────────────────

  int? _optInt(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
  double? _optDouble(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  String? _validate(int step) {
    switch (step) {
      case 0:
        if (_title.text.trim().length < 5) return 'Enter a title of at least 5 characters.';
        if (_description.text.trim().length < 20) return 'Describe the property in at least 20 characters.';
        return null;
      case 1:
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
      case 2:
        if (_photos.any((p) => p.uploading)) return 'Wait for the photos to finish uploading.';
        return null;
      case 3:
        final price = double.tryParse(_price.text.trim());
        if (price == null || price <= 0) return 'Enter a valid price.';
        if (_category == 'hourly_guesthouse') {
          final rate = double.tryParse(_hourly.text.trim());
          if (rate == null || rate <= 0) return 'Enter the hourly rate.';
        }
        return null;
      case 4:
        if (_district == null) return 'Choose the district (shown publicly).';
        if (_address.text.trim().length < 3) return 'Enter the street address (kept private).';
        return null;
      default:
        return null;
    }
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

  // ─── Photos (existing upload service) ───────────────────────────────

  Future<void> _addPhotos() async {
    final client = AgentShellScope.of(context).convexClient;
    final option = await ImageUploadService.showImageSourceDialog(context, allowMulti: true);
    if (option == null) return;
    final List<XFile> files;
    if (option == ImageSourceOption.camera) {
      final f = await ImageUploadService.pickImageFromCamera();
      files = f == null ? const [] : [f];
    } else {
      files = await ImageUploadService.pickMultipleImages();
    }
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final photo = _Photo('p${DateTime.now().microsecondsSinceEpoch}', bytes);
      if (!mounted) return;
      setState(() => _photos.add(photo));
      _upload(photo, client, file.mimeType ?? 'image/jpeg');
    }
  }

  Future<void> _upload(_Photo photo, ConvexClientWrapper client, String contentType) async {
    setState(() {
      photo.uploading = true;
      photo.error = null;
    });
    try {
      final res = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: client,
        imageBytes: photo.bytes,
        contentType: contentType,
      );
      if (mounted) setState(() => photo.storageId = res.storageId);
    } catch (e) {
      if (mounted) setState(() => photo.error = 'Upload failed');
    } finally {
      if (mounted) setState(() => photo.uploading = false);
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
    final cubit = context.read<AgentWorkspaceCubit>();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final listing = NewPropertyListing(
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category,
      price: double.parse(_price.text.trim()),
      hourlyRate: _category == 'hourly_guesthouse' ? double.tryParse(_hourly.text.trim()) : null,
      privateAddress: _address.text.trim(),
      town: _town,
      district: _district,
      bedrooms: _optInt(_beds),
      bathrooms: _optInt(_baths),
      areaSqM: _optDouble(_area),
      amenities: _amenities.toList(),
      // Only photos the server actually stored are attached.
      imageStorageIds: _photos.where((p) => p.storageId != null).map((p) => p.storageId!).toList(),
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
          title: const Text('Add Listing', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).maybePop()),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 4, AgentTokens.gutter, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Step ${_step + 1} of ${_steps.length}',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray500, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_steps[_step],
                      key: const Key('agent-add-step-title'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _steps.length,
                      minHeight: 5,
                      color: AppColors.emeraldDark,
                      backgroundColor: AppColors.gray100,
                    ),
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
                          foregroundColor: AppColors.gray700,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 13),
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
                                  : Text(_publishNow ? 'Submit & publish' : 'Save unpublished'),
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
        1 => _detailsStep(),
        2 => _photosStep(),
        3 => _priceStep(),
        4 => _locationStep(),
        5 => _amenitiesStep(),
        _ => _reviewStep(status),
      };

  InputDecoration _input(String label, {String? hint, String? helper, String? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixText: prefix,
        filled: true,
        fillColor: AppColors.gray50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.emeraldDark, width: 1.5)),
      );

  List<Widget> _basicStep() => [
        const Text('Listing type', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
        const SizedBox(height: 8),
        for (final (value, label, sub, icon) in [
          ('sale', 'For Sale', 'Houses, apartments or land sold outright', Icons.sell_outlined),
          ('long_term_rent', 'For Rent', 'Long-term rental, priced per year', Icons.key_outlined),
          ('hourly_guesthouse', 'Short Stay', 'Guest house rooms by the hour or night', Icons.hotel_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _choiceTile(
              key: Key('agent-add-category-$value'),
              selected: _category == value,
              icon: icon,
              title: label,
              subtitle: sub,
              onTap: () => setState(() => _category = value),
            ),
          ),
        const SizedBox(height: 10),
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

  Widget _choiceTile({
    Key? key,
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: selected ? AppColors.emeraldSurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.emeraldDark : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppColors.emeraldDark : AppColors.gray500),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
                  ],
                ),
              ),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.emeraldDark : AppColors.gray300),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _detailsStep() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return [
      const AgentInfoNote(text: 'Leave a field empty if it does not apply (for example, land has no bedrooms).'),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextField(
                controller: _beds, keyboardType: TextInputType.number, inputFormatters: digits, decoration: _input('Bedrooms')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
                controller: _baths, keyboardType: TextInputType.number, inputFormatters: digits, decoration: _input('Bathrooms')),
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _area,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: _input('Area (m²)', hint: 'e.g. 180'),
      ),
    ];
  }

  List<Widget> _photosStep() => [
        const Text('Add clear photos of the property. The first photo is the cover.',
            style: TextStyle(fontSize: 13, color: AppColors.gray600)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in _photos) _photoTile(p),
            Material(
              color: AppColors.gray50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
              child: InkWell(
                key: const Key('agent-add-photos'),
                borderRadius: BorderRadius.circular(12),
                onTap: _addPhotos,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AppColors.emeraldDark),
                    SizedBox(height: 4),
                    Text('Add photos', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.emeraldDark)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const AgentInfoNote(
          icon: Icons.videocam_off_outlined,
          text: 'Video highlights are not supported by Vektolux listings yet, so only photos can be added.',
        ),
      ];

  Widget _photoTile(_Photo p) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(p.bytes, fit: BoxFit.cover)),
        if (p.uploading || p.error != null)
          Container(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: p.uploading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : TextButton(
                    onPressed: () => _upload(p, AgentShellScope.of(context).convexClient, 'image/jpeg'),
                    child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
          ),
        Positioned(
          right: 4,
          top: 4,
          child: InkWell(
            onTap: () => setState(() => _photos.remove(p)),
            child: const CircleAvatar(radius: 11, backgroundColor: Colors.white, child: Icon(Icons.close_rounded, size: 14)),
          ),
        ),
      ],
    );
  }

  List<Widget> _priceStep() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final (label, helper) = switch (_category) {
      'long_term_rent' => ('Rent per year (SLE)', 'Long-term rentals are shown with the yearly rent.'),
      'hourly_guesthouse' => ('Base / overnight price (SLE)', 'Also enter the hourly rate below.'),
      _ => ('Sale price (SLE)', 'The full asking price.'),
    };
    return [
      TextField(
        key: const Key('agent-add-price'),
        controller: _price,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        decoration: _input(label, helper: helper, prefix: 'SLE  '),
      ),
      if (_category == 'hourly_guesthouse') ...[
        const SizedBox(height: 14),
        TextField(
          controller: _hourly,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: _input('Hourly rate (SLE / hr)', prefix: 'SLE  '),
        ),
      ],
      const SizedBox(height: 14),
      const AgentInfoNote(
        text: 'Platform fees and any agent commission are calculated by Vektolux when a buyer pays, using the current fee rules.',
      ),
    ];
  }

  List<Widget> _locationStep() => [
        const AgentInfoNote(
          icon: Icons.shield_outlined,
          color: AppColors.emeraldDark,
          background: AppColors.emeraldSurface,
          text: 'Buyers only see the town and district. The street address stays private (you and Vektolux administrators only).',
        ),
        const SizedBox(height: 14),
        SierraLeoneLocationPicker(
          requireDistrict: true,
          initialDistrict: _district,
          initialTown: _town,
          onChanged: (district, town) => setState(() {
            _district = district;
            _town = town;
          }),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('agent-add-address'),
          controller: _address,
          maxLength: 200,
          decoration: _input('Street address (private)', hint: 'Used to arrange viewings — never published'),
        ),
      ];

  List<Widget> _amenitiesStep() => [
        const Text('Select everything the property offers.', style: TextStyle(fontSize: 13, color: AppColors.gray600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in kAgentAmenities)
              FilterChip(
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
    final uploaded = _photos.where((p) => p.storageId != null).length;
    final failed = _photos.where((p) => p.error != null).length;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.gray500))),
              Expanded(
                child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.obsidian)),
              ),
            ],
          ),
        );
    return [
      AgentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Type', preview.categoryLabel ?? _category),
            row('Title', preview.title),
            row('Price', preview.priceLabel),
            row('Details', [
              if (preview.bedrooms != null) '${preview.bedrooms} bed',
              if (preview.bathrooms != null) '${preview.bathrooms} bath',
              if (preview.areaSqM != null) '${formatCount(preview.areaSqM!.round())} m²',
            ].join(' · ').ifEmpty('Not specified')),
            row('Public location', preview.publicLocation),
            row('Photos', '$uploaded uploaded${failed > 0 ? ' · $failed failed (not attached)' : ''}'),
            row('Amenities', _amenities.isEmpty ? 'None selected' : _amenities.join(', ')),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AgentCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: SwitchListTile.adaptive(
          key: const Key('agent-add-publish-toggle'),
          contentPadding: EdgeInsets.zero,
          value: _publishNow,
          activeTrackColor: AppColors.emeraldDark,
          onChanged: (v) => setState(() => _publishNow = v),
          title: const Text('Publish now', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
          subtitle: Text(
            _publishNow ? 'Buyers can see it as soon as it is saved.' : 'Saved unpublished — only you can see it until you publish it.',
            style: const TextStyle(fontSize: 12, color: AppColors.gray500),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (!status.canPostProperty)
        AgentInfoNote(
          key: const Key('agent-add-blocked'),
          icon: Icons.lock_clock_outlined,
          color: AppColors.amberDark,
          background: AppColors.amberSurface,
          text: status.postingBlockedReason ?? 'Posting is not available right now.',
        )
      else
        const AgentInfoNote(
          text: 'Submitting does not mark the listing as verified or approved. Your posting permission is checked by Vektolux when you submit.',
        ),
      if (_submitError != null) ...[
        const SizedBox(height: 12),
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
      ListingLiveStatus.live => ('Your listing is live', 'It is published on the Vektolux marketplace now.'),
      ListingLiveStatus.unpublished => (
          'Saved, not published',
          'Only you can see it. Publish it from My Listings when you are ready.'
        ),
      null => ('Listing submitted', 'Its status could not be loaded right now. Check My Listings. (${_statusReadError ?? ''})'),
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
              if (status != null) ...[
                const SizedBox(height: 14),
                Center(child: AgentStatusPill(status: status)),
              ],
              const SizedBox(height: 14),
              const AgentInfoNote(text: 'A submitted listing is not marked as verified or approved.'),
              const SizedBox(height: 24),
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

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
