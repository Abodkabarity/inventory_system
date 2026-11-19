const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ExcelJS = require('../assets/workers/exceljs-4.4.0.min.js');

(async () => {
  // Produced by the Dart export helper test, before the worker boundary.
  const payload = JSON.parse(fs.readFileSync('outputs/online_overview/export_payload.json', 'utf8'));
  const messages = [];
  const context = {ExcelJS, Date, self: {postMessage: message => messages.push(message)}};
  vm.runInNewContext(fs.readFileSync('assets/workers/stock_report_export_worker.js', 'utf8'), context);
  async function send(data) {
    await context.self.onmessage({data});
    const result = messages.at(-1);
    assert.notEqual(result.type, 'error', result.message);
    return result;
  }
  await send({type: 'start', singleReport: true, sheetName: payload.sheetName,
    totalRows: payload.rows.length, detailHeaders: payload.headers,
    detailWidths: payload.widths, columnTypes: payload.types});
  await send({type: 'rows', rows: payload.rows});
  const result = await send({type: 'finish'});
  assert.equal(result.type, 'done');
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(Buffer.from(result.bytes));
  const sheet = workbook.worksheets[0];
  assert.equal(sheet.name, 'Online Overview');
  const cell = (key, row) => sheet.getCell(row, payload.keys.indexOf(key) + 1).value;
  assert.equal(cell('branch_name', 2), '71 Web Shop');
  assert.equal(cell('branch_name', 3), 'Online Two');
  assert.equal(cell('online_branches', 2), '71 Web Shop');
  assert.equal(cell('purchase_status', 2), 'AVAILABLE');
  assert.equal(cell('item_status', 2), '1#NORMAL PURCHASE');
  assert.equal(cell('estimated_retail_value_2026', 2), 4000);
  assert.equal(cell('online_stock_cover_days', 2), 230);
  assert.equal(cell('item_code', 2), 'EXPENSIVE');
  assert.equal(cell('rank', 2), 'C');
  assert.equal(cell('rank', 3), 'A');
  assert.equal(cell('a_qualification', 3), 'Concentrated demand');
  assert.equal(cell('priority_branches', 3), '71 Web Shop / Online Two');
  assert.equal(cell('price_affects_abc', 2), 'No');
  assert.equal(cell('ml_use', 2), 'advisory_only');
  console.log('Online Overview worker passed: separate statuses, typed value, row order and 71/APG branch labels.');
})().catch(error => {console.error(error); process.exitCode = 1;});
