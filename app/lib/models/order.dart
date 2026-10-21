/// An order as the server sends it (app orders, logged delivery orders, walk-ins).
class Order {
  final int id;
  final String source; // App, Logged, Walk-in
  final String sourceText; // App, Call, Text, Messenger, Walk-in for delivery
  final String type; // Refill, Package
  final int quantity;
  final double unitPrice;
  final double total;
  final int? customerId;
  final String name;
  final String phone;
  final String address;
  final String landmark;
  final double? lat;
  final double? lng;
  final double? km;
  final String notes;
  final String status; // New, Processing, Out for Delivery, Delivered, Not Delivered, Declined, Cancelled
  final String payment; // COD, Pay on delivery, Paid at station
  final String paymentText;
  final String paymentStatus; // Pending, Paid, Unpaid
  final int? riderId;
  final String? riderName;
  final String? riderRole;
  final int? batchSize;
  final String estText; // "by 9:50 AM" or "1:00 to 1:30 PM"
  final DateTime? acceptedAt;
  final String deliveredClock;
  final DateTime? createdAt;
  final String reason; // decline reason or not-delivered note
  final String createdText; // "Oct 20, 9:20 PM" (when the order was made, Philippine time)
  final String? deliveryDate; // "2026-10-22" chosen by the customer; null = as soon as possible
  final String? arrival; // while Out for Delivery: Arriving (rider near) or Arrived (rider at the address)

  const Order({
    required this.id,
    required this.source,
    required this.sourceText,
    required this.type,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.customerId,
    required this.name,
    required this.phone,
    required this.address,
    required this.landmark,
    required this.lat,
    required this.lng,
    required this.km,
    required this.notes,
    required this.status,
    required this.payment,
    required this.paymentText,
    required this.paymentStatus,
    required this.riderId,
    required this.riderName,
    required this.riderRole,
    required this.batchSize,
    required this.estText,
    required this.acceptedAt,
    required this.deliveredClock,
    required this.createdAt,
    required this.reason,
    this.createdText = '',
    this.deliveryDate,
    this.arrival,
  });

  static double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
  static DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v as String);

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: (j['id'] as num).toInt(),
        source: (j['source'] ?? 'App') as String,
        sourceText: (j['sourceText'] ?? '') as String,
        type: (j['type'] ?? 'Refill') as String,
        quantity: (j['quantity'] as num).toInt(),
        unitPrice: _d(j['unitPrice']) ?? 0,
        total: _d(j['total']) ?? 0,
        customerId: (j['customerId'] as num?)?.toInt(),
        name: (j['name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        landmark: (j['landmark'] ?? '') as String,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        km: _d(j['km']),
        notes: (j['notes'] ?? '') as String,
        status: (j['status'] ?? 'New') as String,
        payment: (j['payment'] ?? 'COD') as String,
        paymentText: (j['paymentText'] ?? '') as String,
        paymentStatus: (j['paymentStatus'] ?? 'Pending') as String,
        riderId: (j['riderId'] as num?)?.toInt(),
        riderName: j['riderName'] as String?,
        riderRole: j['riderRole'] as String?,
        batchSize: (j['batchSize'] as num?)?.toInt(),
        estText: (j['estText'] ?? '') as String,
        acceptedAt: _t(j['acceptedAt']),
        deliveredClock: (j['deliveredClock'] ?? '') as String,
        createdAt: _t(j['createdAt']),
        reason: (j['reason'] ?? '') as String,
        createdText: (j['createdText'] ?? '') as String,
        deliveryDate: j['deliveryDate'] as String?,
        arrival: j['arrival'] as String?,
      );

  /// The status as people read it: Out for Delivery changes by itself to Arriving and then Arrived
  /// (from the rider's place on the map) until the rider marks it Delivered.
  String get shownStatus => switch (status) {
        'Out for Delivery' when arrival == 'Arrived' => 'Arrived',
        'Out for Delivery' when arrival == 'Arriving' => 'Arriving',
        'Out for Delivery' => 'Out for delivery',
        'Not Delivered' => 'Not delivered',
        _ => status,
      };

  /// "Deliver on Thu, Oct 22" or "As soon as possible".
  String get deliveryDateText {
    final d = deliveryDate == null ? null : DateTime.tryParse(deliveryDate!);
    if (d == null) return 'As soon as possible';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Deliver on ${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  /// "3 gallons · Refill"
  String get summary => '$quantity ${quantity == 1 ? 'gallon' : 'gallons'} · $type';

  /// Rider as the owner sees it: "Juan" or "Owner".
  String get riderShort => riderRole == 'Owner' ? 'Owner' : (riderName ?? '').split(' ').first;

  /// Key of the customer for Unpaid Accounts and the Customer Profile (account, phone, or name).
  String get customerKey => customerId != null ? 'u$customerId' : (phone.isNotEmpty ? 'p$phone' : 'n$name');

  bool get active => status == 'New' || status == 'Processing' || status == 'Out for Delivery';
}

/// One step of the Status Timeline (who did it and when).
class TimelineStep {
  final String status;
  final String note;
  final DateTime? at;
  final String by;
  const TimelineStep(this.status, this.note, this.at, this.by);

  factory TimelineStep.fromJson(Map<String, dynamic> j) =>
      TimelineStep((j['status'] ?? '') as String, (j['note'] ?? '') as String, DateTime.tryParse((j['at'] ?? '') as String), (j['by'] ?? '') as String);
}

/// A delivery address: pinned on the map or typed (Quezon City). Saved addresses also have an id and a name.
class Address {
  final int? id;
  final String name;
  final String mode; // pin, typed
  final String house;
  final String blockLot;
  final String street;
  final String barangay;
  final String landmark;
  final double? lat;
  final double? lng;
  final String text;

  const Address({
    this.id,
    this.name = '',
    required this.mode,
    this.house = '',
    this.blockLot = '',
    this.street = '',
    this.barangay = '',
    this.landmark = '',
    this.lat,
    this.lng,
    this.text = '',
  });

  bool get pinned => mode == 'pin';

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: (j['id'] as num?)?.toInt(),
        name: (j['name'] ?? '') as String,
        mode: (j['mode'] ?? 'typed') as String,
        house: (j['house'] ?? '') as String,
        blockLot: (j['blockLot'] ?? '') as String,
        street: (j['street'] ?? '') as String,
        barangay: (j['barangay'] ?? '') as String,
        landmark: (j['landmark'] ?? '') as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        text: (j['text'] ?? '') as String,
      );

  /// What the server needs to save or use it.
  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        'mode': mode,
        'house': house,
        'blockLot': blockLot,
        'street': street,
        'barangay': barangay,
        'landmark': landmark,
        'lat': lat,
        'lng': lng,
      };

  /// The one line shown on the form, the same way the server writes it.
  static String line({required bool pinned, String house = '', String blockLot = '', String street = '', String barangay = ''}) {
    final first = [house, street].where((s) => s.trim().isNotEmpty).join(' ');
    final parts = [first, blockLot, barangay].where((s) => s.trim().isNotEmpty).toList();
    if (pinned && house.trim().isEmpty) return 'Pinned: near ${parts.isEmpty ? 'the map pin' : parts.join(', ')}';
    return parts.join(', ');
  }
}
