import '../../../core/models/token.dart';

abstract interface class TokenizePort {
  Future<List<Token>> analyze(String text);
}
