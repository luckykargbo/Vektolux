/// Display-side interpretation of the server's escrow order / contract states.
///
/// The server cancels unpaid orders with `CANCELLED` (see convex/escrowExpiry.ts).
/// `CANCELLED_REFUNDED` is a legacy label that the server never writes, kept so
/// any old cached value still closes the card.
class EscrowOrderStatus {
  EscrowOrderStatus._();

  static const _cancelled = {'CANCELLED', 'CANCELLED_REFUNDED'};
  static const _closed = {'SETTLED', 'REFUNDED', 'FULLY_SETTLED', 'CANCELLED', 'CANCELLED_REFUNDED'};

  /// Real-estate contract documents carry `currentState`; older payload shapes used `state`.
  static String contractState(Map<dynamic, dynamic> contract) =>
      (contract['currentState'] ?? contract['state'] ?? 'PENDING_DEPOSIT').toString();

  static String _norm(String? s) => (s ?? '').toUpperCase();

  /// True when the order/contract is finished and belongs in the "Settled/closed" tab.
  static bool isClosed(String? status) => _closed.contains(_norm(status));

  /// True when the order was cancelled (not paid out).
  static bool isCancelled(String? status) => _cancelled.contains(_norm(status));

  static String cancelledLabel(String? status) =>
      _norm(status) == 'CANCELLED_REFUNDED' ? 'Cancelled & Refunded' : 'Cancelled (unpaid)';

  static const cancelledTitle = 'Order Cancelled';
  static const cancelledDescription =
      'This order was cancelled because no payment was received within 14 days. '
      'If you already sent money for it, please contact Vektolux support with your payment reference.';
}
