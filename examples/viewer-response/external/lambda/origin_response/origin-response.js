'use strict';

exports.handler = async (event) => {
  const { request, response } = event.Records[0].cf;
  const statusCode = parseInt(response.status, 10);

  console.log("Origin-response Lambda triggered for:", request.uri);
  console.log("Status code from origin:", statusCode);

  if (statusCode === 403 || statusCode === 404) {
    const html = `
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>${statusCode} - Not Found</title>
          <style>
            body { font-family: system-ui, sans-serif; padding: 2rem; max-width: 600px; margin: auto; background: white; color: black; }
            @media (prefers-color-scheme: dark) { body { background: #111; color: #eee; } }
            h1 { font-size: 1.8rem; margin-bottom: 1rem; }
            p { margin-bottom: 1rem; }
            a { color: #007acc; text-decoration: none; }
          </style>
        </head>
        <body>
          <h1>🚫 ${statusCode} - Page Not Found</h1>
          <p>The requested resource <code>${request.uri}</code> could not be found.</p>
          <p><a href="/browser">Back to index</a></p>
        </body>
      </html>`;

    return {
      status: statusCode.toString(),
      statusDescription: statusCode === 403 ? 'Forbidden' : 'Not Found',
      headers: {
        'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }],
        'cache-control': [{ key: 'Cache-Control', value: 'no-store' }]
      },
      body: html,
      bodyEncoding: 'text'
    };
  }

  // ✅ Return only safe headers (avoid read-only like Server, Via, X-Amz-*)
  return {
    status: response.status,
    statusDescription: response.statusDescription || '',
    headers: {
      'content-type': response.headers['content-type'] || [],
      'cache-control': response.headers['cache-control'] || []
    },
    body: response.body || '',
    bodyEncoding: response.bodyEncoding || 'text'
  };
};
