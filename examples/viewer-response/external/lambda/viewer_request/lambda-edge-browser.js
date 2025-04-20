// lambda-edge-browser.js

'use strict';

const https = require('https');
const http = require('http');
const url = require('url');

const S3_BASE_URL = process.env.S3_BASE_URL || 'https://geonet-open-data.s3-ap-southeast-2.amazonaws.com';

// Fetch S3 bucket XML listing
const fetchXML = (s3url) => new Promise((resolve, reject) => {
  https.get(s3url, res => {
    let data = '';
    res.on('data', chunk => (data += chunk));
    res.on('end', () => resolve(data));
  }).on('error', reject);
});

// Parse S3 XML to extract folders and files
const parseS3XML = (xml, prefix) => {
  const tag = (name) => [...xml.matchAll(new RegExp(`<${name}>(.*?)</${name}>`, 'g'))].map(m => m[1]);
  return {
    folders: tag('Prefix').filter(f => f !== prefix),
    files: tag('Key').filter(k => k !== prefix)
  };
};

// Get parent folder path
const getParentPrefix = (prefix) => {
  const parts = prefix.replace(/\/$/, '').split('/').filter(Boolean);
  return parts.length > 0 ? parts.slice(0, -1).join('/') + '/' : null;
};

// Build link with query params
const buildHref = (prefix, page = 1, sort = 'asc', limit = 25) => {
  return `/browser?prefix=${encodeURIComponent(prefix.replace(/^\/+/g, '').replace(/\/+$/g, '') + '/')}&page=${page}&sort=${sort}&limit=${limit}`;
};

// Return a 302 redirect
const redirectResponse = (location) => ({
  status: '302',
  statusDescription: 'Redirect',
  headers: { location: [{ key: 'Location', value: location }] }
});

