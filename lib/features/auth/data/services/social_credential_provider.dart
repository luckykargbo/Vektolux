import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/repositories/auth_repository.dart';

/// A provider-issued identity token for ONE sign-in attempt. [nonce] is the raw server nonce
/// (Apple only); it is never logged or persisted.
class SocialCredential {
  final String idToken;
  final String? nonce;
  const SocialCredential({required this.idToken, this.nonce});
}

/// Runs the real Google / Apple authentication UI. Returns null when the user cancels, so a
/// cancellation can never be mistaken for (or turned into) an account change.
abstract class SocialCredentialProvider {
  Future<SocialCredential?> obtain(String provider);
}

class PlatformSocialCredentialProvider implements SocialCredentialProvider {
  final AuthRepository _repository;
  PlatformSocialCredentialProvider(this._repository);

  late final GoogleSignIn _google = GoogleSignIn(
    clientId: kIsWeb
        ? AuthConstants.googleWebClientId
        : (defaultTargetPlatform == TargetPlatform.iOS ? AuthConstants.googleIosClientId : null),
    serverClientId: kIsWeb ? null : AuthConstants.googleWebClientId,
    scopes: ['email', 'profile'],
  );

  @override
  Future<SocialCredential?> obtain(String provider) async {
    switch (provider) {
      case 'google':
        final account = await _google.signIn();
        if (account == null) return null;
        final auth = await account.authentication;
        final idToken = auth.idToken;
        // The access token is NOT an identity proof and the server would refuse it.
        if (idToken == null || idToken.isEmpty) {
          throw const AuthException('Google did not return an identity token. Please try again.');
        }
        return SocialCredential(idToken: idToken);
      case 'apple':
        // One-time server nonce per attempt; Apple signs its hash into the identity token.
        final challenge = await _repository.createOAuthChallenge(provider: 'apple');
        try {
          final credential = await SignInWithApple.getAppleIDCredential(
            scopes: [AppleIDAuthorizationScopes.email],
            nonce: challenge.nonceHash,
          );
          final idToken = credential.identityToken;
          if (idToken == null || idToken.isEmpty) return null;
          return SocialCredential(idToken: idToken, nonce: challenge.nonce);
        } on SignInWithAppleAuthorizationException catch (e) {
          if (e.code == AuthorizationErrorCode.canceled) return null;
          rethrow;
        }
      default:
        throw AuthException('Unsupported sign-in provider.');
    }
  }
}
