/* ExcelJS is loaded into this dedicated worker before this script. */
'use strict';
const STOCK_CHECK_KPI_EXPORT_VERSION = 2;
let workbook, details, totalRows, received = 0;
let singleReport = false, columnTypes = [], reportStyles = [];
let projectStyles = [];
let differenceColumn = 0, scoreColumn = 0;
const quarterColors = [
  ['2563EB', 'F2F7FF', 'E7EFFC'],
  ['0F766E', 'EFFAF7', 'E0F2EC'],
  ['7C3AED', 'F8F3FF', 'F0E6FC'],
  ['B45309', 'FFF8EF', 'FFF0DB']
];
function colorsFromHeaders(headers) {
  const colors = [];
  for (let column = 6; /\| System Qty$/.test(headers[column] || ''); column += 3) {
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
      column >= 7 && column < 7 + projectColors.length * 3
        ? 'FF' + projectColors[Math.floor((column - 7) / 3)][0] : color}}, border,
    alignment: {horizontal: 'center', vertical: 'middle', wrapText: true}
  }; });
}
function addRow(sheet, values, leftColumns, detail) {
  const row = sheet.addRow(values);
  const even = row.number % 2 === 0 ? 1 : 0;
  row.eachCell({includeEmpty: true}, (cell, column) => {
    cell.style = detail && column >= 7 && column < 7 + projectStyles.length * 3
      ? projectStyles[Math.floor((column - 7) / 3)][even]
      : rowStyles[even][leftColumns.includes(column) ? 1 : 0];
  });
  if (detail) {
    row.height = 36;
    row.getCell(6).style = {...rowStyles[even][1],
      alignment: {horizontal: 'left', vertical: 'middle', wrapText: true}};
    const difference = values[differenceColumn - 1], score = values[scoreColumn - 1];
    if (typeof difference === 'number' && Math.abs(difference) > 1e-9) {
      row.getCell(differenceColumn).style = {...rowStyles[even][0],
        font: {name: 'Calibri', size: 11, bold: true, color: {argb: 'FFB91C1C'}}};
    }
    const cell = row.getCell(scoreColumn);
    cell.style = typeof score === 'number' ? scoreStyles[score === 100 ? 1 : 0]
      : {...rowStyles[even][0], numFmt: '0"%"'};
  }
}
function addReportRow(values) {
  const row = details.addRow(values.map((value, i) => {
    if (columnTypes[i] === 'percent' && typeof value === 'number') return value / 100;
    if (columnTypes[i] === 'date' && typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value)) {
      const date = new Date(value);
      if (!Number.isNaN(date.getTime())) return date;
    }
    return value;
  }));
  row.height = 24;
  for (let col = 1; col <= columnTypes.length; col++) {
    row.getCell(col).style = reportStyles[row.number % 2 === 0 ? 1 : 0][col - 1];
  }
}
self.onmessage = async event => {
  try {
    const data = event.data;
    if (data.type === 'start') {
      workbook = new ExcelJS.Workbook();
      workbook.creator = 'Inventory System';
      singleReport = data.singleReport === true;
      const summary = singleReport ? null : workbook.addWorksheet('KPI Summary');
      details = workbook.addWorksheet(singleReport ? data.sheetName : 'Product Comparison');
      totalRows = data.totalRows;
      received = 0;
      if (singleReport) {
        columnTypes = data.columnTypes;
        if (columnTypes.length !== data.detailHeaders.length) throw new Error('Invalid report columns');
        reportStyles = [0, 1].map(even => columnTypes.map(type => ({
          font: {name: 'Calibri', size: 11, color: {argb: 'FF142C40'}}, border,
          fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: even ? 'FFF3F9FD' : 'FFFFFFFF'}},
          alignment: {horizontal: type === 'number' || type === 'percent' ? 'right' : 'left', vertical: 'middle'},
          ...(type === 'percent' ? {numFmt: '0.0%'} : type === 'date' ? {numFmt: 'dd/mm/yyyy'} : type === 'number' ? {numFmt: '#,##0.##'} : {})
        })));
        addHeader(details, data.detailHeaders, 'FF4EB0DE', 36, data.detailWidths);
        details.views = [{state: 'frozen', ySplit: 1, xSplit: 1, showGridLines: false}];
        self.postMessage({type: 'ready'});
        return;
      }
      // Older open clients do not send projectColors. They still export the
      // same quarter-labelled columns, so retain colors during app updates.
      // The quarter columns, not the trailing comparison/accuracy/adjustment
      // cells, determine palette length. Old clients or partial palettes are
      // safe: missing/invalid entries use the quarter-labelled fallback.
      const projectColors = colorsFromHeaders(data.detailHeaders).map((fallback, i) => {
        const supplied = data.projectColors && data.projectColors[i];
        return Array.isArray(supplied) && supplied.length === 3 &&
          supplied.every(color => typeof color === 'string' && /^[0-9a-f]{6}$/i.test(color))
          ? supplied : fallback;
      });
      differenceColumn = data.detailHeaders.findIndex(h => h.startsWith('Difference | ')) + 1;
      scoreColumn = data.detailHeaders.indexOf('Accuracy %') + 1;
      if (!differenceColumn || !scoreColumn) throw new Error('Invalid KPI columns');
      projectStyles = projectColors.map(colors => [0, 1].map(even => ({
        ...rowStyles[even][0],
        fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: 'FF' + colors[even + 1]}}
      })));
      addHeader(summary, data.summaryHeaders, 'FF142D4E', 32, data.summaryWidths);
      addHeader(details, data.detailHeaders, 'FF087E8B', 60, data.detailWidths, projectColors);
      for (const values of data.summaryRows) addRow(summary, values, [1], false);
      self.postMessage({type: 'ready'});
    } else if (data.type === 'rows') {
      for (const values of data.rows) {
        if (singleReport) addReportRow(values);
        else addRow(details, values, [1, 2, 3, 6], true);
      }
      received += data.rows.length;
      self.postMessage({type: 'written', processed: received, total: totalRows});
    } else if (data.type === 'finish') {
      if (received !== totalRows) throw new Error('Incomplete export data. Please retry.');
      if (singleReport) details.autoFilter = {
        from: {row: 1, column: 1}, to: {row: received + 1, column: columnTypes.length}
      };
      else details.autoFilter = {
        from: {row: 1, column: 1}, to: {row: received + 1, column: details.columnCount}
      };
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