// Generate full HTML listing
const generateListHTML = (prefix, folders, files, page, sort, limit) => {
  const parent = getParentPrefix(prefix);
  let allItems = [
    ...folders.map(name => ({ name, type: 'folder' })),
    ...files.map(name => ({ name, type: 'file' }))
  ];

  allItems.sort((a, b) => sort === 'desc' ? b.name.localeCompare(a.name) : a.name.localeCompare(b.name));

  const totalPages = Math.ceil(allItems.length / limit);
  const start = (page - 1) * limit;
  const pageItems = allItems.slice(start, start + limit);

  const link = (item) => {
    const icon = item.type === 'folder' ? '📁' : '📄';
    const href = item.type === 'folder'
      ? buildHref(item.name, 1, sort, limit)
      : `/proxy/${encodeURIComponent(item.name)}`;
    return `<li><a href="${href}"><span class="icon">${icon}</span>${item.name}</a></li>`;
  };

  let pagination = '';
  if (totalPages > 1) {
    pagination += '<div class="pagination">';
    if (page > 1) pagination += `<a href="${buildHref(prefix, page - 1, sort, limit)}">⬅️ Prev</a>`;
    for (let i = 1; i <= totalPages; i++) {
      pagination += `<a href="${buildHref(prefix, i, sort, limit)}"${i === page ? ' class="active"' : ''}>${i}</a>`;
    }
    if (page < totalPages) pagination += `<a href="${buildHref(prefix, page + 1, sort, limit)}">Next ➡️</a>`;
    pagination += '</div>';
  }

  const toggleSort = sort === 'asc' ? 'desc' : 'asc';
  const sortBtn = `<a href="${buildHref(prefix, 1, toggleSort, limit)}" class="sort-toggle">Sort: ${sort === 'asc' ? '⬆️' : '⬇️'}</a>`;

  let limitBtn = '';
  if (allItems.length > 25) {
    limitBtn = [25, 50, 75, 100].map(val => {
      return `<a href="${buildHref(prefix, 1, sort, val)}"${val === limit ? ' class="active"' : ''}>${val}</a>`;
    }).join(' ');
    limitBtn = `<div class="limit-toggle">Show: ${limitBtn}</div>`;
  }

  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Index of ${prefix || '/'}</title><style>:root{color-scheme:light dark}body{font-family:system-ui,sans-serif;padding:2rem;margin:auto;max-width:800px;background:white;color:black}@media(prefers-color-scheme:dark){body{background:#111;color:#eee}}h1{font-size:1.4rem;margin-bottom:1rem}ul{list-style:none;padding:0}li{margin:0.5rem 0}.icon{margin-right:0.4rem}.pagination a,.sort-toggle,.limit-toggle a{margin-right:0.5rem;text-decoration:none}.pagination a.active,.limit-toggle a.active{font-weight:bold;text-decoration:underline}</style></head><body><h1>Index of ${prefix || '/'}</h1><div class="sort-toggle">${sortBtn}</div>${limitBtn}${parent ? `<p><a href="${buildHref(parent, 1, sort, limit)}">⬅️ Parent folder</a></p>` : ''}<ul>${pageItems.map(link).join('')}</ul>${pagination}</body></html>`;
};

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const { uri, querystring } = request;

  if (uri === '/') return redirectResponse('/browser');

  if (uri.startsWith('/proxy/')) {
    const key = decodeURIComponent(uri.replace(/^\/proxy\//, '').replace(/\?.*$/, ''));
    if (key.endsWith('/')) return redirectResponse(`/browser?prefix=${encodeURIComponent(key)}`);
    return redirectResponse(`${S3_BASE_URL}/${encodeURIComponent(key)}`);
  }

  if (!uri.startsWith('/browser')) return request;

  const query = new URLSearchParams(querystring);
  const prefix = decodeURIComponent(query.get('prefix') || '').replace(/^\/+/g, '');
  const page = parseInt(query.get('page') || '1', 10);
  const sort = query.get('sort') || 'asc';
  const limit = parseInt(query.get('limit') || '25', 10);
  const s3url = `${S3_BASE_URL}/?prefix=${encodeURIComponent(prefix)}&delimiter=/`;

  try {
    const xml = await fetchXML(s3url);
    if (!xml.includes('<ListBucketResult')) throw new Error('Unexpected XML format');

    const { folders, files } = parseS3XML(xml, prefix);
    const html = generateListHTML(prefix, folders, files, page, sort, limit);

    return {
      status: '200',
      statusDescription: 'OK',
      headers: {
        'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }],

        // ✅ Enable caching for 5 minutes
        'cache-control': [{ key: 'Cache-Control', value: 'public, max-age=300' }],

        // 🌐 Let intermediate caches know this is based on Accept-Encoding (gzip/brotli)
        'vary': [{ key: 'Vary', value: 'Accept-Encoding' }],

        // 🏷 Optionally add a lightweight ETag based on content hash
        'etag': [{ key: 'ETag', value: `"${Buffer.from(html).toString('base64').slice(0, 16)}"` }],

        'x-powered-by': [{ key: 'X-Powered-By', value: 'lambda-edge-browser' }]
      },
      body: html
    };
  } catch (err) {
    return {
      status: '502',
      statusDescription: 'Bad Gateway',
      headers: {
        'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }]
      },
      body: `<h1>Error</h1><p>${err.message}</p>`
    };
  }
};

// Local testing
if (require.main === module) {
  http.createServer(async (req, res) => {
    const parsed = url.parse(req.url, true);
    const { pathname, query } = parsed;
    const querystring = new URLSearchParams(query).toString();
    const event = {
      Records: [{
        cf: { request: { uri: pathname, querystring } }
      }]
    };

    try {
      const response = await exports.handler(event);
      res.writeHead(parseInt(response.status), Object.fromEntries(
        Object.entries(response.headers || {}).map(([k, v]) => [k, v[0].value])
      ));
      res.end(response.bodyEncoding === 'base64' ? Buffer.from(response.body, 'base64') : response.body);
    } catch (err) {
      res.writeHead(500);
      res.end('Local error: ' + err.message);
    }
  }).listen(3000, () => {
    console.log('🚀 Local test server running at http://localhost:3000/browser?prefix=');
  });
}
