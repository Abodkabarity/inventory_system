// Run after stock_excel_report_test.dart creates the typed fixture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ExcelJS = require('../assets/workers/exceljs-4.4.0.min.js');
const script = fs.readFileSync('assets/workers/stock_report_export_worker.js', 'utf8');
const kpiScript = fs.readFileSync('assets/workers/stock_check_kpi_export_worker.js', 'utf8');

async function build(start, rows, workerScript = script) {
  const messages = [];
  const context = {ExcelJS, Date, self: {postMessage: message => messages.push(message)}};
  vm.runInNewContext(workerScript, context);
  const send = async data => {
    await context.self.onmessage({data});
    const last = messages.at(-1);
    if (last.type === 'error') throw Error(last.message);
    return last;
  };
  assert.equal((await send({type: 'start', totalRows: rows.length, ...start})).type, 'ready');
  for (let index = 0; index < rows.length; index += 250) {
    assert.equal((await send({type: 'rows', rows: rows.slice(index, index + 250)})).type, 'written');
  }
  const done = await send({type: 'finish'});
  assert.equal(done.type, 'done');
  return Buffer.from(done.bytes);
}

(async () => {
  const fixture = JSON.parse(fs.readFileSync('validation/stock_excel_fixture.json'));
  const native = new ExcelJS.Workbook();
  await native.xlsx.load(fs.readFileSync('validation/stock_excel_native.xlsx'));
  assert.equal(native.worksheets.length, 1);
  const nativeSheet = native.worksheets[0];
  assert.equal(nativeSheet.getCell('A1').fill.fgColor.argb, 'FF4EB0DE');
  assert.equal(nativeSheet.getCell('I2').border.bottom.style, 'thin');
  assert.equal(nativeSheet.getCell('F2').value, 0.25);
  assert.equal(nativeSheet.getCell('D2').value.toISOString(), '2025-01-01T00:00:00.000Z');
  assert.equal(nativeSheet.getCell('H2').value, '=1+1');
  const bytes = await build({singleReport: true, sheetName: fixture.sheetName,
    detailHeaders: fixture.headers, detailWidths: fixture.widths, columnTypes: fixture.types}, fixture.rows);
  fs.writeFileSync('validation/stock_excel_web.xlsx', bytes);
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(bytes);
  assert.equal(workbook.worksheets.length, 1);
  const sheet = workbook.worksheets[0];
  assert.equal(sheet.name, 'Near Expiry');
  assert.equal(sheet.getCell('A1').fill.fgColor.argb, 'FF4EB0DE');
  assert.equal(sheet.getCell('A1').font.color.argb, 'FFFFFFFF');
  for (const edge of ['top', 'bottom', 'left', 'right']) {
    assert.equal(sheet.getCell('I2').border[edge].style, 'thin');
  }
  assert.notEqual(sheet.getCell('A2').fill.fgColor.argb, sheet.getCell('A3').fill.fgColor.argb);
  assert.equal(sheet.getCell('A2').value, '00123');
  assert.equal(sheet.getCell('C2').value, '71 Zakher Branch');
  assert.equal(sheet.getCell('C3').value, 'CITY');
  assert.equal(sheet.getCell('D2').value.toISOString(), '2025-01-01T00:00:00.000Z');
  assert.equal(sheet.getCell('D2').numFmt, 'dd/mm/yyyy');
  assert.equal(sheet.getCell('F2').value, 0.25);
  assert.equal(sheet.getCell('F2').numFmt, '0.0%');
  assert.equal(sheet.getCell('H2').value, '=1+1');
  assert.equal(sheet.views[0].ySplit, 1);
  assert.equal(sheet.views[0].xSplit, 1);
  assert.ok(sheet.autoFilter);

  // Every Stock Management report stays single-sheet, even if legacy summary
  // options accidentally reach the dedicated worker.
  for (const name of ['Stock Overview', 'MRN Overview', 'Near Expiry', 'Monthly Sales', 'Branch Stock']) {
    const report = new ExcelJS.Workbook();
    await report.xlsx.load(await build({singleReport: false, sheetName: name,
      summaryHeaders: ['Unused summary'], summaryWidths: [20], summaryRows: [['Unused']],
      detailHeaders: fixture.headers, detailWidths: fixture.widths, columnTypes: fixture.types}, fixture.rows));
    assert.deepEqual(report.worksheets.map(tab => tab.name), [name]);
    assert.equal(report.worksheets[0].rowCount, fixture.rows.length + 1);
    assert.equal(report.worksheets[0].getCell('A2').value, '00123');
  }

  // Existing KPI clients retain both sheets and the original score format.
  const kpi = await build({summaryHeaders: ['Branch'], summaryWidths: [20], summaryRows: [['A']],
    detailHeaders: ['Branch', 'Item', 'Name', 'A', 'B', 'C', 'Difference', 'Score'],
    detailWidths: Array(8).fill(20)}, [['A', '001', 'Product', 1, 2, 3, 0, 100]], kpiScript);
  const legacy = new ExcelJS.Workbook();
  await legacy.xlsx.load(kpi);
  assert.equal(legacy.worksheets.length, 2);
  assert.equal(legacy.worksheets[1].getCell('H2').numFmt, '0"%"');
  console.log('Excel worker: values, dates, percentages, group 71 labels, styles and KPI compatibility passed.');

  if (process.env.STOCK_EXCEL_STRESS === '1') {
    const rows = Array.from({length: 15000}, (_, i) => [String(i).padStart(6, '0'), `Product ${i}`,
      ...Array.from({length: 58}, (_, col) => i + col / 10)]);
    const started = Date.now();
    const large = await build({singleReport: true, sheetName: 'Stock Overview',
      detailHeaders: ['Item code', 'Product', ...Array.from({length: 58}, (_, i) => `Qty ${i}`)],
      detailWidths: Array(60).fill(18), columnTypes: ['text', 'text', ...Array(58).fill('number')]}, rows);
    assert.ok(large.length > 0);
    console.log(`15,000 rows × 60 columns: ${((Date.now() - started) / 1000).toFixed(1)}s, ${(large.length / 1048576).toFixed(1)} MB.`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
