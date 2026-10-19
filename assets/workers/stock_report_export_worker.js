/* ExcelJS is loaded into this dedicated worker before this script. */
'use strict';
let workbook, sheet, columnTypes, styles, totalRows, received;
const border = {top: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  bottom: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  left: {style: 'thin', color: {argb: 'FFCBD5E1'}},
  right: {style: 'thin', color: {argb: 'FFCBD5E1'}}};

function addRow(values) {
  const row = sheet.addRow(values.map((value, i) => {
    if (columnTypes[i] === 'percent' && typeof value === 'number') return value / 100;
    if (columnTypes[i] === 'date' && typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value)) {
      const date = new Date(value);
      if (!Number.isNaN(date.getTime())) return date;
    }
    return value;
  }));
  row.height = 24;
  for (let col = 1; col <= columnTypes.length; col++) {
    row.getCell(col).style = styles[row.number % 2 === 0 ? 1 : 0][col - 1];
  }
}

self.onmessage = async event => {
  try {
    const data = event.data;
    if (data.type === 'start') {
      columnTypes = data.columnTypes;
      if (!columnTypes.length || columnTypes.length !== data.detailHeaders.length) {
        throw new Error('Invalid report columns');
      }
      workbook = new ExcelJS.Workbook();
      workbook.creator = 'Inventory System';
      // Stock reports always contain exactly one worksheet, independently of
      // the legacy KPI worker's options and summary data.
      sheet = workbook.addWorksheet(data.sheetName);
      totalRows = data.totalRows;
      received = 0;
      styles = [0, 1].map(even => columnTypes.map(type => ({
        font: {name: 'Calibri', size: 11, color: {argb: 'FF142C40'}}, border,
        fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: even ? 'FFF3F9FD' : 'FFFFFFFF'}},
        alignment: {horizontal: type === 'number' || type === 'percent' ? 'right' : 'left', vertical: 'middle'},
        ...(type === 'percent' ? {numFmt: '0.0%'} : type === 'date' ? {numFmt: 'dd/mm/yyyy'} : type === 'number' ? {numFmt: '#,##0.##'} : {})
      })));
      sheet.columns = data.detailHeaders.map((_, i) => ({width: data.detailWidths[i]}));
      const header = sheet.addRow(data.detailHeaders);
      header.height = 36;
      header.eachCell(cell => { cell.style = {
        font: {name: 'Calibri', size: 11, bold: true, color: {argb: 'FFFFFFFF'}},
        fill: {type: 'pattern', pattern: 'solid', fgColor: {argb: 'FF4EB0DE'}}, border,
        alignment: {horizontal: 'center', vertical: 'middle', wrapText: true}
      }; });
      sheet.views = [{state: 'frozen', ySplit: 1, xSplit: 1, showGridLines: false}];
      self.postMessage({type: 'ready'});
    } else if (data.type === 'rows') {
      for (const values of data.rows) addRow(values);
      received += data.rows.length;
      self.postMessage({type: 'written', processed: received, total: totalRows});
    } else if (data.type === 'finish') {
      if (received !== totalRows) throw new Error('Incomplete export data. Please retry.');
      sheet.autoFilter = {from: {row: 1, column: 1},
        to: {row: received + 1, column: columnTypes.length}};
      self.postMessage({type: 'packaging', processed: received, total: totalRows});
      const bytes = await workbook.xlsx.writeBuffer({useStyles: true, useSharedStrings: true,
        zip: {compression: 'DEFLATE', compressionOptions: {level: 6}}});
      const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      self.postMessage({type: 'done', bytes: buffer}, [buffer]);
      workbook = sheet = null;
    }
  } catch (error) {
    self.postMessage({type: 'error', message: error && error.message ? error.message : String(error)});
  }
};
