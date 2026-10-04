// Buyer ↔ seller conversations against a fake Convex backend shaped like convex/messaging.ts:
// the thread, sending (shown only once the server has it), closed conversations, the inbox, and
// "Message" from a property page (first message → new conversation; an open one is reused; the
// owner gets no button on their own listing).

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/listings/presentation/views/property_detail_screen.dart';
import 'package:vektolux/features/messaging/data/messaging_api.dart';
import 'package:vektolux/features/messaging/presentation/buyer_messaging.dart';
import 'package:vektolux/features/messaging/presentation/conversation_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _ServerError {
  final String message;
  const _ServerError(this.message);
}

typedef _Route = Object? Function(Map<String, dynamic> args);

class _Backend {
  final Map<String, _Route> routes;
  final List<(String, Map<String, dynamic>)> calls = [];
  _Backend(this.routes);

  late final ConvexClientWrapper client = ConvexClientWrapper(
    deploymentUrl: 'https://example.invalid',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final path = body['path'] as String;
      final args = Map<String, dynamic>.from(body['args'] as Map);
      calls.add((path, args));
      final route = routes[path];
      final value = route == null ? null : route(args);
      if (value is _ServerError) {
        return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Uncaught Error: ${value.message}'}), 200);
      }
      return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
    }),
  );

  Map<String, dynamic> lastArgs(String path) => calls.lastWhere((c) => c.$1 == path).$2;
  int count(String path) => calls.where((c) => c.$1 == path).length;
}

const _buyer = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_buyer_1_0123456789abcdef',
);

final int _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _conversation(String id, {String role = 'buyer', String status = 'pending', String listingId = 'p1'}) => {
      'id': id,
      'myRole': role,
      'status': status,
      'counterpart': {'id': 'seller_1', 'name': 'Mariama Sesay', 'avatarUrl': null, 'isVerified': true},
      'listingId': listingId,
      'listingType': 'property',
      'listing': {'id': listingId, 'type': 'property', 'title': 'Modern 3 Bedroom House', 'category': 'sale', 'price': 2850000, 'currency': 'SLE', 'location': 'Aberdeen, Western Area Urban'},
      'lastMessage': 'Is this property still available?',
      'lastMessageAt': _now - 60000,
      'lastMessageFromMe': role == 'buyer',
      'unread': 0,
      'createdAt': _now - 60000,
    };

/// One thread with server-side state (messages, status).
class _Thread {
  final String id;
  String status;
  final List<Map<String, dynamic>> messages = [];
  _Thread(this.id, {this.status = 'pending'}) {
    messages.add({'id': '$id:inquiry', 'fromMe': true, 'body': 'Is this property still available?', 'createdAt': _now - 60000});
  }

  Map<String, dynamic> view() => {
        'conversation': _conversation(id, status: status),
        'canSend': status != 'declined',
        'truncated': false,
        'messages': messages,
      };
}

Map<String, _Route> _routes(_Thread thread, {List<Map<String, dynamic>>? conversations}) => {
      'messaging:getThread': (a) => a['requestId'] == thread.id ? thread.view() : const _ServerError('Conversation not found.'),
      'messaging:getMyConversations': (_) => conversations ?? [_conversation(thread.id, status: thread.status)],
      'messaging:markThreadRead': (_) => null,
      'messaging:sendMessage': (a) {
        if ((a['body'] as String).contains('spam')) return const _ServerError('You are sending messages too quickly. Please wait a moment.');
        thread.messages.add({'id': 'm${thread.messages.length + 1}', 'fromMe': true, 'body': a['body'], 'createdAt': _now});
        return null;
      },
    };

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpApp(WidgetTester tester, Widget home, _Backend backend, {UserEntity? user = _buyer}) async {
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(),
      initialState: user == null ? const AuthState(status: AuthStatus.unauthenticated) : AuthState(status: AuthStatus.authenticated, user: user));
  await tester.pumpWidget(RepositoryProvider<ConvexClientWrapper>.value(
    value: backend.client,
    child: BlocProvider<AuthBloc>.value(value: bloc, child: MaterialApp(home: home)),
  ));
  await _settle(tester);
}

MessagingApi _api(_Backend b) => MessagingApi(client: b.client, userId: _buyer.id, sessionToken: _buyer.sessionToken);

PropertyDetailScreen _property({String ownerId = 'seller_1'}) => PropertyDetailScreen(
      id: 'p1',
      title: 'Modern 3 Bedroom House',
      description: 'A bright family home.',
      category: 'sale',
      price: 2850000,
      address: 'Aberdeen, Western Area Urban',
      latitude: 8.484,
      longitude: -13.234,
      ownerId: ownerId,
      ownerName: 'Mariama Sesay',
    );

