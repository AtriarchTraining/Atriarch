// ignore_for_file: override_on_non_overriding_member
import 'package:atriarch/repositories/session_repository.dart';
import 'package:atriarch/state/shooter_state.dart';

// ignore: must_be_immutable
class FakeSessionRepository implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeShooterState implements ShooterState {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
