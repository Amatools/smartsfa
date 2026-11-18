const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSankhyaProductImageChunksSql,
  detectImageFormat,
  buildFirebaseDownloadUrl,
} = require('../../src/billing/sankhya_product_images_data_helpers');

test('buildSankhyaProductImageChunksSql returns empty when no valid product codes', () => {
  const sql = buildSankhyaProductImageChunksSql(['0', 'ABC', null, '']);
  assert.equal(sql, '');
});

test('buildSankhyaProductImageChunksSql builds query with chunk size and filtered codes', () => {
  const sql = buildSankhyaProductImageChunksSql(
    ['001', '2', '2', '0', 'A'],
    { chunkSize: 2048 },
  );

  assert.match(sql, /P\.CODPROD IN \(1, 2\)/);
  assert.match(sql, /DBMS_LOB\.SUBSTR\(/);
  assert.match(sql, /2048/);
  assert.match(sql, /ORDER BY P\.CODPROD, LEVEL/);
});

test('detectImageFormat identifies png and defaults to jpg', () => {
  assert.equal(detectImageFormat(Buffer.from([0x89, 0x50, 0x4e, 0x47])), 'png');
  assert.equal(detectImageFormat(Buffer.from([0x01, 0x02, 0x03, 0x04])), 'jpg');
  assert.equal(detectImageFormat(Buffer.alloc(0)), 'jpg');
});

test('buildFirebaseDownloadUrl encodes storage path and appends token', () => {
  const url = buildFirebaseDownloadUrl({
    bucketName: 'bucket-name',
    storagePath: 'tenants/t1/produtos/p1 image.jpg',
    token: 'tok123',
  });

  assert.equal(
    url,
    'https://firebasestorage.googleapis.com/v0/b/bucket-name/o/tenants%2Ft1%2Fprodutos%2Fp1%20image.jpg?alt=media&token=tok123',
  );
});
