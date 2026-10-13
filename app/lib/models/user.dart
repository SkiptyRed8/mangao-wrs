/// The four roles of the system (Chapter 4.4).
enum Role { owner, staff, rider, customer }

Role roleFrom(String? s) => switch (s) {
      'Owner' => Role.owner,
      'Staff' => Role.staff,
      'Rider' => Role.rider,
      _ => Role.customer,
    };

String roleName(Role r) => switch (r) {
      Role.owner => 'Owner',
      Role.staff => 'Staff',
      Role.rider => 'Rider',
      Role.customer => 'Customer',
    };

/// A logged-in account (users table).
class AppUser {
  final int id;
  final String name;
  final String phone;
  final String email;
  final Role role;

  const AppUser({required this.id, required this.name, required this.phone, required this.email, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        role: roleFrom(j['role'] as String?),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'email': email, 'role': roleName(role)};
}
