import 'package:firebase_auth/firebase_auth.dart';

class AuthErrorInfo {
  const AuthErrorInfo({required this.code, required this.message});

  final String code;
  final String message;

  factory AuthErrorInfo.fromFirebaseException(
    FirebaseAuthException exception, {
    required String provider,
  }) {
    final code = exception.code;
    final rawMessage = exception.message ?? '';

    final message = switch (code) {
      'operation-not-allowed' => provider == 'google'
          ? 'Login Google desabilitado no Firebase. Habilite em Authentication > Sign-in method.'
          : 'Login por e-mail/senha desabilitado no Firebase. Habilite em Authentication > Sign-in method.',
      'permission-denied' when rawMessage.contains('consumer-api-key') ||
          rawMessage.contains('has been suspended') =>
        'A chave de API do Firebase foi suspensa ou bloqueada no projeto. Verifique o projeto conectado, billing e restricoes da API.',
      'unauthorized-domain' => 'Dominio nao autorizado. Adicione o dominio atual em Authentication > Settings > Authorized domains.',
      'popup-blocked' => 'Popup bloqueado pelo navegador. Libere popups para continuar o login.',
      'popup-closed-by-user' => 'Login cancelado antes da confirmacao.',
      'invalid-email' => 'E-mail invalido.',
      'user-disabled' => 'Usuario desabilitado.',
      'user-not-found' => 'Usuario nao encontrado.',
      'wrong-password' => 'Credenciais invalidas.',
      'invalid-credential' => 'Credenciais invalidas.',
      _ => exception.message ?? 'Falha ao autenticar.',
    };

    return AuthErrorInfo(code: code, message: message);
  }

  static const AuthErrorInfo unexpected = AuthErrorInfo(
    code: 'unexpected',
    message: 'Erro inesperado durante o login.',
  );
}