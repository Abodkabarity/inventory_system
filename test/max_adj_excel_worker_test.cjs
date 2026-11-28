// Run max_adj_excel_report_test.dart first to create the typed input fixture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Worker} = require('node:worker_threads');
const ExcelJS = require('../assets/workers/exceljs-4.4.0.min.js');

async function build(fixture, totalRows = fixture.rows.length) {
  const worker = new Worker(`
    const {parentPort} = require('node:worker_threads');
    const fs = require('node:fs');
    const vm = require('node:vm');
    const ExcelJS = require(${JSON.stringify(path.resolve('assets/workers/exceljs-4.4.0.min.js'))});
    const context = {ExcelJS, Date, self: {postMessage: (data, transfer) => parentPort.postMessage(data, transfer)}};
    vm.runInNewContext(fs.readFileSync(${JSON.stringify(path.resolve('assets/workers/stock_report_export_worker.js'))}, 'utf8'), context);
    parentPort.on('message', data => context.self.onmessage({data}));
  `, {eval: true, resourceLimits: {maxOldGenerationSizeMb: 4096}});
  let pending;
  const messages = [];
  const send = data => new Promise((resolve, reject) => {
    pending = {resolve, reject}; worker.postMessage(data);
  });
  worker.on('error', error => pending?.reject(error));
  worker.on('message', data => {
    messages.push(data.type);
    if (data.type === 'error') pending?.reject(Error(data.message));
    else if (data.type !== 'packaging') pending?.resolve(data);
  });
  let ticks = 0;
  const timer = setInterval(() => ticks++, 10);
  try {
    assert.equal((await send({type: 'start', sheetName: 'Max Adjustment',
      detailHeaders: fixture.headers, detailWidths: fixture.widths,
      columnTypes: fixture.types, totalRows})).type, 'ready');
    for (let index = 0; index < totalRows; index += 250) {
      const rows = Array.from({length: Math.min(250, totalRows - index)}, (_, offset) =>
        totalRows === fixture.rows.length ? fixture.rows[index + offset] :
          fixture.rows[(index + offset) % fixture.rows.length].map((value, column) =>
            column === 1 ? String(index + offset).padStart(8, '0') : value));
      const result = await send({type: 'rows', rows});
      assert.equal(result.processed, index + rows.length);
    }
    const result = await send({type: 'finish'});
    assert.equal(result.type, 'done');
    assert.ok(messages.includes('packaging'));
    assert.ok(ticks > 0, 'main event loop remains responsive');
    return Buffer.from(result.bytes);
  } finally { clearInterval(timer); await worker.terminate(); }
}

(async () => {
  const fixture = JSON.parse(fs.readFileSync('validation/max_adj_excel_fixture.json'));
  const bytes = await build(fixture);
  const book = new ExcelJS.Workbook();
  await book.xlsx.load(bytes);
  const sheet = book.worksheets[0];
  assert.equal(sheet.rowCount, 3);
  assert.equal(sheet.getCell('A2').value, '71 Al Ain');
  assert.equal(sheet.getCell('A3').value, 'City');
  assert.equal(sheet.getCell('B2').value, '00123');
  assert.equal(sheet.getCell('C2').value, '=literal');
  assert.equal(sheet.getCell('E2').value, 2.5);
  assert.equal(sheet.getCell('H2').value.toISOString(), '2026-11-01T00:00:00.000Z');
  assert.equal(sheet.getCell('K2').value, '');
  assert.equal(sheet.getCell('M2').value, 5);
  assert.equal(sheet.getCell('M3').value, 'Historical record');
  assert.equal(sheet.getCell('N2').value, '2026-11-01T15:26:32+04:00');
  assert.equal(sheet.getCell('P3').value, '2026-11-20T10:12:35');
  console.log('Max Excel: dates, Qty, text codes, history, group 71 names and responsive worker passed.');
  if (process.env.MAX_ADJ_STRESS === '1') {
    const started = Date.now();
    const large = await build(fixture, 107689);
    fs.writeFileSync('validation/max_adj_excel_stress.xlsx', large);
    console.log(`107,689 rows x 16 columns: ${((Date.now()-started)/1000).toFixed(1)}s, ${(large.length/1048576).toFixed(1)} MB`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
