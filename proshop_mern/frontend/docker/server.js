const http = require('http');
const fs = require('fs');
const path = require('path');

const buildDir = path.join(__dirname, 'build');
const port = process.env.PORT || 80;

const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const sendFile = (res, filePath) => {
  const ext = path.extname(filePath);
  const type = mimeTypes[ext] || 'application/octet-stream';
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not Found');
      return;
    }
    res.writeHead(200, { 'Content-Type': type });
    res.end(data);
  });
};

http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  const safePath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  const assetPath = path.join(buildDir, safePath);

  fs.stat(assetPath, (err, stats) => {
    if (!err && stats.isFile()) {
      sendFile(res, assetPath);
      return;
    }

    if (!err && stats.isDirectory()) {
      const indexPath = path.join(assetPath, 'index.html');
      sendFile(res, indexPath);
      return;
    }

    sendFile(res, path.join(buildDir, 'index.html'));
  });
}).listen(port, () => {
  console.log(`Frontend node server running on ${port}`);
});