void main() {
  group('conversation screen', () {
    testWidgets('the history comes from the server; a reply is shown only once the server has it', (tester) async {
      final thread = _Thread('r1');
      final backend = _Backend(_routes(thread));
      await _pumpApp(tester, ConversationScreen(api: _api(backend), conversationId: 'r1', refreshEvery: Duration.zero), backend);
      expect(find.byKey(const Key('chat-msg-r1:inquiry')), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget, reason: 'the property the conversation is about');
      expect(find.text('Seller'), findsOneWidget);
      expect(find.byKey(const Key('chat-menu')), findsNothing, reason: 'only the seller can close an inquiry');

      await tester.enterText(find.byKey(const Key('chat-input')), 'Can I view it on Saturday?');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(backend.lastArgs('messaging:sendMessage'), {
        'requestId': 'r1',
        'body': 'Can I view it on Saturday?',
        'sessionToken': _buyer.sessionToken,
      });
      expect(find.byKey(const Key('chat-msg-m2')), findsOneWidget);
      expect(backend.count('messaging:getThread'), 2, reason: 're-read after sending');
    });

    testWidgets('a refused send shows the server message and keeps the text', (tester) async {
      final thread = _Thread('r1');
      final backend = _Backend(_routes(thread));
      await _pumpApp(tester, ConversationScreen(api: _api(backend), conversationId: 'r1', refreshEvery: Duration.zero), backend);
      await tester.enterText(find.byKey(const Key('chat-input')), 'spam spam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      expect(find.text('You are sending messages too quickly. Please wait a moment.'), findsOneWidget);
      expect(find.text('spam spam'), findsOneWidget, reason: 'nothing is shown as sent');
      expect(thread.messages, hasLength(1));
    });

    testWidgets('a closed conversation has no composer', (tester) async {
      final thread = _Thread('r1', status: 'declined');
      final backend = _Backend(_routes(thread));
      await _pumpApp(tester, ConversationScreen(api: _api(backend), conversationId: 'r1', refreshEvery: Duration.zero), backend);
      expect(find.byKey(const Key('chat-closed')), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsNothing);
    });

    testWidgets('someone else\'s conversation is refused by the server and shown as an error', (tester) async {
      final backend = _Backend(_routes(_Thread('r1')));
      await _pumpApp(tester, ConversationScreen(api: _api(backend), conversationId: 'other', refreshEvery: Duration.zero), backend);
      expect(find.text('Conversation not found.'), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsNothing);
    });
  });

  group('inbox', () {
    testWidgets('lists both sides (questions sent and received) and opens a thread', (tester) async {
      final thread = _Thread('r1');
      final backend = _Backend(_routes(thread, conversations: [
        _conversation('r1'),
        _conversation('r2', role: 'seller', listingId: 'p2'),
      ]));
      await _pumpApp(tester, MessagesInboxScreen(api: _api(backend)), backend);
      expect(backend.lastArgs('messaging:getMyConversations').containsKey('role'), isFalse);
      expect(find.byKey(const Key('conversation-r1')), findsOneWidget);
      expect(find.byKey(const Key('conversation-r2')), findsOneWidget);
      expect(find.text('Interested in: Modern 3 Bedroom House'), findsOneWidget, reason: 'the seller-side row');
      expect(find.text('You: Is this property still available?'), findsOneWidget);
    });

    testWidgets('no conversations → an honest empty state', (tester) async {
      final backend = _Backend(_routes(_Thread('r1'), conversations: const []));
      await _pumpApp(tester, MessagesInboxScreen(api: _api(backend)), backend);
      expect(find.text('No messages yet'), findsOneWidget);
    });
  });

  group('Message from a property page', () {
    testWidgets('first message: a quick question is sent as the inquiry and the new conversation opens', (tester) async {
      final thread = _Thread('r9');
      final routes = _routes(thread, conversations: const []);
      routes['adminPortal:submitContactRequest'] = (a) => {'success': true, 'requestId': 'r9'};
      final backend = _Backend(routes);
      await _pumpApp(tester, _property(), backend);
      await tester.scrollUntilVisible(find.byKey(const Key('property-message-seller')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('property-message-seller')));
      await _settle(tester);
      await tester.tap(find.text('Can I schedule a viewing?'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('first-message-send')));
      await _settle(tester, 10);
      final args = backend.lastArgs('adminPortal:submitContactRequest');
      expect(args['buyerId'], 'buyer_1');
      expect(args['listingId'], 'p1');
      expect(args['listingType'], 'property');
      expect(args['message'], 'Can I schedule a viewing?');
      expect(args['sessionToken'], _buyer.sessionToken);
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
      // dispose the conversation's refresh timer
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an open conversation about the listing is reused (no second inquiry)', (tester) async {
      final thread = _Thread('r1');
      final routes = _routes(thread);
      routes['adminPortal:submitContactRequest'] = (_) => const _ServerError('should not be called');
      final backend = _Backend(routes);
      await _pumpApp(tester, _property(), backend);
      await tester.scrollUntilVisible(find.byKey(const Key('property-message-seller')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('property-message-seller')));
      await _settle(tester, 10);
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(backend.count('adminPortal:submitContactRequest'), 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the owner sees no Message button on their own listing', (tester) async {
      final backend = _Backend(_routes(_Thread('r1')));
      await _pumpApp(tester, _property(ownerId: _buyer.id), backend);
      expect(find.byKey(const Key('property-message-seller'), skipOffstage: false), findsNothing);
    });

    testWidgets('signed out: asked to log in, nothing is sent', (tester) async {
      final backend = _Backend(_routes(_Thread('r1')));
      await _pumpApp(tester, _property(), backend, user: null);
      await tester.scrollUntilVisible(find.byKey(const Key('property-message-seller')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('property-message-seller')));
      await _settle(tester);
      expect(find.text('Please log in to message the seller.'), findsOneWidget);
      expect(backend.calls, isEmpty);
    });
  });

  test('a server without messaging yet gets a clear message', () {
    expect(friendlyServerMessage("Could not find public function for 'messaging:getThread'."),
        'Messaging becomes available after the next Vektolux server update.');
    expect(friendlyServerMessage('This conversation is closed.'), 'This conversation is closed.');
    expect(friendlyServerMessage(null, fallback: 'x'), 'x');
  });
}
