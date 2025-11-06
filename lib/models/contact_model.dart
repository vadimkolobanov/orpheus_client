// lib/models/contact_model.dart

class Contact {
  final int? id;
  final String name;
  final String publicKey;

  Contact({this.id, required this.name, required this.publicKey});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
    };
  }
}