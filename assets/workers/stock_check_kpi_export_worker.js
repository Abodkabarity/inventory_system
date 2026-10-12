/* ExcelJS is loaded into this dedicated worker before this script. */
'use strict';
let workbook, details, totalRows, received = 0;
let projectStyles = [];
const quarterColors = [
  ['2563EB', 'F2F7FF', 'E7EFFC'],
  ['0F766E', 'EFFAF7', 'E0F2EC'],
  ['7C3AED', 'F8F3FF', 'F0E6FC'],
  ['B45309', 'FFF8EF', 'FFF0DB']
];
function colorsFromHeaders(headers) {
  const colors = [];
  for (let column = 6; column < headers.length - 2; column += 3) {
    const quarter = headers[column].match(/\bQ([1-4])\b/i);
    colors.push(quarterColors[quarter ? Number(quarter[1]) - 1 : colors.length % 4]);
  }
  return colors;
}
const border = {top: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  bottom: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  left: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  right: {style: 'thin', color: {argb: 'FFCBD5E1'}}};
const rowStyles = [false, true].map(even => [false, true].map(left => ({
  font: {name: 'Calibri', size: 11}, border,
  alignment: {horizontal: left ? 'left' : 'center', vertical: 'middle'},
  ...(even ? {fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: 'FFF8FAFC'}}} : {})
})));
const scoreStyles = [false, true].map(correct => ({
  ...rowStyles[0][0], numFmt: '0"%"',
  font: {name: 'Calibri', size: 11, bold: true, color: {argb: correct ? 'FF15803D' : 'FFB91C1C'}},
  fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: correct ? 'FFDCFCE7' : 'FFFEE2E2'}}
}));
function addHeader(sheet, headers, color, height, widths, projectColors = []) {
  sheet.views = [{state: 'frozen', ySplit: 1}];
  sheet.columns = headers.map((_, i) => ({width: widths[i]}));
  const row = sheet.addRow(headers);
  row.height = height;
  row.eachCell((cell, column) => { cell.style = {
    font: {name: 'Calibri', size: 11, bold: true, color: {argb: 'FFFFFFFF'}},
    fill: {type: 'pattern', pattern: 'solid', fgColor: {argb:
      column >= 7 && column <= headers.length - 2 && projectColors.length
        ? 'FF' + projectColors[Math.floor((column - 7) / 3)][0] : color}}, border,
    alignment: {horizontal: 'center', vertical: 'middle', wrapText: true}
  }; });
}
function addRow(sheet, values, leftColumns, detail) {
  const row = sheet.addRow(values);
  const even = row.number % 2 === 0 ? 1 : 0;
  row.eachCell({includeEmpty: true}, (cell, column) => {
    cell.style = detail && column >= 7 && column <= values.length - 2 && projectStyles.length
      ? projectStyles[Math.floor((column - 7) / 3)][even]
      : rowStyles[even][leftColumns.includes(column) ? 1 : 0];
  });
  if (detail) {
    const difference = values[values.length - 2], score = values[values.length - 1];
    if (typeof difference === 'number' && Math.abs(difference) > 1e-9) {
      row.getCell(values.length - 1).style = {...rowStyles[even][0],
        font: {name: 'Calibri', size: 11, bold: true, color: {argb: 'FFB91C1C'}}};
    }
    const cell = row.getCell(values.length);
    cell.style = typeof score === 'number' ? scoreStyles[score === 100 ? 1 : 0]
      : {...rowStyles[even][0], numFmt: '0"%"'};
  }
}
self.onmessage = async event => {
  try {
    const data = event.data;
    if (data.type === 'start') {
      workbook = new ExcelJS.Workbook();
      workbook.creator = 'Inventory System';
      const summary = workbook.addWorksheet('KPI Summary');
      details = workbook.addWorksheet('Product Comparison');
      totalRows = data.totalRows;
      received = 0;
      // Older open clients do not send projectColors. They still export the
      // same quarter-labelled columns, so retain colors during app updates.
      const projectColors = data.projectColors && data.projectColors.length
        ? data.projectColors : colorsFromHeaders(data.detailHeaders);
      projectStyles = projectColors.map(colors => [0, 1].map(even => ({
        ...rowStyles[even][0],
        fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: 'FF' + colors[even + 1]}}
      })));
      addHeader(summary, data.summaryHeaders, 'FF142D4E', 32, data.summaryWidths);
      addHeader(details, data.detailHeaders, 'FF087E8B', 60, data.detailWidths, projectColors);
      for (const values of data.summaryRows) addRow(summary, values, [1], false);
      self.postMessage({type: 'ready'});
    } else if (data.type === 'rows') {
      for (const values of data.rows) addRow(details, values, [1, 2, 3, 6], true);
      received += data.rows.length;
      self.postMessage({type: 'written', processed: received, total: totalRows});
    } else if (data.type === 'finish') {
      if (received !== totalRows) throw new Error('Incomplete export data. Please retry.');
      self.postMessage({type: 'packaging', processed: received, total: totalRows});
      const bytes = await workbook.xlsx.writeBuffer({useStyles: true, useSharedStrings: true,
        zip: {compression: 'DEFLATE', compressionOptions: {level: 6}}});
      const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      self.postMessage({type: 'done', bytes: buffer}, [buffer]);
      workbook = details = null;
    }
  } catch (error) {
    self.postMessage({type: 'error', message: error && error.message ? error.message : String(error)});
  }
};
