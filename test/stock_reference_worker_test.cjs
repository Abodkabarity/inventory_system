const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ExcelJS = require('../assets/workers/exceljs-4.4.0.min.js');

(async () => {
  for (const sheetName of ['Stock Overview', 'MRN Overview', 'MRN CD Overview', 'Near Expiry']) {
    const messages = [];
    const context = {ExcelJS, Date, self: {postMessage: m => messages.push(m)}};
    vm.runInNewContext(fs.readFileSync('assets/workers/stock_report_export_worker.js', 'utf8'), context);
    const send = async data => {
      await context.self.onmessage({data});
      const result = messages.at(-1);
      assert.notEqual(result.type, 'error', result.message);
      return result;
    };
    await send({type: 'start', singleReport: true, sheetName, totalRows: 2,
      detailHeaders: ['Reference', 'Warehouse', 'Purchase Status', 'Total Qty', 'Bonus Qty'], detailWidths: [24, 30, 27, 18, 18], columnTypes: ['text', 'text', 'text', 'number', 'number']});
    await send({type: 'rows', rows: [['00017 · PO-X', '71 Zakher Branch', 'AVAILABLE', 12, 2], ['00003', 'CITY', 'NOT AVAILABLE', 8, 0]]});
    const done = await send({type: 'finish'});
    assert.equal(done.type, 'done');
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(Buffer.from(done.bytes));
    assert.equal(workbook.worksheets.length, 1);
    const sheet = workbook.worksheets[0];
    assert.equal(sheet.name, sheetName);
    assert.equal(sheet.getCell('A2').value, '00017 · PO-X');
    assert.equal(sheet.getCell('A3').value, '00003');
    assert.equal(sheet.getCell('B2').value, '71 Zakher Branch');
    assert.equal(sheet.getCell('B3').value, 'CITY');
    assert.equal(sheet.getCell('C2').value, 'AVAILABLE');
    assert.equal(sheet.getCell('C3').value, 'NOT AVAILABLE');
    assert.equal(sheet.getCell('D2').value, 12);
    assert.equal(sheet.getCell('E2').value, 2);
    assert.equal(sheet.getCell('D3').value, 8);
    assert.equal(sheet.getCell('E3').value, 0);
  }
  console.log('Stock worker: Overview, MRN, MRN CD and Near Expiry preserve Total Qty, Bonus, Reference, Purchase Status and branch labels.');
})().catch(error => { console.error(error); process.exitCode = 1; });
