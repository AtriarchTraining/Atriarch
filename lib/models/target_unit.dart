class TargetUnit {
  final int id;
  bool isOnline;
  int? groupId;
  bool isNoShoot;

  TargetUnit({
    required this.id,
    this.isOnline = false,
    this.groupId,
    this.isNoShoot = false,
  });
}
