import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// Web version: the browser makes the connections (its own name lookup and certificates).

http.Client makeHttpClient() => http.Client();

WebSocketChannel openWebSocket(Uri uri) => WebSocketChannel.connect(uri);

String connectionNote(String host) => 'browser';
