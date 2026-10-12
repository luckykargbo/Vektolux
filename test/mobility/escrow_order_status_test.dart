import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/features/mobility/domain/escrow_order_status.dart';

void main() {
  test('server cancellation status CANCELLED is closed and cancelled', () {
    expect(EscrowOrderStatus.isClosed('CANCELLED'), isTrue);
    expect(EscrowOrderStatus.isCancelled('cancelled'), isTrue);
    expect(EscrowOrderStatus.cancelledLabel('CANCELLED'), 'Cancelled (unpaid)');
  });

  test('legacy CANCELLED_REFUNDED and settled states stay closed', () {
    expect(EscrowOrderStatus.isClosed('CANCELLED_REFUNDED'), isTrue);
    expect(EscrowOrderStatus.isClosed('SETTLED'), isTrue);
    expect(EscrowOrderStatus.isClosed('REFUNDED'), isTrue);
    expect(EscrowOrderStatus.isCancelled('SETTLED'), isFalse);
  });

  test('live orders are not closed', () {
    for (final s in ['PENDING_PAYMENT', 'HELD_IN_ESCROW', 'DISPUTED', 'PARTIALLY_RELEASED', '', null]) {
      expect(EscrowOrderStatus.isClosed(s), isFalse, reason: '$s');
    }
  });

  test('cancelled notice does not promise a refund', () {
    expect(EscrowOrderStatus.cancelledDescription, contains('14 days'));
    expect(EscrowOrderStatus.cancelledDescription, contains('payment reference'));
    expect(EscrowOrderStatus.cancelledDescription.toLowerCase(), isNot(contains('refund')));
  });

  test('contract state reads currentState (server field) and falls back to state', () {
    expect(EscrowOrderStatus.contractState({'currentState': 'CANCELLED'}), 'CANCELLED');
    expect(EscrowOrderStatus.contractState({'state': 'FUNDS_LOCKED'}), 'FUNDS_LOCKED');
    expect(EscrowOrderStatus.contractState({}), 'PENDING_DEPOSIT');
  });
}
