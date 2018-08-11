// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stream_channel/stream_channel.dart';

/// The list of headers to ignore when sending back confirmation.
final _ignoreHeaders = <String>[
  // Browser headers (Chrome)
  'accept',
  'accept-language',
  'accept-encoding',
  'connection',
  'origin',
  'referer',

  // Dart IO headers
  'cookie',
  'host',
];

/// Creates a server used to test a `http` client.
///
/// On startup the server will bind to `localhost`. Then it will send the url
/// as a string back through the [channel].
///
/// The server has the following explicit endpoints used to test individual
/// functionality.
/// * /error - Will return a 400 status code.
/// * /loop - Which is used to check for max redirects.
/// * /redirect - Which is used to test that a redirect works.
/// * /no-content-length - Which returns a body with no content.
///
/// All other requests will be responded to. This is used to test the
/// individual HTTP methods. The server will return back the following
/// information in a string.
///
///     {
///       method: 'METHOD_NAME',
///       path: 'ENDPOINT_PATH',
///       headers: {
///         KEY VALUE STORE OF INDIVIDUAL HEADERS
///       },
///       body: OPTIONAL
///     }
Future<Null> hybridMain(StreamChannel channel) async {
  Uri serverUrl;
  final server = await shelf_io.serve((request) async {
    if (request.url.path == 'error') {
      return shelf.Response(400);
    }

    if (request.url.path == 'loop') {
      final n = int.parse(request.url.query);
      return shelf.Response.found(serverUrl.resolve('/loop?${n + 1}'));
    }

    if (request.url.path == 'redirect') {
      return shelf.Response.found(serverUrl.resolve('/'));
    }

    if (request.url.path == 'no-content-length') {
      return shelf.Response.ok(Stream.fromIterable([ascii.encode('body')]));
    }

    final content = <String, dynamic>{
      'method': request.method,
      'path': request.url.path,
      'headers': <String, String>{}
    };

    if (request.encoding != null) {
      final requestBody = await request.readAsString();

      if (requestBody.isNotEmpty) {
        content['body'] = requestBody;
      }
    } else {
      final requestBody = await collectBytes(request.read());

      if (requestBody.isNotEmpty) {
        content['body'] = requestBody;
      }
    }

    request.headers.forEach((name, value) {
      // Ignore headers that are generated by the client
      if (_ignoreHeaders.contains(name)) {
        return;
      }

      final Map<String, String> headers = content['headers'];
      headers[name] = value;
    });

    final encodingName = request.url.queryParameters['response-encoding'];
    final outputEncoding =
        encodingName == null ? ascii : Encoding.getByName(encodingName);

    return shelf.Response.ok(jsonEncode(content), headers: {
      'content-type': 'application/json; charset=${outputEncoding.name}',

      // CORS headers for browser testing
      'access-control-allow-origin': '*',
      'access-control-allow-headers':
          'X-Random-Header,X-Other-Header,User-Agent,Content-Type',
      'access-control-allow-methods': 'GET, PUT, POST, DELETE, PATCH, HEAD'
    });
  }, 'localhost', 0);

  serverUrl = Uri.parse('http://localhost:${server.port}');
  channel.sink.add(serverUrl.toString());
}
