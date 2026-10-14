import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/features/listings/domain/vehicle_posting_options.dart';

Map<String, dynamic> status({
  bool dealerHeld = false,
  bool dealerAllowed = false,
  bool companyHeld = false,
  bool companyAllowed = false,
}) =>
    {
      'vehiclePosting': {
        'individualDealer': {'held': dealerHeld, 'allowed': dealerAllowed},
        'carCompany': {'held': companyHeld, 'allowed': companyAllowed},
        'requiresChoice': dealerHeld && companyHeld,
      },
    };

void main() {
  test('single individual dealer capability is used without asking', () {
    final o = VehiclePostingOptions.fromStatus(status(dealerHeld: true, dealerAllowed: true))!;
    expect(o.requiresChoice, isFalse);
    expect(o.wireValue(null), 'individual_dealer');
    expect(o.blockingMessage(null), isNull);
    expect(o.eligibilityText(VehiclePostingCapability.individualDealer), contains('no subscription'));
  });

  test('single car company capability is sent, and the missing subscription is explained', () {
    final o = VehiclePostingOptions.fromStatus(status(companyHeld: true, companyAllowed: false))!;
    expect(o.wireValue(null), 'car_company');
    expect(o.blockingMessage(null), contains('subscription is required'));
  });

  test('holding both requires an explicit selection and never guesses', () {
    final o = VehiclePostingOptions.fromStatus(
        status(dealerHeld: true, dealerAllowed: true, companyHeld: true, companyAllowed: false))!;
    expect(o.requiresChoice, isTrue);
    expect(o.wireValue(null), isNull);
    expect(o.blockingMessage(null), contains('Choose'));
    expect(o.wireValue(VehiclePostingCapability.individualDealer), 'individual_dealer');
    expect(o.blockingMessage(VehiclePostingCapability.individualDealer), isNull);
    // the company route is shown as blocked until the subscription is active
    expect(o.blockingMessage(VehiclePostingCapability.carCompany), contains('subscription is required'));
  });

  test('a capability that is not held is never sent, whatever is selected', () {
    final o = VehiclePostingOptions.fromStatus(status(dealerHeld: true, dealerAllowed: true))!;
    expect(o.wireValue(VehiclePostingCapability.carCompany), 'individual_dealer'); // auto-selected, not the claim
    final none = VehiclePostingOptions.fromStatus(status())!;
    expect(none.wireValue(VehiclePostingCapability.carCompany), isNull);
    expect(none.held, isEmpty);
  });

  test('unknown shapes send nothing', () {
    expect(VehiclePostingOptions.fromStatus(null), isNull);
    expect(VehiclePostingOptions.fromStatus({'role': 'client'}), isNull);
  });
}
