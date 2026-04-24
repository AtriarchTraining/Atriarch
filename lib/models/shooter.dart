import 'package:flutter/foundation.dart';

@immutable
class Shooter {
  final String id;
  final String displayName;
  final String? contactEmail;
  final String? contactPhone;
  final DateTime createdAt;
  final String? rangeBuddyUserId;

  const Shooter({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.contactEmail,
    this.contactPhone,
    this.rangeBuddyUserId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'display_name': displayName,
        'contact_email': contactEmail,
        'contact_phone': contactPhone,
        'created_at': createdAt.millisecondsSinceEpoch,
        'range_buddy_user_id': rangeBuddyUserId,
      };

  factory Shooter.fromMap(Map<String, Object?> m) => Shooter(
        id: m['id'] as String,
        displayName: m['display_name'] as String,
        contactEmail: m['contact_email'] as String?,
        contactPhone: m['contact_phone'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        rangeBuddyUserId: m['range_buddy_user_id'] as String?,
      );

  Shooter copyWith({
    String? displayName,
    String? contactEmail,
    String? contactPhone,
    String? rangeBuddyUserId,
  }) =>
      Shooter(
        id: id,
        displayName: displayName ?? this.displayName,
        createdAt: createdAt,
        contactEmail: contactEmail ?? this.contactEmail,
        contactPhone: contactPhone ?? this.contactPhone,
        rangeBuddyUserId: rangeBuddyUserId ?? this.rangeBuddyUserId,
      );

  @override
  bool operator ==(Object other) =>
      other is Shooter &&
      other.id == id &&
      other.displayName == displayName &&
      other.contactEmail == contactEmail &&
      other.contactPhone == contactPhone &&
      other.createdAt == createdAt &&
      other.rangeBuddyUserId == rangeBuddyUserId;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        contactEmail,
        contactPhone,
        createdAt,
        rangeBuddyUserId,
      );
}
