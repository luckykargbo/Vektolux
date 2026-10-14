/// Which capability a vehicle is posted under (display + request building ONLY).
///
/// The server decides everything: it checks that the account really holds the capability and, for
/// `car_company`, that an approved capability and an active car_company subscription exist. A value
/// sent from here can never grant anything; a wrong one is simply refused.
enum VehiclePostingCapability {
  individualDealer('individual_dealer', 'Individual dealer / vehicle owner'),
  carCompany('car_company', 'Car company');

  const VehiclePostingCapability(this.wire, this.label);
  final String wire;
  final String label;
}

class VehiclePostingOptions {
  const VehiclePostingOptions({
    required this.individualHeld,
    required this.individualAllowed,
    required this.carCompanyHeld,
    required this.carCompanyAllowed,
  });

  final bool individualHeld;
  final bool individualAllowed;
  final bool carCompanyHeld;
  final bool carCompanyAllowed;

  /// Parses `subscriptions:getMyProfessionalStatus`.vehiclePosting. Null when the shape is unknown
  /// (the caller then sends nothing and lets the server decide).
  static VehiclePostingOptions? fromStatus(Object? status) {
    if (status is! Map) return null;
    final vp = status['vehiclePosting'];
    if (vp is! Map) return null;
    bool flag(Object? m, String k) => m is Map && m[k] == true;
    return VehiclePostingOptions(
      individualHeld: flag(vp['individualDealer'], 'held'),
      individualAllowed: flag(vp['individualDealer'], 'allowed'),
      carCompanyHeld: flag(vp['carCompany'], 'held'),
      carCompanyAllowed: flag(vp['carCompany'], 'allowed'),
    );
  }

  List<VehiclePostingCapability> get held => [
        if (individualHeld) VehiclePostingCapability.individualDealer,
        if (carCompanyHeld) VehiclePostingCapability.carCompany,
      ];

  /// Both capabilities are held: the user must choose, nothing is guessed.
  bool get requiresChoice => held.length > 1;

  /// The only held capability, used without asking (no extra friction).
  VehiclePostingCapability? get autoSelected => held.length == 1 ? held.first : null;

  bool isAllowed(VehiclePostingCapability c) =>
      c == VehiclePostingCapability.individualDealer ? individualAllowed : carCompanyAllowed;

  /// The value to send as `postingCapability`, or null to send nothing. A selection is honoured
  /// only if the account holds that capability.
  String? wireValue(VehiclePostingCapability? selected) {
    if (requiresChoice) {
      if (selected == null || !held.contains(selected)) return null;
      return selected.wire;
    }
    return autoSelected?.wire;
  }

  /// A message when the form must not be submitted yet, else null.
  String? blockingMessage(VehiclePostingCapability? selected) {
    if (requiresChoice && (selected == null || !held.contains(selected))) {
      return 'Choose whether this vehicle is posted as an individual dealer or as your car company.';
    }
    final c = requiresChoice ? selected : autoSelected;
    if (c != null && !isAllowed(c)) return eligibilityText(c);
    return null;
  }

  String eligibilityText(VehiclePostingCapability c) {
    switch (c) {
      case VehiclePostingCapability.individualDealer:
        return individualAllowed
            ? 'Free: no subscription is needed to post as an individual dealer.'
            : 'Your individual dealer approval is not active.';
      case VehiclePostingCapability.carCompany:
        if (!carCompanyHeld) return 'Your account is not an approved car company.';
        return carCompanyAllowed
            ? 'Car company subscription is active.'
            : 'A car company subscription is required. Subscribe from your account to post as a company.';
    }
  }
}
