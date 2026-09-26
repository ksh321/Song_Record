import 'auth_session.dart';

abstract interface class AccountActionsApi {
  Future<void> logout(AuthSession session);
  Future<void> unlinkProvider(AuthSession session, String provider);
}
