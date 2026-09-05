// lib/features/real_estate/real_estate.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Feature Module Exports
// ═══════════════════════════════════════════════════════════════════════

// Domain
export 'domain/entities/property_listing_entity.dart';
export 'domain/entities/booking_slot_entity.dart';
export 'domain/repositories/real_estate_repository.dart';

// Data
export 'data/models/property_listing_model.dart';
export 'data/repositories/real_estate_repository_impl.dart';

// Presentation
export 'presentation/bloc/real_estate_detail_bloc.dart';
export 'presentation/bloc/real_estate_detail_event.dart';
export 'presentation/bloc/real_estate_detail_state.dart';
export 'presentation/views/real_estate_listing_detail_screen.dart';
export 'presentation/widgets/hero_image_carousel.dart';
export 'presentation/widgets/sticky_header.dart';
export 'presentation/widgets/site_visit_booking_modal.dart';
export 'presentation/widgets/hourly_booking_panel.dart';
export 'presentation/widgets/payment_webview_dialog.dart';
