package com.mangao.wrs.service;

import com.lowagie.text.Chunk;
import com.lowagie.text.Document;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.Image;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.Phrase;
import com.lowagie.text.Rectangle;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import com.lowagie.text.pdf.draw.LineSeparator;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.apache.poi.ss.usermodel.BorderStyle;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.HorizontalAlignment;
import org.apache.poi.xssf.usermodel.XSSFCell;
import org.apache.poi.xssf.usermodel.XSSFColor;
import org.apache.poi.xssf.usermodel.XSSFFont;
import org.apache.poi.xssf.usermodel.XSSFRow;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

/**
 * Export Report (FR-10; Admin Sales 4): the daily, weekly and unpaid accounts reports as a PDF
 * (OpenPDF) or a spreadsheet (Apache POI). Money in the PDF is written "P1,310.00".
 */
@Component
public class Export {
  private static final String STATION = "Mangao Water Refilling Station";
  private static final Color BLUE = new Color(0x0A, 0x84, 0xE0);
  private static final Color INK = new Color(0x11, 0x18, 0x27);
  private static final Color MUTED = new Color(0x6B, 0x72, 0x80);
  private static final Color STRIPE = new Color(0xEE, 0xF6, 0xFD);
  private static final String[] MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};

  private final Db db;
  private final Reports reports;
  private final Customers customers;
  private final Settings settings;

  public Export(Db db, Reports reports, Customers customers, Settings settings) {
    this.db = db;
    this.reports = reports;
    this.customers = customers;
    this.settings = settings;
  }

  // ---------------------------------------------------------------- report data
  public record Col(String header, String key, int width, String kind) {}

  public record Table(String title, List<Col> columns, List<Map<String, Object>> rows) {}

  public record Report(String fileBase, String title, String subtitle, List<Object[]> summary, List<Table> tables, String address) {}

  public record File(String fileName, String type, byte[] bytes) {}

  static String money(Object v) {
    DecimalFormat f = new DecimalFormat("#,##0.00", DecimalFormatSymbols.getInstance(Locale.US));
    return "P" + f.format(V.num(v));
  }

  static String dateLabel(String ymd) {
    LocalDate d = LocalDate.parse(ymd);
    return MONTHS[d.getMonthValue() - 1] + " " + d.getDayOfMonth() + ", " + d.getYear();
  }

  static String phoneText(String p) {
    return p != null && p.matches("^\\d{11}$") ? p.substring(0, 4) + " " + p.substring(4, 7) + " " + p.substring(7) : (p == null ? "" : p);
  }

  static String pct(Double v) {
    if (v == null) return "No sales last week";
    if (v == 0) return "Same as last week";
    return (v > 0 ? "+" : "") + V.jsNumber(v) + "%";
  }

  private static Col col(String header, String key, int width) {
    return new Col(header, key, width, null);
  }

  private static Col col(String header, String key, int width, String kind) {
    return new Col(header, key, width, kind);
  }

  @SuppressWarnings("unchecked")
  public Report build(String report, String date) {
    String today = Clock.ymd(Clock.now());
    String address = settings.stationAddress();
    if ("daily".equals(report)) {
      Instant[] r = Reports.dayRange(date);
      Map<String, Object> s = reports.daySummary(r[0], r[1]);
      List<Map<String, Object>> rows = new ArrayList<>();
      for (Map<String, Object> o : reports.dayOrders(r[0], r[1])) {
        rows.add(M.with(o, "id", "#" + o.get("id"), "time", Clock.clock(V.instant(o.get("at")))));
      }
      return new Report("Mangao-Daily-Sales-" + date, "Daily Sales Report", dateLabel(date), List.of(
          new Object[] {"Money earned", s.get("moneyEarned"), "money"},
          new Object[] {"Unpaid", s.get("unpaid"), "money"},
          new Object[] {"Gallons processed", s.get("gallons"), null},
          new Object[] {"Packages sold", s.get("packages"), null},
          new Object[] {"Delivery gallons", s.get("deliveryGallons"), null},
          new Object[] {"Walk-in gallons", s.get("walkInGallons"), null},
          new Object[] {"Rider paid", s.get("riderPaid"), "money"},
          new Object[] {"Orders completed", V.num(s.get("delivered")) + V.num(s.get("walkIns")), null}),
          List.of(new Table("Orders", List.of(
              col("Order", "id", 8), col("Time", "time", 10), col("Customer", "name", 26), col("Gallons", "quantity", 9, "num"),
              col("Type", "type", 10), col("Amount", "total", 13, "money"), col("Payment", "tag", 16)), rows)),
          address);
    }
    if ("weekly".equals(report)) {
      String start = Reports.mondayOf(date);
      Map<String, Object> week = reports.weekSummary(start, today);
      Map<String, Object> last = reports.weekSummary(Reports.addDays(start, -7), today);
      Map<String, Object> t = (Map<String, Object>) week.get("totals");
      Map<String, Object> l = (Map<String, Object>) last.get("totals");
      List<Map<String, Object>> days = (List<Map<String, Object>>) week.get("days");
      List<Map<String, Object>> lastDays = (List<Map<String, Object>>) last.get("days");
      List<Map<String, Object>> rows = new ArrayList<>();
      for (int i = 0; i < days.size(); i++) {
        Map<String, Object> d = days.get(i);
        rows.add(M.with(d, "dateText", dateLabel(String.valueOf(d.get("date"))), "lastWeek", lastDays.get(i).get("moneyEarned")));
      }
      return new Report("Mangao-Weekly-Sales-" + start, "Weekly Sales Report", dateLabel(start) + " to " + dateLabel(Reports.addDays(start, 6)), List.of(
          new Object[] {"Money earned", t.get("moneyEarned"), "money"},
          new Object[] {"Last week", l.get("moneyEarned"), "money"},
          new Object[] {"Change in money earned", pct(Reports.change(V.num(t.get("moneyEarned")), V.num(l.get("moneyEarned")))), null},
          new Object[] {"Gallons processed", t.get("gallons"), null},
          new Object[] {"Gallons last week", l.get("gallons"), null},
          new Object[] {"Packages sold", t.get("packages"), null},
          new Object[] {"Orders completed", t.get("orders"), null},
          new Object[] {"Unpaid", t.get("unpaid"), "money"},
          new Object[] {"Rider paid", t.get("riderPaid"), "money"}),
          List.of(new Table("Day by day", List.of(
              col("Day", "day", 7), col("Date", "dateText", 14), col("Money earned", "moneyEarned", 15, "money"), col("Last week", "lastWeek", 13, "money"),
              col("Gallons", "gallons", 9, "num"), col("Orders", "orders", 8, "num"), col("Unpaid", "unpaid", 12, "money")), rows)),
          address);
    }
    // unpaid accounts (as of now)
    List<Map<String, Object>> list = customers.unpaidAccounts("");
    List<Map<String, Object>> orders = db.query(
        "SELECT k.order_id, k.ckey, k.order_type, k.quantity, k.total_amount, COALESCE(k.delivered_at, k.created_at) AS at"
            + " FROM " + Customers.KEYED_ORDERS + " k WHERE " + Customers.UNPAID + " ORDER BY at");
    Map<String, Object> nameOf = new HashMap<>();
    double owed = 0;
    List<Map<String, Object>> custRows = new ArrayList<>();
    for (Map<String, Object> c : list) {
      nameOf.put(String.valueOf(c.get("key")), c.get("name"));
      owed += V.num(c.get("owed"));
      Instant oldest = V.instant(c.get("oldest"));
      custRows.add(M.with(c, "phone", phoneText(String.valueOf(c.get("phone"))), "oldestText", oldest != null ? dateLabel(Clock.ymd(oldest)) : ""));
    }
    List<Map<String, Object>> orderRows = new ArrayList<>();
    for (Map<String, Object> o : orders) {
      Instant at = V.instant(o.get("at"));
      orderRows.add(M.with(o, "id", "#" + V.lng(o.get("order_id")), "dateText", at != null ? dateLabel(Clock.ymd(at)) : "",
          "name", nameOf.getOrDefault(String.valueOf(o.get("ckey")), "Walk-in"), "total", V.num(o.get("total_amount"))));
    }
    return new Report("Mangao-Unpaid-Accounts-" + today, "Unpaid Accounts", "As of " + dateLabel(today), List.of(
        new Object[] {"Total owed", owed, "money"},
        new Object[] {"Customers", list.size(), null},
        new Object[] {"Unpaid orders", orders.size(), null}),
        List.of(
            new Table("Customers", List.of(col("Customer", "name", 26), col("Phone", "phone", 15), col("Unpaid orders", "orders", 14, "num"),
                col("Owed", "owed", 13, "money"), col("Oldest", "oldestText", 14)), custRows),
            new Table("Unpaid orders", List.of(col("Order", "id", 8), col("Date", "dateText", 14), col("Customer", "name", 26),
                col("Gallons", "quantity", 9, "num"), col("Type", "order_type", 10), col("Amount", "total", 13, "money")), orderRows)),
        address);
  }

  private static String cellText(Col c, Object v) {
    if ("money".equals(c.kind())) return money(v);
    if (v == null) return "";
    return V.str(v);
  }

  // ---------------------------------------------------------------- PDF
  public byte[] toPdf(Report r) throws Exception {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    Document doc = new Document(PageSize.A4, 40, 40, 36, 40);
    PdfWriter.getInstance(doc, out);
    doc.addTitle(r.title() + " - " + r.subtitle());
    doc.addAuthor(STATION);
    doc.open();
    Font h1 = new Font(Font.HELVETICA, 16, Font.BOLD, INK);
    Font small = new Font(Font.HELVETICA, 9.5f, Font.NORMAL, MUTED);
    Font title = new Font(Font.HELVETICA, 18, Font.BOLD, BLUE);
    Font body = new Font(Font.HELVETICA, 11, Font.NORMAL, INK);
    Font label = new Font(Font.HELVETICA, 10, Font.NORMAL, MUTED);
    Font value = new Font(Font.HELVETICA, 11, Font.BOLD, INK);
    Font tableTitle = new Font(Font.HELVETICA, 12, Font.BOLD, INK);
    Font head = new Font(Font.HELVETICA, 9, Font.BOLD, Color.WHITE);
    Font cell = new Font(Font.HELVETICA, 9, Font.NORMAL, INK);

    // Header: logo, station name, address, created
    PdfPTable header = new PdfPTable(new float[] {1, 9});
    header.setWidthPercentage(100);
    PdfPCell logoCell = new PdfPCell();
    logoCell.setBorder(Rectangle.NO_BORDER);
    try (InputStream in = Export.class.getResourceAsStream("/logo.png")) {
      if (in != null) {
        Image logo = Image.getInstance(in.readAllBytes());
        logo.scaleToFit(44, 44);
        logoCell.addElement(logo);
      }
    }
    header.addCell(logoCell);
    PdfPCell nameCell = new PdfPCell();
    nameCell.setBorder(Rectangle.NO_BORDER);
    nameCell.addElement(new Paragraph(STATION, h1));
    if (r.address() != null && !r.address().isEmpty()) nameCell.addElement(new Paragraph(r.address(), small));
    nameCell.addElement(new Paragraph("Created " + dateLabel(Clock.ymd(Clock.now())) + " " + Clock.clock(Clock.now()), small));
    header.addCell(nameCell);
    doc.add(header);
    LineSeparator line = new LineSeparator(1.5f, 100, BLUE, Element.ALIGN_CENTER, -4);
    doc.add(new Chunk(line));
    Paragraph t = new Paragraph(r.title(), title);
    t.setSpacingBefore(10);
    doc.add(t);
    doc.add(new Paragraph(r.subtitle(), body));

    // Summary, two columns
    PdfPTable sum = new PdfPTable(new float[] {3, 2.2f, 3, 2.2f});
    sum.setWidthPercentage(100);
    sum.setSpacingBefore(12);
    for (Object[] s : r.summary()) {
      PdfPCell a = new PdfPCell(new Phrase(String.valueOf(s[0]), label));
      PdfPCell b = new PdfPCell(new Phrase("money".equals(s[2]) ? money(s[1]) : V.str(s[1]), value));
      for (PdfPCell c : new PdfPCell[] {a, b}) {
        c.setBorder(Rectangle.NO_BORDER);
        c.setPaddingBottom(6);
        sum.addCell(c);
      }
    }
    if (r.summary().size() % 2 == 1) {
      PdfPCell blank = new PdfPCell(new Phrase(""));
      blank.setBorder(Rectangle.NO_BORDER);
      blank.setColspan(2);
      sum.addCell(blank);
    }
    doc.add(sum);

    // Tables
    for (Table tb : r.tables()) {
      Paragraph p = new Paragraph(tb.title(), tableTitle);
      p.setSpacingBefore(14);
      p.setSpacingAfter(6);
      doc.add(p);
      float[] widths = new float[tb.columns().size()];
      for (int i = 0; i < widths.length; i++) widths[i] = tb.columns().get(i).width();
      PdfPTable table = new PdfPTable(widths);
      table.setWidthPercentage(100);
      table.setHeaderRows(1);
      for (Col c : tb.columns()) {
        PdfPCell h = new PdfPCell(new Phrase(c.header(), head));
        h.setBackgroundColor(BLUE);
        h.setBorder(Rectangle.NO_BORDER);
        h.setPadding(4);
        h.setHorizontalAlignment(c.kind() != null ? Element.ALIGN_RIGHT : Element.ALIGN_LEFT);
        table.addCell(h);
      }
      if (tb.rows().isEmpty()) {
        PdfPCell none = new PdfPCell(new Phrase("None", new Font(Font.HELVETICA, 9, Font.NORMAL, MUTED)));
        none.setColspan(widths.length);
        none.setBorder(Rectangle.NO_BORDER);
        none.setPadding(4);
        table.addCell(none);
      }
      int n = 0;
      for (Map<String, Object> row : tb.rows()) {
        for (Col c : tb.columns()) {
          PdfPCell x = new PdfPCell(new Phrase(cellText(c, row.get(c.key())), cell));
          x.setBorder(Rectangle.NO_BORDER);
          x.setPadding(4);
          x.setNoWrap(true);
          if (n % 2 == 1) x.setBackgroundColor(STRIPE);
          x.setHorizontalAlignment(c.kind() != null ? Element.ALIGN_RIGHT : Element.ALIGN_LEFT);
          table.addCell(x);
        }
        n++;
      }
      doc.add(table);
    }
    doc.close();
    return out.toByteArray();
  }

  // ---------------------------------------------------------------- spreadsheet
  public byte[] toXlsx(Report r) throws Exception {
    try (XSSFWorkbook wb = new XSSFWorkbook(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      wb.getProperties().getCoreProperties().setCreator(STATION);
      short peso = wb.createDataFormat().getFormat("\"₱\"#,##0.00");
      CellStyle money = wb.createCellStyle();
      money.setDataFormat(peso);
      XSSFFont bold = wb.createFont();
      bold.setBold(true);
      CellStyle boldStyle = wb.createCellStyle();
      boldStyle.setFont(bold);
      CellStyle boldMoney = wb.createCellStyle();
      boldMoney.setFont(bold);
      boldMoney.setDataFormat(peso);
      XSSFFont white = wb.createFont();
      white.setBold(true);
      white.setColor(new XSSFColor(new byte[] {(byte) 255, (byte) 255, (byte) 255}, null));
      CellStyle head = wb.createCellStyle();
      head.setFont(white);
      ((org.apache.poi.xssf.usermodel.XSSFCellStyle) head).setFillForegroundColor(new XSSFColor(new byte[] {(byte) 0x0A, (byte) 0x84, (byte) 0xE0}, null));
      head.setFillPattern(FillPatternType.SOLID_FOREGROUND);
      head.setBorderBottom(BorderStyle.NONE);
      head.setAlignment(HorizontalAlignment.LEFT);

      XSSFSheet s = wb.createSheet("Summary");
      s.setColumnWidth(0, 28 * 256);
      s.setColumnWidth(1, 22 * 256);
      int ri = 0;
      XSSFFont big = wb.createFont();
      big.setBold(true);
      big.setFontHeightInPoints((short) 14);
      CellStyle bigStyle = wb.createCellStyle();
      bigStyle.setFont(big);
      XSSFFont blueTitle = wb.createFont();
      blueTitle.setBold(true);
      blueTitle.setFontHeightInPoints((short) 12);
      blueTitle.setColor(new XSSFColor(new byte[] {(byte) 0x0A, (byte) 0x84, (byte) 0xE0}, null));
      CellStyle titleStyle = wb.createCellStyle();
      titleStyle.setFont(blueTitle);
      XSSFCell c0 = s.createRow(ri++).createCell(0);
      c0.setCellValue(STATION);
      c0.setCellStyle(bigStyle);
      if (r.address() != null && !r.address().isEmpty()) s.createRow(ri++).createCell(0).setCellValue(r.address());
      XSSFCell c1 = s.createRow(ri++).createCell(0);
      c1.setCellValue(r.title());
      c1.setCellStyle(titleStyle);
      s.createRow(ri++).createCell(0).setCellValue(r.subtitle());
      ri++;
      for (Object[] sm : r.summary()) {
        XSSFRow row = s.createRow(ri++);
        row.createCell(0).setCellValue(String.valueOf(sm[0]));
        XSSFCell v = row.createCell(1);
        if (sm[1] instanceof Number num) v.setCellValue(num.doubleValue());
        else v.setCellValue(V.str(sm[1]));
        v.setCellStyle("money".equals(sm[2]) ? boldMoney : boldStyle);
      }

      for (Table tb : r.tables()) {
        XSSFSheet ws = wb.createSheet(tb.title().length() > 31 ? tb.title().substring(0, 31) : tb.title());
        XSSFRow h = ws.createRow(0);
        for (int i = 0; i < tb.columns().size(); i++) {
          Col c = tb.columns().get(i);
          XSSFCell hc = h.createCell(i);
          hc.setCellValue(c.header());
          hc.setCellStyle(head);
          ws.setColumnWidth(i, Math.max(c.width() + 4, c.header().length() + 2) * 256);
        }
        int rn = 1;
        for (Map<String, Object> row : tb.rows()) {
          XSSFRow xr = ws.createRow(rn++);
          for (int i = 0; i < tb.columns().size(); i++) {
            Col c = tb.columns().get(i);
            Object v = row.get(c.key());
            XSSFCell xc = xr.createCell(i);
            if ("money".equals(c.kind())) {
              xc.setCellValue(V.num(v));
              xc.setCellStyle(money);
            } else if (v instanceof Number num) {
              xc.setCellValue(num.doubleValue());
            } else {
              xc.setCellValue(v == null ? "" : V.str(v));
            }
          }
        }
        ws.createFreezePane(0, 1);
      }
      wb.write(out);
      return out.toByteArray();
    }
  }

  public File exportFile(String report, String date, String format) throws Exception {
    Report r = build(report, date);
    boolean pdf = "pdf".equals(format);
    return new File(r.fileBase() + (pdf ? ".pdf" : ".xlsx"),
        pdf ? "application/pdf" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        pdf ? toPdf(r) : toXlsx(r));
  }
}
